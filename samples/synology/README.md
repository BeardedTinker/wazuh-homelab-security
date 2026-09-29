# Synology sample logs

This directory contains sanitized Synology DSM authentication logs used for testing Wazuh decoders and rules.

These samples focus on authentication behaviour such as:

- login success
- login failure
- repeated login failures (brute force patterns)

---

# Scenarios

The root `raw.log` is the current production `Connection:` format and validates
base success/failure rules 100200 and 100201.

`failure-success/` reuses sanitized production-format events and validates rule
100220: at least two failures followed by success for the same user and IP.

`bruteforce-login/` contains an alternative or legacy `DSM Login:` / `failed to
log in via [DSM]` format. It is PENDING and must not be treated as current
production coverage or used to justify widening the production decoder. Replace
it with repeated sanitized `Connection:` production events before enabling it.

---

# Structure

Each scenario contains:

raw.log
expected.json

Where:

- raw.log contains the original log lines
- expected.json describes the expected decoder, extracted fields and matching rules

---

# Notes

Logs are sanitized before publishing.

This includes:

- replacing internal IP addresses
- removing real usernames
- normalizing timestamps
