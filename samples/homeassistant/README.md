# Home Assistant sample logs

This directory contains sanitized Home Assistant security-relevant logs used for testing Wazuh decoders and rules.

These samples focus on events such as:

- invalid authentication
- repeated invalid authentication
- brute-force style behaviour
- UniFi probe followed by Home Assistant brute force

---

# Example scenario

The `auth-bruteforce` sample simulates repeated invalid authentication attempts against Home Assistant from the same IP address.

This should trigger:

- the base invalid authentication rule
- the repeated brute-force detection rule

The following scenarios are production-confirmed PASS cases:

- `auth-bruteforce/` for rules 100400 and 100410;
- `unifi-attack-chain/` for cross-source correlation rule 100433.

Rule 100433 is confirmed with production `wazuh-logtest-legacy`. A real
cross-agent runtime sequence was not executed because it could trigger Home
Assistant IP banning.

`auth-failed/` intentionally remains PENDING until a genuine production event
for decoder `homeassistant-auth-failed` and rule 100420 is available. Do not
manufacture it from the existing HTTP-ban sample; its TODO file specifies the
transport and message details that must be preserved.

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
