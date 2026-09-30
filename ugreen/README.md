# UGREEN UGOS Pro telemetry

This integration forwards a narrow, security-focused subset of UGREEN UGOS Pro
logs to an existing Wazuh manager. It was validated with a DXP4800 GT running
UGOS Pro and Wazuh 4.14.8.

## Data flow

```text
UGREEN auth.log, kern.log, and log_serv journald
  → Fluent Bit 5.1.2 on the NAS
  → RFC3164 over UDP/514
  → existing rsyslogd listener
  → /var/log/ugreen.log
  → Wazuh localfile
  → UGREEN rules 100600–100631
```

`rsyslogd` remains the sole owner of UDP/514. Do not add a Wazuh `remote`
syslog listener on that port.

## Collected events

The Fluent Bit example forwards only:

- SSH authentication success and failure from `auth.log`
- group creation, user creation, and password changes from `auth.log`
- block-device I/O errors from `kern.log`
- canonical UGOS web login success/failure records from journald `_COMM=log_serv`

It intentionally excludes broad journald output, `sudo COMMAND=` records,
tokens, CRON, camera/indexing noise, and duplicate `log_serv` SSH events. No
UGOS firewall rule is included because no authentic firewall event was observed.

## 1. Fluent Bit on UGOS Pro

Copy `fluent-bit/` to a persistent Docker project directory on the NAS. Replace
the RFC 5737 example manager address `192.0.2.39` in `fluent-bit.conf` with the
rsyslog host. The image is pinned by both version and digest.

Create the writable offset directory without creating a new UGOS account:

```bash
mkdir -p state
sudo chown 65534:65534 state
chmod 0750 state
docker compose up -d
```

The container runs as UID/GID `65534`, adds only the host groups needed to read
the deployed log sources, mounts logs read-only, drops all capabilities, and
persists tail/journal offsets. Group IDs vary between systems; verify `10` and
`999` against the NAS before deployment.

RFC3164 is deliberate. In the validated environment RFC5424 inserted a UTF-8
BOM before message text, preventing reliable decoder matches.

## 2. Existing rsyslog receiver

Install `rsyslog/30-ugreen.conf` after replacing `192.0.2.30` with the NAS
address. This snippet routes an already-received source; it does not open a
listener. Validate and reload rsyslog using the commands appropriate for the
host, then install `rsyslog/ugreen.logrotate` under `/etc/logrotate.d/`.

Expected file ownership is `syslog:adm` with mode `0640`.

## 3. Wazuh manager

Install:

```text
wazuh/decoders/0500-ugreen-decoders.xml
wazuh/rules/0500-ugreen-rules.xml
```

Merge `wazuh/ossec.conf.snippets/0500-localfiles-ugreen.xml` into the manager's
`<ossec_config>`. Test before restart:

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo /var/ossec/bin/wazuh-logcollector -t
sudo python3 tools/regression/run_samples.py
```

Rules `5715`, `5901`, and `5902` remain built-in Wazuh detections for SSH
success, group creation, and user creation. The custom range only fills gaps:

| Rule | Level | Purpose |
|---|---:|---|
| `100600` | 3 | UGOS web login success |
| `100601` | 5 | UGOS web login failure |
| `100610` | 12 | five same-source web failures in five minutes |
| `100611` | 10 | web success after a same-source failure |
| `100620` | 5 | root password change from the UGREEN localfile |
| `100630` | 10 | storage I/O error |
| `100631` | 13 | three same-device storage I/O errors in five minutes |

Rule `100611` correlates only by source IP because the canonical failure record
does not contain a reliable username. Rule `100620` remains level 5 because
legitimate UGOS upgrades can rotate the root password.

## Verification

1. Confirm Fluent Bit reports no startup or output errors and its state files persist.
2. Confirm a test UGOS web login appears once in `/var/log/ugreen.log` without a BOM.
3. Confirm the Wazuh alert has `location=/var/log/ugreen.log`.
4. Confirm web-login fields use `data.srcip` and, for success, `data.dstuser`.
5. Run the sanitized scenarios under `samples/ugreen/`.

Do not generate destructive storage faults or create throwaway UGOS accounts for
testing. Use the sanitized offline regression samples for those paths.
