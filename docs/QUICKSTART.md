# Source-by-source quick start

This checklist is the shortest safe path for installing **one** telemetry source
from Wazuh Homelab Security. It does not replace the complete
[installation and rollback guide](../INSTALL.md) or the selected source's input
contract.

Supported baseline: **Wazuh Manager 4.14.9**. Pin the exact release or commit you
test. Do not deploy repeatedly from a moving branch.

## Safety rules

- Install one source at a time.
- Never copy the repository over `/var/ossec/etc`.
- Treat every file in `wazuh/ossec.conf.snippets/` as a fragment, not a complete
  configuration.
- Do not load the same decoder or rule from both a split file and a local
  combined file.
- Stop before restart if any daemon test or regression scenario fails.
- Keep credentials, enrollment secrets, agent keys, and private event data out
  of the repository.

## 1. Choose one source

Open the source guide and confirm that your real event format matches its
documented input contract before installing anything.

| Source | Setup guide | Collection boundary |
|---|---|---|
| UniFi | [`unifi/README.md`](../unifi/README.md) | External syslog route writes `/var/log/unifi.log` |
| Synology DSM | [`synology/README.md`](../synology/README.md) | External syslog route writes `/var/log/synology.log` |
| Home Assistant | [`homeassistant/README.md`](../homeassistant/README.md) | Journald input on the emitting agent or its shared configuration |
| SafeLine WAF | [`safeline/README.md`](../safeline/README.md) | Schema-v1 collector output read by a Wazuh agent |
| UGREEN UGOS Pro | [`ugreen/README.md`](../ugreen/README.md) | Documented Fluent Bit and rsyslog pipeline |
| Minecraft Java Paper | [`minecraft/README.md`](../minecraft/README.md) | Host agent reads the verified Paper `latest.log` path |

Do not continue until the selected source already produces events at the input
location described by its guide. Installing a decoder does not create the
source transport.

## 2. Record the baseline

From the pinned repository checkout, record both versions:

```bash
git describe --tags --always --dirty
sudo /var/ossec/bin/wazuh-control info
```

Confirm that the selected rule IDs and decoder names do not collide with local
content. The full [installation guide](../INSTALL.md) describes the required
preflight boundary. If the existing installation has custom merged files and
you cannot determine ownership, stop and compare before copying anything.

## 3. Back up before the first change

Create a timestamped, root-only backup:

```bash
backup_dir="/root/wazuh-homelab-$(date +%Y%m%d-%H%M%S)"
sudo install -d -m 0700 "$backup_dir"
sudo cp -a /var/ossec/etc/ossec.conf "$backup_dir/"
sudo cp -a /var/ossec/etc/decoders "$backup_dir/"
sudo cp -a /var/ossec/etc/rules "$backup_dir/"
printf 'Backup: %s\n' "$backup_dir"
```

Keep the printed path. Do not store the backup in this repository.

## 4. Install only the selected source

Follow the selected source guide and the file matrix in
[`INSTALL.md`](../INSTALL.md#1-choose-one-source):

1. Install only that source's decoder when it has one.
2. Install only that source's rule file.
3. Merge its collection snippet inside the correct `<ossec_config>` exactly
   once.
4. Complete only that source's transport steps.
5. Do not install another source yet.

SafeLine users must install `0480-safeline-rules.xml`. Do not also load the
former `0400` filename because both contain the same rule IDs.

## 5. Validate before restart

Run all manager configuration tests:

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo /var/ossec/bin/wazuh-authd -t
sudo /var/ossec/bin/wazuh-modulesd -t
```

Then run the complete regression suite from the pinned checkout:

```bash
sudo python3 tools/regression/run_samples.py
```

Expected repository baseline:

```text
PASS=25, FAIL=0, PENDING=2, XPASS=0
```

Stop if a daemon test fails, if `FAIL` is nonzero, or if an unexpected `XPASS`
appears. Do not restart to see whether the configuration might still work.

## 6. Restart and verify

Only after every validation gate succeeds:

```bash
sudo systemctl restart wazuh-manager
sudo systemctl --no-pager --full status wazuh-manager
sudo /var/ossec/bin/wazuh-control status
```

Verify all of the following before installing another source:

- no new `ERROR` or `CRITICAL` entry appears in `/var/ossec/logs/ossec.log`
- the selected source continues writing to its expected input
- one known sanitized sample produces its documented decoder and rule result
- expected alerts reach `alerts.json`
- expected alerts reach the Indexer when indexing is enabled

## 7. Roll back if verification fails

Restore only the files changed for this source. Restore the backed-up version
when one existed; otherwise remove only the newly installed file. Undo only the
selected source's collection or transport change, rerun all daemon tests, and
restart only if the manager already attempted to load the candidate
configuration.

Do not restore a complete backup over unrelated changes made after that backup.
Use the full [rollback procedure](../INSTALL.md#7-roll-back-safely) when any
step is uncertain.

## Completion checklist

- [ ] exact repository tag or commit recorded
- [ ] Wazuh version recorded
- [ ] one source selected and its input contract confirmed
- [ ] backup path recorded
- [ ] only selected source files installed
- [ ] all daemon tests passed
- [ ] regression baseline matched
- [ ] manager health and source ingestion verified
- [ ] rollback path retained

Only after every item is complete should another source be considered.
