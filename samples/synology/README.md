# Synology sample logs

This directory contains sanitized Synology DSM authentication logs used for testing Wazuh decoders and rules.

These samples focus on authentication behaviour such as:

- login success
- login failure
- repeated login failures (brute force patterns)

---

# Example scenario

The `bruteforce-login` sample simulates repeated failed authentication attempts from the same IP address.

This should trigger the Synology brute-force detection rule.

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
