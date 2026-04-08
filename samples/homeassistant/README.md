# Home Assistant sample logs

This directory contains sanitized Home Assistant security-relevant logs used for testing Wazuh decoders and rules.

These samples focus on events such as:

- invalid authentication
- repeated invalid authentication
- websocket-related suspicious activity
- brute-force style behaviour

---

# Example scenario

The `auth-bruteforce` sample simulates repeated invalid authentication attempts against Home Assistant from the same IP address.

This should trigger:

- the base invalid authentication rule
- the repeated brute-force detection rule

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
- removing identifying usernames
- normalizing timestamps
- simplifying user-agent strings where needed
