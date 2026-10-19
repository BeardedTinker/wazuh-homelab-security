# Detection reference

This reference summarizes the production-derived detection coverage, correlation
behavior, rule IDs, and known limitations. The source setup guides remain the
authority for exact input formats and installation.

## Production data flow

```text
UniFi / Synology ──UDP/514──> rsyslogd ──> /var/log/*.log ──> Wazuh localfile
UGREEN ──Fluent Bit RFC3164 UDP/514──> rsyslogd ──> /var/log/ugreen.log
Home Assistant ──agent secure TCP/1514──────────────────────> Wazuh remoted
SafeLine Open API ──schema-v1 collector──> attacks.json ──> Wazuh Agent 023
Minecraft Paper latest.log ──host Wazuh Agent───────────────> Wazuh remoted
New agents ──password-protected TCP/1515────────────────────> Wazuh authd
Wazuh alerts ──Filebeat──> Wazuh Indexer ingest pipeline ──> GeoLocation.*
```

Wazuh does not own UDP/514 in this deployment. GeoIP enrichment happens after
manager rule evaluation and therefore cannot be referenced by manager rules.

## Detection coverage by source

### UniFi

- WAN_LOCAL firewall drops
- SSH, HTTP, HTTPS, Home Assistant, and Synology exposure probes
- high-rate repeated probes from the same source
- CEF IDS/IPS event parsing and service-specific targeting
- repeated IDS targeting of Home Assistant and Synology
- reconnaissance and multi-service probing

See the [UniFi input and setup contract](../unifi/README.md).

### Synology DSM

- login success and failure
- repeated login failures from the same IP
- success after multiple failures from the same IP and user

See the [Synology input and setup contract](../synology/README.md).

### Home Assistant

- invalid authentication from `http.ban`
- repeated invalid authentication from the same IP
- narrowly scoped Moonraker offline connection-error suppression
- UniFi port 8123 probe followed by Home Assistant brute force from the same
  observable source

See the [Home Assistant input and setup contract](../homeassistant/README.md).

### SafeLine WAF

- blocked risk-level-3 SQL injection (`100510`)
- blocked risk-level-3 XSS (`100520`)
- five same-source risk-level-3 attacks in 300 seconds (`100550`)
- same-source XSS and SQL injection within 300 seconds (`100551`)

SafeLine events use the built-in JSON decoder. Rule `100500` is a constrained
child of built-in rule `86600`, which otherwise claims JSON containing both
`timestamp` and `event_type`. Correlation uses the collector's static `srcip`
field and shared `safeline_waf_tier3_event` history.

`reason` remains enrichment only. A production SQL injection event reported a
numeric attack value in localized reason text, so classification is based on
`attack_type`, not `reason`.

See the [SafeLine collector and setup guide](../safeline/README.md).

### UGREEN UGOS Pro

- web login success and failure (`100600`, `100601`)
- repeated same-source web failures (`100610`)
- same-source web success after a failure (`100611`)
- root password changes at a deliberately low severity (`100620`)
- storage I/O errors and repeated same-device correlation (`100630`, `100631`)
- built-in Wazuh SSH and account rules `5715`, `5901`, and `5902`

The collector forwards only allowlisted `auth.log`, `kern.log`, and
`_COMM=log_serv` events. See the [UGREEN transport and setup guide](../ugreen/README.md).

### Minecraft Java Paper

- low-severity pre-login disconnect visibility (`100700`)
- whitelist rejection (`100701`)
- authentication-service availability failures (`100702`)
- distributed low-rate pre-login spray (`100710`)
- same-source player-name rotation (`100711`)
- completed player login (`100720`)

Normal post-login disconnects do not contain the remote endpoint shape required
by the pre-login decoder. See the [Minecraft Paper contract](../minecraft/README.md).

### GeoIP enrichment

The optional Wazuh Indexer pipeline enriches indexed alerts with geographic
context for maps, countries, regions, and attack-origin summaries. Enrichment
does not alter manager-side detection and is not available to manager rules.

See the [Indexer GeoIP guide](../wazuh/indexer/README.md).

## Home Assistant cross-source chain

Home Assistant logs are ingested through a Wazuh Agent with journald access.
Source IP extraction occurs in custom decoders, brute-force detection occurs in
Wazuh rules, and rule `100433` correlates UniFi and Home Assistant events across
agents.

The documented chain is:

1. UniFi detects a probe on port 8123 (`100132`).
2. Home Assistant logs repeated invalid authentication (`100410`).
3. Rule `100433` correlates both sources by `srcip` within 900 seconds.

Rule `100433` uses `<global_frequency/>` because matching events can originate
from different agents. Its logic is production-logtest-confirmed. A real
cross-agent runtime sequence was not executed because it could trigger Home
Assistant IP banning.

## Correlation implementation

Wazuh stores correlation history for the final matched rule. A child rule such
as `100302` therefore does not also populate `if_matched_sid` history for parent
`100300`. The production rules avoid that blind spot with dedicated groups:

| Group | Used by |
|---|---|
| `unifi_wan_local_event` | `100150` high-rate WAN_LOCAL detection |
| `unifi_cef_ids_event` | `100301` repeated IDS and `100310` multi-port reconnaissance |
| `unifi_cef_homeassistant_event` | `100306` repeated Home Assistant targeting |
| `unifi_cef_synology_event` | `100307` repeated Synology targeting |
| `unifi_ha_probe_event` | `100433` UniFi-to-Home Assistant attack chain |
| `safeline_waf_tier3_event` | `100550` repeated attacks and `100551` multi-vector attacks |

One `100310` rule searches the shared CEF group; separate helpers for every
possible previous final SID are neither present nor required.

SafeLine correlations do not use `<global_frequency/>`: all validated SafeLine
events originate from agent 023. Every possible final tier-3 SafeLine child,
including correlation rules, retains `safeline_waf_tier3_event` so group history
does not depend on one final SID.

## Rule reference

| Rule | Level | Purpose | Status |
|---|---:|---|---|
| 100110 | 3 | WAN_LOCAL base event | Production-confirmed |
| 100116 / 100117 / 100119 | 12 / 5 / 5 | SSH, HTTPS, and HTTP probes | Production-confirmed |
| 100132 / 100133 | 10 / 12 | Home Assistant and Synology probes | Production-confirmed |
| 100150 | 13 | 12 WAN_LOCAL drops from one source in 120 seconds | Production-confirmed |
| 100300 | 5 | UniFi CEF IDS/IPS base event | Production-confirmed |
| 100301 | 13 | Five CEF IDS events from one source in 10 minutes | Production-confirmed |
| 100302–100305 | 13–14 | CEF targeting SSH, Home Assistant, Synology, or HTTPS | Production-confirmed |
| 100306 / 100307 | 15 | Repeated Home Assistant or Synology CEF targeting | Production-confirmed; service-wide threshold |
| 100310 | 15 | Same source targeting different destination ports | Production-confirmed |
| 100200 / 100201 | 3 / 12 | Synology login success or failure | Production-confirmed |
| 100210 | 15 | Five Synology failures from one source | Authentic repeated production sample PENDING |
| 100220 | 16 | Two failures then success for the same user and source | Production-confirmed |
| 100419 | 0 | Exact Moonraker offline connection-error suppression | Production-confirmed |
| 100400 / 100410 | 10 / 14 | Home Assistant ban-component failure and brute force | Production-confirmed |
| 100433 | 15 | UniFi probe followed by Home Assistant brute force | Production logtest-confirmed; runtime cross-agent sequence not executed |
| 100420 / 100421 | 8 / 13 | Home Assistant auth failure outside ban component and repetition | PENDING authentic production event |
| 100500 | 3 | SafeLine schema-v1 WAF base child of built-in `86600` | Production-confirmed |
| 100503 / 100504 | 10 / 11 | Risk-level-3 event and blocked risk-level-3 event | Production-confirmed for risk 3/action 1 |
| 100510 / 100520 | 12 | Blocked SQL injection or XSS | Production-confirmed |
| 100550 | 13 | Five same-source risk-level-3 attacks in 300 seconds | Production-confirmed |
| 100551 | 14 | Same-source attacks with different `attack_type` in 300 seconds | Production-confirmed |
| 100600 / 100601 | 3 / 5 | UGOS web login success or failure | Production-confirmed |
| 100610 | 12 | Five same-source UGOS web failures in five minutes | Production logtest-confirmed |
| 100611 | 10 | UGOS web success after same-source failure | Production logtest-confirmed |
| 100620 | 5 | UGREEN root password change | Production-confirmed; low severity is intentional |
| 100630 / 100631 | 10 / 13 | UGREEN storage I/O error and repeated same-device correlation | Production logtest-confirmed |
| 100700–100702 | 3–8 | Paper pre-login disconnect, whitelist rejection, and authentication outage | Production-derived regression coverage |
| 100710 / 100711 | 10 / 12 | Distributed pre-login spray and same-source player-name rotation | Production-derived regression coverage |
| 100720 | 3 | Paper player login completed | Production-derived regression coverage |

## Rule ID ranges

```text
100100–100199   UniFi firewall detections
100200–100299   Synology DSM authentication detections
100300–100399   UniFi IDS/IPS detections
100400–100499   Home Assistant detections
100500–100599   SafeLine WAF detections
100600–100699   UGREEN UGOS Pro detections
100700–100799   Minecraft Java Paper detections
```

New rules should remain within the appropriate logical range. Check for local
collisions before installation or contribution.

## Known limitations

- Rule `100433` depends on the same observable `srcip` across both sources; NAT
  or reverse proxies can merge unrelated clients.
- Rules `100306` and `100307` are service-wide and do not require `same_srcip`.
- The CEF decoder expects the documented extension-field ordering.
- Manager rules cannot use `GeoLocation.*` because Indexer enrichment happens
  later.
- Some detections depend on the exact production-observed log formatting.
- Public sample logs are sanitized and intentionally minimal.
