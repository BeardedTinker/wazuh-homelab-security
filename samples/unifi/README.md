# UniFi sample logs

This directory contains sanitized sample logs for testing UniFi decoders and rules.

The goal of these samples is to provide small, reproducible inputs for:

- decoder validation
- rule validation
- regression testing after rule changes
- dashboard field verification

---

# Expected structure

Each scenario can contain:

- `raw.log`
- `expected.json`

Where:

- `raw.log` contains one or more example log lines
- `expected.json` describes the expected decoder, extracted fields, and matching rule IDs

---

# Covered scenarios

Recommended scenarios for this repository:

- WAN_LOCAL firewall drops
- Home Assistant probe attempts
- Synology DSM probe attempts
- UniFi IDS / IPS CEF events
- repeated targeting of Home Assistant
- repeated targeting of Synology DSM
- multi-service reconnaissance / probing

---

# Notes

These samples are intentionally sanitized.

That means they may differ from raw production logs in the following ways:

- internal IP addresses replaced
- usernames removed or generalized
- timestamps normalized
- public IPs replaced with safe examples where needed

The important part is that the log format remains realistic enough for decoder and rule testing.

---

# Testing workflow

Typical workflow when changing UniFi rules:

1. validate decoders
2. run sample log lines through `wazuh-logtest`
3. verify extracted fields such as:
   - `data.srcip`
   - `data.dstip`
   - `data.dstport`
   - `decoder.name`
4. verify matching rule IDs
5. verify that indexed alerts contain structured fields for dashboards

---

# Recommended future sample set

Suggested scenarios to include in this directory:

```
samples/unifi/
├── wan-local-basic/
│   ├── raw.log
│   └── expected.json
├── cef-homeassistant-target/
│   ├── raw.log
│   └── expected.json
├── cef-synology-target/
│   ├── raw.log
│   └── expected.json
└── cef-reconnaissance/
    ├── raw.log
    └── expected.json
```
