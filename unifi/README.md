# UniFi telemetry setup

This guide connects supported UniFi security events to the Wazuh 4.14.8
baseline in this repository. It documents two distinct input formats. Confirm
which format you actually receive before installing the decoder and rules.

Follow the backup, validation, restart, and rollback gates in
[`INSTALL.md`](../INSTALL.md). Install UniFi independently before adding any
other telemetry source.

## Supported input contracts

### UniFi CEF IDS/IPS events

The `unifi-ucg-cef` decoder supports the production-tested UCG Ultra CEF
format. It currently requires:

- a pre-decoded program name of `CEF`
- the exact CEF header prefix `CEF:0|Ubiquiti|UCG-Ultra|`
- extension fields in the tested order: `src`, `dst`, `spt`, `dpt`, `proto`,
  and `act`

It extracts these Wazuh fields:

| CEF key | Wazuh field |
|---|---|
| `src` | `srcip` |
| `dst` | `dstip` |
| `spt` | `srcport` |
| `dpt` | `dstport` |
| `proto` | `protocol` |
| `act` | `action` |

This is not a generic decoder for every UniFi gateway or every valid CEF field
ordering. A different device product string or extension order requires a new
sanitized sample and decoder regression test before compatibility is claimed.

### Raw WAN_LOCAL firewall events

The `unifi-wan-local` decoder supports production-framed firewall messages
containing both:

```text
[WAN_LOCAL-D-<number>]
DESCR="[WAN_LOCAL]
```

The tested message also contains `SRC`, `DST`, `PROTO`, `SPT`, and `DPT` fields.
This path is separate from the CEF contract and is retained for deployments
whose syslog stream or archives contain the raw gateway firewall format.

## Configure UniFi log export

Current Ubiquiti documentation configures SIEM export under:

```text
Integration > System Logging / SIEM
```

Select **SIEM Server**, choose the required security categories, and enter the
address and port of your syslog receiver. UniFi exports these system logs in
CEF. See Ubiquiti's current
[UniFi System Logs & SIEM Integration](https://help.ui.com/hc/en-us/articles/33349041044119-UniFi-System-Logs-SIEM-Integration)
documentation because menu names and available categories can change between
UniFi Network versions.

The production deployment behind this repository uses `rsyslogd` as the only
owner of UDP/514. It writes accepted UniFi events to:

```text
/var/log/unifi.log
```

This repository does not currently ship a generic UniFi rsyslog receiver
drop-in. Receiver address selection, firewall policy, source filtering, and
transport security are host-specific. Do not expose an unauthenticated syslog
listener to untrusted networks, and do not configure a second Wazuh UDP/514
listener when rsyslog already owns the port.

## Verify the received format

Confirm that the file exists and is receiving new events before changing
Wazuh:

```bash
sudo test -r /var/log/unifi.log
sudo tail -n 20 /var/log/unifi.log
```

Compare a received event with the sanitized scenarios under
`samples/unifi/`. Do not publish an unsanitized line. In particular, check the
CEF product string and key order or the raw `WAN_LOCAL` markers described
above.

If neither contract matches, stop. Capture the minimum required event fields,
sanitize addresses and identifiers, and add a regression scenario before
changing the decoder.

## Install the manager files

After creating the backup described in `INSTALL.md`, install only the UniFi
decoder and rules:

```bash
sudo install -o root -g wazuh -m 0640 \
  wazuh/decoders/0100-unifi-decoders.xml \
  /var/ossec/etc/decoders/0100-unifi-decoders.xml

sudo install -o root -g wazuh -m 0640 \
  wazuh/rules/0100-unifi-rules.xml \
  /var/ossec/etc/rules/0100-unifi-rules.xml
```

Merge the following fragment inside the manager's existing `<ossec_config>`
exactly once:

```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/unifi.log</location>
</localfile>
```

The tracked fragment is
`wazuh/ossec.conf.snippets/0200-localfiles-unifi.xml`. Do not replace the full
manager configuration with this fragment.

## Validate before restart

First verify that the obsolete parent decoder from issue #1 is absent:

```bash
grep -n '<parent>kernel</parent>' \
  /var/ossec/etc/decoders/0100-unifi-decoders.xml
```

The expected result is no output. Then run the authoritative manager test and
the UniFi regression scenarios:

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo python3 tools/regression/run_samples.py --samples samples/unifi
```

Do not restart if either command fails. Restore the files changed during this
installation using the rollback procedure in `INSTALL.md`.

After both checks pass, complete the remaining daemon tests from `INSTALL.md`,
restart the manager, and verify that no new `ERROR` or `CRITICAL` message
appears in `/var/ossec/logs/ossec.log`.

## Expected detection families

The installed rules cover:

- raw WAN_LOCAL drops and high-rate same-source probing (`100110`-`100150`)
- CEF IDS/IPS events and targeted services (`100300`-`100307`)
- same-source, multi-port reconnaissance (`100310`)

Some correlations require several events within their configured timeframe.
Use the multi-line scenarios under `samples/unifi/` rather than judging those
rules from a single event.

## Troubleshooting

### `Parent decoder name invalid: 'kernel'`

The checkout or installed decoder is stale. The removed
`unifi-wan-kernel` decoder caused issue #1 because the expected `kernel` parent
was unavailable in affected installations. Replace only the installed UniFi
decoder with the current repository version, run `wazuh-analysisd -t`, and do
not restart until validation passes.

### Event reaches the file but no UniFi decoder matches

Compare the complete sanitized message shape with the supported contracts. The
most common causes are a different CEF product string, different extension key
ordering, or a raw firewall format without the tested `WAN_LOCAL` markers.

### Decoder matches but a correlation rule does not

Check the required event count, timeframe, source IP, and destination-port
conditions in `wazuh/rules/0100-unifi-rules.xml`. Run the matching multi-event
regression scenario in one `wazuh-logtest-legacy` process so correlation state
is retained.
