# Sample logs

This directory contains sanitized sample logs used for testing Wazuh decoders and rules.

The goal of these samples is to provide small, reproducible log inputs that can be used for:

- decoder validation
- rule validation
- regression testing
- dashboard field verification

All samples are based on **real log formats observed in a working homelab deployment**, but are sanitized before publication.

---

# Structure

Samples are organized by telemetry source:

```
samples/
├── homeassistant/
├── synology/
└── unifi/
```

Each scenario typically contains:

```
raw.log
expected.json
```

Where:

- `raw.log` contains one or more log lines
- `expected.json` describes the expected decoder, extracted fields, and rule matches

---

# How to use samples

Samples can be tested with:

```
/var/ossec/bin/wazuh-logtest
```

Example workflow:

1. copy the log line from `raw.log`
2. paste it into `wazuh-logtest`
3. verify:
   - decoder name
   - extracted fields
   - triggered rules

---

# Sanitization

All samples are sanitized before publishing.

Sanitization may include:

- replacing internal IP addresses
- replacing usernames
- normalizing timestamps
- simplifying user agent strings
- removing device identifiers

Public documentation IP ranges may be used such as:

```
192.0.2.0/24
198.51.100.0/24
203.0.113.0/24
```

---

# Why samples matter

Maintaining sample logs helps ensure that future rule or decoder changes do not silently break detection logic.

Whenever rules are modified, the samples can be re-tested to confirm expected behaviour.
