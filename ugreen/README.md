# UGREEN UGOS Pro telemetry

This guide forwards a narrow, security-focused subset of UGREEN UGOS Pro logs
to the Wazuh 4.14.8 baseline in this repository. The production-confirmed
deployment uses a DXP4800 GT, Fluent Bit 5.1.2, an existing rsyslog receiver,
and manager-side custom rules.

Follow the backup, validation, restart, and rollback gates in
[`INSTALL.md`](../INSTALL.md). UGREEN is an independent optional source.

## Compatibility boundaries

The tracked pipeline was validated with:

- UGREEN DXP4800 GT running UGOS Pro
- Fluent Bit 5.1.2 with the pinned image digest in `compose.yaml`
- RFC 3164 syslog over UDP/514
- Wazuh Manager 4.14.8

The current web-login decoders require:

- the pre-decoded program name `log_serv`
- the exact English `insertLog login User [...] from [...]` message family
- a valid IPv4 source address
- exact success or failure wording covered by the sanitized fixtures

The Fluent Bit allowlist accepts an address-shaped value containing IPv4 or
IPv6 characters, but the Wazuh decoders currently extract IPv4 only. Forwarding
an IPv6 event is not evidence that it will decode. Add an authentic sanitized
fixture before extending this contract.

The storage decoder is a child of Wazuh's built-in `kernel` decoder. That parent
exists in the audited 4.14.8 ruleset. Compatibility with another Wazuh version
must be verified rather than inferred.

## Data flow

```text
UGREEN auth.log, kern.log, and log_serv journald
  → Fluent Bit 5.1.2 on the NAS
  → RFC 3164 over UDP/514
  → existing rsyslogd listener
  → /var/log/ugreen.log
  → Wazuh manager localfile
  → built-in and custom UGREEN rules
```

`rsyslogd` remains the only owner of UDP/514. Do not add a Wazuh `remote`
syslog listener on the same port.

UDP syslog is unencrypted, unauthenticated, and spoofable. Restrict it to a
trusted management network, filter the sender at the host firewall and rsyslog,
and never expose the listener to the internet. The rsyslog source-address check
in this repository is routing hygiene, not cryptographic authentication.

## Collected events

The Fluent Bit example forwards only:

- SSH authentication success and failure from `auth.log`
- group creation, user creation, and password changes from `auth.log`
- block-device I/O errors from `kern.log`
- canonical UGOS web login success and failure from journald `_COMM=log_serv`

It intentionally excludes broad journald output, `sudo COMMAND=` records,
tokens, CRON, camera and indexing noise, and duplicate `log_serv` SSH events.
No UGOS firewall rule is included because no authentic firewall event was
observed.

## 1. Deploy Fluent Bit on UGOS Pro

Copy `ugreen/fluent-bit/` to a persistent Docker project directory on the NAS.
Replace the RFC 5737 example receiver address `192.0.2.39` in
`fluent-bit.conf` with the rsyslog host. Do not change the pinned image digest
without separately reviewing and testing the image update.

The container runs as UID/GID `65534`, mounts logs read-only, drops all Linux
capabilities, enables `no-new-privileges`, and persists tail and journal
offsets. Supplemental group IDs vary by system. Verify that tracked values `10`
and `999` correspond only to the groups needed to read the deployed sources.

Create the writable state directory without creating a new UGOS account:

```bash
mkdir -p state
sudo chown 65534:65534 state
chmod 0750 state
docker compose config
docker compose up -d
```

Confirm Fluent Bit starts without input, parser, permission, storage, or output
errors. Restart the container once and verify it reuses the persisted database
files instead of replaying old logs.

RFC 3164 is deliberate. In the validated environment RFC 5424 inserted a UTF-8
byte-order mark before message text, preventing reliable decoder matches. Do not
switch the format without capturing and regression-testing the resulting wire
message.

## 2. Configure the existing rsyslog receiver

Before installing the route, confirm an existing rsyslog input already owns the
chosen port. The tracked snippet does not open a listener.

Replace the RFC 5737 example NAS address `192.0.2.30` in
`ugreen/rsyslog/30-ugreen.conf`, then install it using the path and ownership
required by the receiver distribution. Validate rsyslog configuration before
reload.

Install `ugreen/rsyslog/ugreen.logrotate` under `/etc/logrotate.d/` and validate
it with the receiver's logrotate tooling. Expected log ownership is
`syslog:adm` with mode `0640`.

After reload, verify that one normal UGOS event reaches
`/var/log/ugreen.log` exactly once and does not begin with a byte-order mark. Do
not publish unsanitized authentication or storage logs.

## 3. Install the Wazuh manager files

After creating the backup described in `INSTALL.md`, install only the UGREEN
decoder and rules:

```bash
sudo install -o root -g wazuh -m 0640 \
  wazuh/decoders/0500-ugreen-decoders.xml \
  /var/ossec/etc/decoders/0500-ugreen-decoders.xml

sudo install -o root -g wazuh -m 0640 \
  wazuh/rules/0500-ugreen-rules.xml \
  /var/ossec/etc/rules/0500-ugreen-rules.xml
```

Merge the following fragment inside the manager's existing `<ossec_config>`
exactly once:

```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/ugreen.log</location>
</localfile>
```

The tracked fragment is
`wazuh/ossec.conf.snippets/0500-localfiles-ugreen.xml`. Do not replace the full
manager configuration with this fragment.

## Validate before restart

Run the manager analysis and logcollector tests, followed by the targeted
UGREEN regression suite:

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo /var/ossec/bin/wazuh-logcollector -t
sudo python3 tools/regression/run_samples.py --samples samples/ugreen
```

Do not restart if any command fails. Restore the files changed during this
installation using the rollback procedure in `INSTALL.md`.

After validation passes, complete the remaining daemon tests from `INSTALL.md`,
restart the manager, and verify that no new `ERROR` or `CRITICAL` message
appears in `/var/ossec/logs/ossec.log`.

## Detection and regression status

The current production-derived custom regression scenarios cover:

| Rule | Level | Purpose |
|---|---:|---|
| `100600` | 3 | UGOS web login success |
| `100610` | 12 | Five same-source web failures in five minutes |
| `100611` | 10 | Web success after a same-source failure |
| `100631` | 13 | Three same-device storage I/O errors in five minutes |

Those scenarios also exercise the required base decoders and parent rules,
including web failure rule `100601` and storage error rule `100630`.

Rule `100611` correlates only by source IP because the canonical failure record
does not contain a reliable username. Rule `100620` remains level 5 because
legitimate UGOS upgrades can rotate the root password.

Built-in Wazuh rules `5715`, `5901`, and `5902` provide SSH success, group
creation, and user creation detections for matching forwarded records. They are
not replacements for the custom UGREEN regression scenarios and their behavior
must be rechecked when the Wazuh baseline changes.

## End-to-end verification

1. Confirm Fluent Bit reports no startup or output errors and retains its state.
2. Confirm one normal event appears once in `/var/log/ugreen.log` without a BOM.
3. Confirm Wazuh reports `location=/var/log/ugreen.log`.
4. Confirm web-login fields use `data.srcip` and, for success,
   `data.dstuser`.
5. Run all sanitized scenarios under `samples/ugreen/`.

Do not create destructive storage faults, rotate credentials, or create
throwaway UGOS accounts merely to test detections. Use sanitized offline
regression scenarios for those paths.

## Troubleshooting

### Fluent Bit cannot read a source

Check the actual NAS group IDs and read permissions instead of broadening the
container to privileged mode. Preserve the read-only host mounts, dropped
capabilities, and `no-new-privileges` setting.

### Events reach rsyslog but no web decoder matches

Verify the message has no byte-order mark, pre-decodes to program `log_serv`,
uses the supported English wording, and contains an IPv4 address. An event that
passes the Fluent Bit grep filter can still be outside the stricter decoder
contract.

### Storage events do not match

Confirm the event retains the kernel syslog structure and the text
`I/O error, dev <device>,`. Then verify that the audited Wazuh version loads its
built-in `kernel` decoder before the custom `ugreen-storage-io` child.

### Duplicate events appear after restart

Confirm the `state/` directory is writable by UID/GID `65534`, the database
files persist across container recreation, and only one Fluent Bit deployment
is forwarding the selected sources.
