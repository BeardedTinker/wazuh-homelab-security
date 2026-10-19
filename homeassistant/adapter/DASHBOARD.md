# Sanitized Home Assistant dashboard example

[`dashboard-example.yaml`](dashboard-example.yaml) is a complete, optional
Lovelace YAML dashboard example for the version 1 adapter contract. It uses only
built-in `markdown` and `entities` cards and requires no custom frontend
resources.

The example is deliberately limited to counts, health, timestamps, rule summary,
and destination-port state. It does not display source-IP entities, raw alert
hits, player names, device identifiers, internal addresses, or credentials.
The Minecraft card uses only the source-summary entity state; operational server
status remains outside the Wazuh security adapter.

## Use

Install and verify the adapter first. Then either:

- register the file as a YAML-mode dashboard using Home Assistant's documented
  dashboard configuration; or
- recreate the cards in a storage-mode dashboard through the dashboard editor.

Do not edit Home Assistant's internal `.storage` files. If entity IDs were
renamed locally, update a private copy instead of changing the published
contract. Validate the complete Home Assistant configuration before loading a
new YAML-mode dashboard.

This is a portable example, not a supported dashboard export. Rendering depends
on the Home Assistant frontend version, theme, screen width, and which optional
telemetry sources are installed. An absent source should show zero; a failed
adapter response should remain unavailable rather than appear as a valid zero.

## Publication safety

The YAML file itself contains no deployment identifiers or event data. A live
dashboard can still display information from the user's own entities. Before
publishing screenshots or exported configuration, remove source addresses,
hostnames, usernames, player names, tokens, URLs, and any raw alert attributes.
