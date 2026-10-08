# Home Assistant telemetry setup

This guide connects supported Home Assistant security events to the Wazuh
4.14.8 baseline in this repository. The production-confirmed path uses a Wazuh
agent with read-only journald access and preserves `homeassistant` as the
pre-decoded program name.

Follow the backup, validation, restart, and rollback gates in
[`INSTALL.md`](../INSTALL.md). Home Assistant is an independent source; the
UniFi integration is required only for the optional cross-source attack-chain
rule.

## Supported input contract

Both Home Assistant decoders currently require:

- the pre-decoded program name `homeassistant`
- an English invalid-authentication message
- a source address repeated in parentheses
- a valid IPv4 address inside those parentheses

The production-confirmed sanitized form is:

```text
Jan 21 12:03:11 homeassistant homeassistant[1234]: 2026-01-21 12:03:11.100 WARNING (MainThread) [homeassistant.components.http.ban] Login attempt or request with invalid authentication from 198.51.100.24 (198.51.100.24). Requested URL: '/api/websocket'. (Mozilla/5.0)
```

The `homeassistant-http-ban` decoder additionally requires logger text:

```text
homeassistant.components.http.ban
```

It extracts the parenthesized IPv4 address as `srcip`. This path is covered by
production-derived regression scenarios.

The separate `homeassistant-auth-failed` decoder looks for the invalid
authentication phrase outside the ban-specific match. That path is not yet
production-confirmed. Its scenario remains `PENDING` until an authentic event
preserving the transport header, logger, source-host text, punctuation, and
parenthesized IP is available.

The current contract does not claim support for IPv6, localized messages, log
lines without program name `homeassistant`, or reformatted authentication
events.

## Recommended transport: HA Wazuh Agent add-on

The companion
[`ha-wazuh-agent-addon`](https://github.com/BeardedTinker/ha-wazuh-agent-addon)
runs the official Wazuh agent inside Home Assistant OS. Release `v1.2.2` bundles
Wazuh Agent `4.14.8-1` and requires a Wazuh Manager at version 4.14.8 or newer.
Follow that repository's installation, enrollment, persistence, and upgrade
documentation rather than copying add-on configuration from this guide.

The add-on has read-only journald access and configures its own Wazuh
`<localfile>` block. When its startup log says:

```text
Using journald log source
```

do not also merge
`wazuh/ossec.conf.snippets/0400-localfiles-journald.xml` into the add-on. That
would duplicate collection configuration.

The add-on currently selects `/config/home-assistant.log` when that file is
present and otherwise selects journald. Its file-source startup message is:

```text
Using file log source: /config/home-assistant.log
```

The decoder contract in this repository is validated only with the journald
shape that pre-decodes to program `homeassistant`. The file fallback is not a
confirmed substitute. If it is selected, verify a sanitized event with
`wazuh-logtest-legacy` before claiming decoder compatibility.

## Generic Wazuh agent alternative

For a separately managed Wazuh agent that can read the Home Assistant host
journal, merge this fragment into that emitting agent's configuration or its
shared agent configuration:

```xml
<localfile>
  <log_format>journald</log_format>
  <location>journald</location>
</localfile>
```

The tracked fragment is
`wazuh/ossec.conf.snippets/0400-localfiles-journald.xml`. It belongs on the
emitting agent, not automatically on the Wazuh manager. Journal visibility,
container permissions, agent enrollment, and persistent keys remain the
responsibility of that deployment.

## Install the manager files

After creating the manager backup described in `INSTALL.md`, install only the
Home Assistant decoder and rules:

```bash
sudo install -o root -g wazuh -m 0640 \
  wazuh/decoders/0300-homeassistant-decoders.xml \
  /var/ossec/etc/decoders/0300-homeassistant-decoders.xml

sudo install -o root -g wazuh -m 0640 \
  wazuh/rules/0300-homeassistant-rules.xml \
  /var/ossec/etc/rules/0300-homeassistant-rules.xml
```

These files are manager-side detection content. Installing them does not
enroll an agent or grant journal access.

## Verify the received format

Check the agent or add-on startup log to confirm the selected source. Then
compare a sanitized received authentication event with
`samples/homeassistant/auth-bruteforce/raw.log`.

Verify all of the following:

- Wazuh pre-decodes the program as `homeassistant`
- the logger is `homeassistant.components.http.ban` for the confirmed path
- the invalid-authentication phrase is unchanged
- the source IPv4 address remains inside parentheses

Do not publish raw Home Assistant logs. URLs, user agents, internal addresses,
hostnames, integration data, and custom-component errors may contain sensitive
information.

If the shape differs, stop and add a minimal sanitized production sample before
changing the decoder.

## Validate before restart

Run the authoritative manager test and Home Assistant regression scenarios:

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo python3 tools/regression/run_samples.py --samples samples/homeassistant
```

Do not restart if the manager test or a non-PENDING regression fails. Restore
the files changed during this installation using `INSTALL.md`.

Do not generate repeated live login failures merely to test the rules. That can
trigger Home Assistant IP banning and lock out the testing client. Use the
sanitized multi-event regression scenarios instead.

After validation passes, complete the remaining daemon tests from `INSTALL.md`,
restart the manager, and verify that no new `ERROR` or `CRITICAL` message
appears in `/var/ossec/logs/ossec.log`.

## Detection and regression status

The production-confirmed scenarios cover:

- ban-component invalid authentication, rule `100400`
- five same-source failures in five minutes, rule `100410`
- UniFi port 8123 probing followed by Home Assistant brute force from the same
  source, rule `100433`

Rule `100433` uses global frequency history because UniFi and Home Assistant
events can originate from different Wazuh agents. It remains optional: without
the UniFi decoder, rules, matching event group, and same source IP, the base
Home Assistant detections still operate but the cross-source rule does not.

The following paths are not yet production-confirmed:

- non-ban invalid authentication decoder and rule `100420`
- repeated non-ban invalid authentication rule `100421`
- `/config/home-assistant.log` as a transport that preserves the required
  pre-decoded program name

Rule `100419` is a narrow level-zero suppression for known Moonraker websocket
reconnect errors while an intentionally powered-off printer is unavailable. It
does not suppress unrelated Home Assistant errors and is not an authentication
detection.

## Troubleshooting

### Events arrive but no Home Assistant decoder matches

Check the pre-decoded program name first. A raw Home Assistant file line may
lack the syslog or journald header that produces `homeassistant`. Then verify
the logger, English phrase, punctuation, and parenthesized IPv4 structure.

### Add-on repeatedly enrolls or reports duplicate agent names

Use the enrollment and persisted-key troubleshooting in the add-on repository.
Do not delete `client.keys` or force re-enrollment as a decoder troubleshooting
step.

### Rule `100433` does not trigger

Confirm that the UniFi event matches group `unifi_ha_probe_event`, the Home
Assistant sequence reaches rule `100410`, both sides share `srcip`, and the
events occur within 900 seconds. Test the complete sequence in one
`wazuh-logtest-legacy` process so history is retained.
