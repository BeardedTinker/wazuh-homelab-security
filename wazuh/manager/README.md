# Production manager baseline

The production baseline is Wazuh **4.14.8**. Custom rules and decoders are kept
in the sibling `rules/` and `decoders/` directories. The `ossec.conf.snippets/`
directory contains the publishable production-relevant sections that must be
merged into the manager configuration.

`local_internal_options.conf` is part of the audited baseline but contains no
custom runtime override.

## Agent transport and enrollment

- Existing agents use the secure TCP listener on port **1514**.
- New enrollment uses `authd` on TCP **1515** with `use_password=yes`.
- The enrollment password belongs in `/var/ossec/etc/authd.pass`; that file is
  intentionally excluded from this repository.
- Changing the enrollment password does not rotate existing agent keys.

## Syslog ingress

`rsyslogd`, not Wazuh `remoted`, owns UDP/514. It writes UniFi and Synology
events to `/var/log/unifi.log` and `/var/log/synology.log`; Wazuh reads those
files with `<localfile>` blocks. Do not add a second Wazuh UDP/514 listener.

## Validation

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo /var/ossec/bin/wazuh-authd -t
sudo /var/ossec/bin/wazuh-modulesd -t
sudo python3 tools/regression/run_samples.py
```

Restart only after all configuration tests pass. After restart, verify manager
health, loaded rule count, secure TCP/1514, authd TCP/1515, and new
`ERROR`/`CRITICAL` messages in the Wazuh log.
