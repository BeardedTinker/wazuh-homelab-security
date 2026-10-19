# Compatibility baseline

This document records the versions and deployment assumptions currently covered
by production evidence, runtime regression, or an explicitly limited example.
Compatibility with another version, firmware, message language, transport
shape, or topology is not implied.

## Audited baseline

| Component | Validated baseline | Scope |
|---|---|---|
| Wazuh Manager | 4.14.9 | Production-audited after an in-place upgrade |
| Runtime CI package | Wazuh Manager 4.14.9-1 amd64 | Complete regression in an isolated package tree |
| UniFi | UCG Ultra | Message formats documented in the source guide |
| Synology | DSM `Connection:` authentication messages | Alternative `DSM Login:` repetition remains PENDING |
| Home Assistant detection | Journald events with program name `homeassistant` | Optional raw log-file fallback is not the confirmed baseline |
| SafeLine | 9.4.2, collector schema version 1 | Built-in JSON decoder and repository rules |
| UGREEN | DXP4800 GT running UGOS Pro | Pinned Fluent Bit 5.1.2 example and RFC 3164 transport |
| Minecraft | Java Paper | Production-derived formats documented in the source guide |
| Home Assistant adapter | Home Assistant 2026.10.2 | One deployment through a constrained read-only HTTPS proxy |

The live Home Assistant adapter deployment is the supported project baseline.
Additional community deployments can broaden the compatibility evidence, but a
fixed number of external reports is not a release gate. Direct Indexer access is
a non-recommended exception for networks that already isolate the Indexer on a
source-restricted management segment.

## Wazuh assumptions

Earlier Wazuh versions may work, but they are not covered by the current runtime
CI. Before claiming support for another version, run the complete regression
suite and all manager daemon configuration tests on that version.

The Wazuh AIO upgrade helper supports package-based, single-node installations
on Ubuntu 24.04. Docker, RPM, and multi-node deployments are outside that
helper's supported boundary; this limit does not by itself describe detection
content compatibility.

Stock Wazuh 4.14.9 manager packages do not consume GeoLite2 `.mmdb` files for
manager-side rule evaluation in this setup. GeoIP enrichment occurs in the
Wazuh Indexer after manager rule evaluation.

## Deployment assumptions

- `rsyslogd`, not Wazuh, owns UDP/514 for UniFi, Synology, and UGREEN events.
- Home Assistant and Minecraft events arrive through host Wazuh agents over the
  established secure agent transport.
- SafeLine events are emitted by the schema-v1 collector and read by a Wazuh
  agent.
- Manager rules never depend on `GeoLocation.*` fields created later by the
  Indexer pipeline.
- Every source is optional and must have an independent install and rollback
  path.

## Dashboard and query fields

Dashboards and monitors should use structured indexed fields such as:

```text
data.srcip.keyword
manager.name.keyword
GeoLocation.country_name
GeoLocation.location
```

Do not rely on scripted extraction from `full_log`. If a dashboard is empty,
first verify that decoders loaded, alerts contain the expected structured
fields, and the relevant Indexer pipeline is active.

## Validation language

| Status | Meaning |
|---|---|
| Production-confirmed | Behavior was validated with the production manager and sanitized regression inputs. |
| Production-derived regression | Authentic observed formats are covered by the regression suite. |
| Known limitation | Behavior is understood and intentionally retained. |
| PENDING | No compatibility claim is made until an authentic event is available. |

The current suite reports **25 PASS, 0 FAIL, 2 PENDING, and 0 XPASS**. The
PENDING scenarios are `homeassistant/auth-failed` and
`synology/bruteforce-login`.
