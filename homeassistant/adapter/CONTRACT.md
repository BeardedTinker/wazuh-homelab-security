# Home Assistant adapter entity contract v1

This document freezes the entity IDs and user-visible meanings proposed for the
first YAML adapter. Internal query paths may change only when entity behavior
and compatibility remain unchanged.

## Core and freshness entities

| Entity ID | State | Empty state | Response |
| --- | --- | --- | --- |
| `sensor.wazuh_critical_24h` | Alert count, rule level 15 or higher | `0` | summary |
| `sensor.wazuh_high_24h` | Alert count, levels 12 through 14 | `0` | summary |
| `sensor.wazuh_medium_24h` | Alert count, levels 7 through 11 | `0` | summary |
| `sensor.wazuh_low_24h` | Alert count, level 6 or lower | `0` | summary |
| `sensor.wazuh_top_rule_24h` | Most frequent rule at level 7 or higher | `n/a` | summary |
| `sensor.wazuh_indexer_last_successful_poll` | Timestamp of the latest successful fast response | unavailable until success | fast |
| `sensor.wazuh_security_last_5` | Number of returned alerts at level 10 or higher | `0` | fast |
| `sensor.siem_security_score` | Existing local score derived from critical, high, and medium counts | unavailable when an input is unavailable | template |

`sensor.wazuh_security_last_5` retains a bounded `hits` attribute as documented
in `README.md`. The entity is excluded from Recorder by default.

## UniFi entities

| Entity ID | State | Empty state | Response |
| --- | --- | --- | --- |
| `sensor.wazuh_wan_local_drops_24h` | Alerts decoded as `unifi-wan-local` | `0` | summary |
| `sensor.wazuh_top_wan_local_source_ip_24h` | Most frequent source IP and count | `n/a` | summary |
| `sensor.wazuh_top_wan_local_dpt_24h` | Most frequent destination port and count | `n/a` | summary |

## SafeLine entities

| Entity ID | State | Empty state | Response |
| --- | --- | --- | --- |
| `sensor.wazuh_safeline_alerts_24h` | SafeLine WAF alert count | `0` | fast |
| `sensor.wazuh_safeline_blocked_attacks_24h` | Blocked SafeLine event count | `0` | fast |
| `sensor.wazuh_safeline_sqli_24h` | SQL injection event count | `0` | fast |
| `sensor.wazuh_safeline_xss_24h` | Cross-site scripting event count | `0` | fast |
| `sensor.wazuh_safeline_repeated_attacks_24h` | Rule 100550 count | `0` | fast |
| `sensor.wazuh_safeline_multi_vector_24h` | Rule 100551 count | `0` | fast |
| `sensor.wazuh_safeline_top_source_ip_24h` | Most frequent source IP and count | `n/a` | fast |
| `sensor.wazuh_safeline_last_attack` | Timestamp of the newest SafeLine event | `n/a` | fast |

The last-attack entity retains a bounded `hits` attribute containing only the
newest event and is excluded from Recorder by default.

## UGREEN entities

| Entity ID | State | Empty state | Response |
| --- | --- | --- | --- |
| `sensor.wazuh_ugreen_events_24h` | UGREEN event count | `0` | summary |
| `sensor.wazuh_ugreen_web_success_24h` | Successful web authentication count | `0` | summary |
| `sensor.wazuh_ugreen_web_failures_24h` | Failed web authentication count | `0` | summary |
| `sensor.wazuh_ugreen_ssh_success_24h` | Successful SSH authentication count | `0` | summary |
| `sensor.wazuh_ugreen_account_changes_24h` | Account-change alert count | `0` | summary |
| `sensor.wazuh_ugreen_storage_alerts_24h` | Storage alert count | `0` | summary |
| `sensor.wazuh_ugreen_top_source_ip_24h` | Most frequent source IP and count | `n/a` | summary |
| `sensor.wazuh_ugreen_last_event` | Timestamp of the newest UGREEN event | `n/a` | summary |

The last-event entity retains a bounded `hits` attribute containing only the
newest event and is excluded from Recorder by default.

## Source summary entities

All source summary entities use the unit `events`. Their state is the matching
24-hour event count. Their attributes contain `elevated`, `high`, and `latest`
subsets from the same source aggregation. Because `latest` contains security
event details, all five entities are excluded from Recorder by default.

| Entity ID | Source filter | Empty state | Response |
| --- | --- | --- | --- |
| `sensor.wazuh_source_unifi_24h` | Rule group `unifi` | `0` | summary |
| `sensor.wazuh_source_safeline_24h` | Rule group `safeline_waf_event` | `0` | summary |
| `sensor.wazuh_source_ugreen_24h` | UGREEN log location | `0` | summary |
| `sensor.wazuh_source_home_assistant_24h` | Rule group `homeassistant` | `0` | summary |
| `sensor.wazuh_source_synology_24h` | Rule group `synology` | `0` | summary |

## Compatibility rules

- Existing entity IDs, unique IDs, units, and state meanings must not change in
  an internal polling refactor.
- Missing optional sources return valid zero or empty states.
- Missing required response paths make only the affected entities unavailable.
- Authentication and transport failures make all entities attached to the
  failed response unavailable.
- Empty buckets render `n/a`; they do not reuse a previous source IP, port,
  rule, or timestamp.
- Source-specific attributes may be absent only when the corresponding entity
  is unavailable.
- OpenSearch hit metadata such as `_index`, `_id`, `_score`, and `sort` may be
  present, but its exact presence and format are not compatibility guarantees.
- `sensor.wazuh_ops_last_5` is not part of version 1 and must not be recreated as
  an alias for security alerts.
