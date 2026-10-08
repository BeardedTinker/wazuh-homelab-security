# Safe installation and rollback

This guide describes the supported installation approach for the current
Wazuh 4.14.8 production baseline. Install one telemetry source at a time. Do
not copy the repository over `/var/ossec/etc`, and do not restart the manager
until its configuration tests pass.

The repository is still pre-release. Review the selected source files and pin
the commit you tested instead of deploying repeatedly from a moving branch.

## 1. Choose one source

Each source is optional. Install only the files and transport configuration for
the source you actually use.

| Source | Manager decoder | Manager rules | Collection input | Setup status |
|---|---|---|---|---|
| UniFi | `wazuh/decoders/0100-unifi-decoders.xml` | `wazuh/rules/0100-unifi-rules.xml` | `wazuh/ossec.conf.snippets/0200-localfiles-unifi.xml` | Requires an external syslog route to `/var/log/unifi.log` |
| Synology | `wazuh/decoders/0200-synology-decoders.xml` | `wazuh/rules/0200-synology-rules.xml` | `wazuh/ossec.conf.snippets/0300-localfiles-synology.xml` | Requires an external syslog route to `/var/log/synology.log` |
| Home Assistant | `wazuh/decoders/0300-homeassistant-decoders.xml` | `wazuh/rules/0300-homeassistant-rules.xml` | `wazuh/ossec.conf.snippets/0400-localfiles-journald.xml` | Journald input belongs on the emitting agent or in its shared agent configuration |
| SafeLine | Built-in Wazuh JSON decoder | `wazuh/rules/0400-safeline-rules.xml` | `wazuh/ossec.conf.snippets/0450-localfiles-safeline.xml` | Follow `safeline/README.md`; collector scheduling remains host-specific |
| UGREEN | `wazuh/decoders/0500-ugreen-decoders.xml` | `wazuh/rules/0500-ugreen-rules.xml` | `wazuh/ossec.conf.snippets/0500-localfiles-ugreen.xml` | Follow the end-to-end transport guide in `ugreen/README.md` |

The collection snippets are fragments, not complete `ossec.conf` files. Merge
the selected `<localfile>` block inside the correct `<ossec_config>` exactly
once. Do not add a Wazuh UDP/514 listener when `rsyslogd` already owns that
port.

## 2. Confirm prerequisites

Before changing the manager:

- confirm the installed Wazuh version
- confirm the selected log file or journald source already receives events
- check that the selected rule IDs and decoder names do not collide with local
  content
- record the exact repository commit being installed
- keep an administrator session open until post-restart verification completes

Useful checks:

```bash
/var/ossec/bin/wazuh-control info
git rev-parse HEAD
sudo ls -l /var/ossec/etc/decoders /var/ossec/etc/rules
```

For UniFi, make sure the checkout does not contain the obsolete decoder parent
that caused issue #1:

```bash
grep -n '<parent>kernel</parent>' wazuh/decoders/0100-unifi-decoders.xml
```

The expected result is no output. Regardless of that check, the authoritative
gate is `wazuh-analysisd -t` after installing the selected files.

## 3. Create a backup

Create a timestamped, root-only backup before the first change:

```bash
backup_dir="/root/wazuh-homelab-$(date +%Y%m%d-%H%M%S)"
sudo install -d -m 0700 "$backup_dir"
sudo cp -a /var/ossec/etc/ossec.conf "$backup_dir/"
sudo cp -a /var/ossec/etc/decoders "$backup_dir/"
sudo cp -a /var/ossec/etc/rules "$backup_dir/"
printf 'Backup: %s\n' "$backup_dir"
```

Keep the printed path. Do not store enrollment passwords, agent keys, or other
runtime secrets in this repository.

## 4. Install only the selected files

Copy the chosen decoder, when the source has one, and its rule file into the
corresponding manager directories. The following UniFi example illustrates the
operation; substitute only the two filenames listed for your chosen source:

```bash
sudo install -o root -g wazuh -m 0640 \
  wazuh/decoders/0100-unifi-decoders.xml \
  /var/ossec/etc/decoders/0100-unifi-decoders.xml

sudo install -o root -g wazuh -m 0640 \
  wazuh/rules/0100-unifi-rules.xml \
  /var/ossec/etc/rules/0100-unifi-rules.xml
```

Merge the selected collection snippet manually into the manager, emitting
agent, or shared agent configuration indicated in the source matrix. Never
replace a complete `ossec.conf` with a snippet.

Complete any source transport steps before continuing. For example, a localfile
entry does not create the syslog file it references.

## 5. Validate before restart

Run manager configuration tests first:

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo /var/ossec/bin/wazuh-authd -t
sudo /var/ossec/bin/wazuh-modulesd -t
```

All three commands must succeed. If any command fails, stop here and follow the
rollback section without restarting the manager.

Run the complete regression suite from the repository checkout:

```bash
sudo python3 tools/regression/run_samples.py
```

Compare the result with the audited baseline in `README.md`. A `FAIL` or an
unexpected `XPASS` requires review. A scenario explicitly classified as
`PENDING` remains unverified rather than passing.

## 6. Restart and verify

Restart only after configuration and regression validation succeed:

```bash
sudo systemctl restart wazuh-manager
sudo systemctl --no-pager --full status wazuh-manager
sudo /var/ossec/bin/wazuh-control status
```

Then verify:

- no new `ERROR` or `CRITICAL` entry appears in `/var/ossec/logs/ossec.log`
- the selected source continues writing events to its expected input
- one known sanitized sample produces its documented decoder and rule result
- expected alerts reach `alerts.json` and the Indexer, if indexing is enabled

Do not install the next source until this one is verified.

## 7. Roll back safely

If validation fails before restart, the running manager remains on its previous
configuration. Restore only the files changed during this installation:

1. Restore `ossec.conf` from the recorded backup if it was edited.
2. For each installed decoder or rule, restore the backed-up version when one
   existed; otherwise remove only that newly added file.
3. Undo only the selected source's transport or collection change.
4. Run all three manager configuration tests again.
5. Restart only if the manager had already loaded or attempted to load the bad
   configuration.
6. Verify manager health and logs after recovery.

Do not restore the complete backup over newer unrelated changes. If other work
occurred after the backup, compare and restore the affected files individually.

## Issue #1 status

Issue #1 reported that the former `unifi-wan-kernel` decoder referenced a
`kernel` parent unavailable in affected installations, preventing
`wazuh-analysisd` from starting. The redundant decoder has been removed from
the repository. Two users reproduced the original failure, but an independent
confirmation of the fix is still pending.

Keep the issue open until a reporter confirms that the current UniFi decoder
passes `wazuh-analysisd -t` on their manager. Do not treat repository-side
validation alone as confirmation of a successful fresh installation.
