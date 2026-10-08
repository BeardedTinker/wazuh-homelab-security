# Synology DSM telemetry setup

This guide connects supported Synology DSM authentication events to the Wazuh
4.14.8 baseline in this repository. The decoder intentionally follows one
production-confirmed message contract rather than attempting to match every DSM
version, language, or service.

Follow the backup, validation, restart, and rollback gates in
[`INSTALL.md`](../INSTALL.md). Install Synology independently before adding any
other telemetry source.

## Supported input contract

The `synology-dsm-auth` decoder requires a syslog event with:

- the pre-decoded program name `Connection`
- the English message fragment `User [<name>] from [<IPv4 address>]`
- a valid IPv4 source address

The production-confirmed sanitized form is:

```text
2026-02-26T11:49:14+00:00 nas-1 Connection: User [user_admin] from [203.0.113.37] failed to sign in to [DSM] via [password] due to authorization failure.
```

The decoder extracts:

| Message value | Wazuh field |
|---|---|
| User inside the first brackets | `dstuser` |
| IPv4 address after `from` | `srcip` |

The rules then distinguish these exact English message fragments:

| Message fragment | Rule | Meaning |
|---|---:|---|
| `signed in to [DSM]` | `100200` | DSM login success |
| `failed to sign in to [DSM]` | `100201` | DSM login failure |

The current contract does not cover IPv6, localized DSM messages, other DSM
services, or the alternative `DSM Login:` / `failed to log in via [DSM]`
format. Do not widen the decoder solely from synthetic or legacy examples.

## Configure DSM Log Center

Synology documents log forwarding under:

```text
Log Center > Log Sending
```

Enable **Send logs to a syslog server**, enter the receiver and port, select a
matching transport, and include connection logs in the filter. Use **Send test
log** before applying the configuration. See Synology's current
[Log Sending](https://kb.synology.com/en-global/DSM/help/LogCenter/logcenter_client?version=7)
documentation for the exact DSM interface and supported options.

DSM supports UDP or TCP and BSD (RFC 3164) or IETF (RFC 5424) syslog. TCP can
also use TLS when the receiver is configured with the matching certificate.
Those wire options do not by themselves guarantee decoder compatibility: the
event reaching Wazuh must still pre-decode to program `Connection` and retain
the supported message contract.

The production deployment behind this repository uses `rsyslogd` as the only
owner of UDP/514 and writes accepted Synology events to:

```text
/var/log/synology.log
```

This repository does not currently ship a generic Synology rsyslog receiver
drop-in. Receiver address selection, source filtering, file ownership,
rotation, and transport security are host-specific. Do not expose an
unauthenticated syslog listener to untrusted networks, and do not configure a
second Wazuh UDP/514 listener when rsyslog already owns the port.

## Verify the received format

Confirm that the file exists and receives current DSM events before changing
Wazuh:

```bash
sudo test -r /var/log/synology.log
sudo tail -n 20 /var/log/synology.log
```

Compare a received authentication event with `samples/synology/raw.log`. Do not
publish an unsanitized event. Verify all of the following:

- the program name remains `Connection`
- the message contains `User [...] from [...]`
- the source address is IPv4
- success and failure wording matches the supported English fragments

If the shape differs, stop and add a minimal sanitized production sample before
changing the decoder or rules.

## Install the manager files

After creating the backup described in `INSTALL.md`, install only the Synology
decoder and rules:

```bash
sudo install -o root -g wazuh -m 0640 \
  wazuh/decoders/0200-synology-decoders.xml \
  /var/ossec/etc/decoders/0200-synology-decoders.xml

sudo install -o root -g wazuh -m 0640 \
  wazuh/rules/0200-synology-rules.xml \
  /var/ossec/etc/rules/0200-synology-rules.xml
```

Merge the following fragment inside the manager's existing `<ossec_config>`
exactly once:

```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/synology.log</location>
</localfile>
```

The tracked fragment is
`wazuh/ossec.conf.snippets/0300-localfiles-synology.xml`. Do not replace the
full manager configuration with this fragment.

## Validate before restart

Run the authoritative manager test and Synology regression scenarios:

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo python3 tools/regression/run_samples.py --samples samples/synology
```

Do not restart if either command fails. Restore the files changed during this
installation using the rollback procedure in `INSTALL.md`.

After both checks pass, complete the remaining daemon tests from `INSTALL.md`,
restart the manager, and verify that no new `ERROR` or `CRITICAL` message
appears in `/var/ossec/logs/ossec.log`.

## Detection and regression status

The current production-format scenarios confirm:

- login success rule `100200`
- login failure rule `100201`
- success after repeated failures for the same user and IP, rule `100220`

Rule `100210` detects five failures from the same source IP within five minutes.
Its current `samples/synology/bruteforce-login/` scenario uses an alternative or
legacy message format and is deliberately classified as `PENDING`. The rule is
not considered regression-confirmed until that scenario is replaced with
authentic, sanitized, repeated `Connection:` production events.

`PENDING` is not a failure, but it is also not evidence of compatibility. Do
not rewrite that sample into the desired format merely to make the test pass.

## Troubleshooting

### Event reaches the file but no Synology decoder matches

Check the pre-decoded program name first. The decoder requires `Connection`,
not `DSM Login` or another package name. Then compare the sanitized message with
the supported bracketed user and IPv4 structure.

### Decoder matches but no base rule matches

The success and failure rules match exact English DSM phrases. Localized text or
different DSM wording requires a separate production sample, compatibility
decision, and regression expectation.

### Correlation does not trigger

Keep all events for one scenario in the same `wazuh-logtest-legacy` process so
history is retained. For rule `100220`, failures and success must share both
`srcip` and `dstuser` within five minutes. For rule `100210`, five failures must
share `srcip` within five minutes.
