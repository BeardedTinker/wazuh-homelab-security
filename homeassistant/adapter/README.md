# Home Assistant presentation adapter

This directory provides the version 1 contract and a transparent YAML example
for an optional Home Assistant presentation adapter. It is not a custom
integration and has not yet been validated by multiple independent deployments.

The Wazuh manager remains responsible for decoding and detection. Home Assistant
reads already indexed alerts and presents counts and recent security events.

## Deployment boundary

The YAML example uses Home Assistant's shared REST sensor platform. The
recommended deployment places a constrained read-only HTTPS proxy between Home
Assistant and the Wazuh Indexer. The proxy should expose only the required
search endpoint and methods.

Direct Home Assistant access to the Indexer is **not recommended** because it
increases the attack surface of a system that stores security evidence. A
least-privilege account reduces credential misuse, but it does not remove the
risk of an Indexer or authorization-layer vulnerability. Never expose port
`9200` to the internet or open it to a general-purpose LAN solely for this
adapter.

Direct access is an advanced exception only when the Indexer already serves an
isolated service or management network with source-restricted firewall rules,
trusted TLS, and a least-privilege read-only account. Do not weaken an existing
loopback-only or proxy-only Indexer deployment to use this example.

The complete search URL, including the configurable index pattern, will be held
in a Home Assistant secret. Usernames and passwords will also remain in secrets.
TLS verification will be enabled by default. Disabling verification will not be
part of the published default.

No credential, private address, certificate, or internal hostname belongs in
the package, fixtures, dashboard export, or documentation.

## Installation

Requirements:

- Home Assistant packages enabled under `homeassistant.packages`
- HTTPS access to a constrained read-only proxy
- a least-privilege account that can only read the selected alert indices
- a certificate chain trusted by Home Assistant

Install one copy of [`wazuh_adapter.yaml`](wazuh_adapter.yaml) in the Home
Assistant `packages` directory. Merge the three keys from
[`secrets.example.yaml`](secrets.example.yaml) into the existing `secrets.yaml`.
Never replace an existing secrets file with the example.

`wazuh_indexer_search_url` is the complete proxy search URL, so the proxy route
and index pattern are configured in one place. For example:

```yaml
wazuh_indexer_search_url: "https://security-proxy.example.com/wazuh-alerts-*/_search"
```

The package deliberately sets `verify_ssl: true`. Use a trusted certificate on
the read-only HTTPS proxy. Do not weaken the published package by disabling
certificate validation.

Before restart, run Home Assistant's configuration check. A first installation
requires a Core restart to load the new package and Recorder exclusions. After
startup, verify that the freshness sensor has a recent timestamp and that a
source without data shows zero rather than `unavailable`.

The package does not install detection rules, configure the Wazuh Indexer, or
ship a dashboard. Follow the repository's source-specific setup guides first.

## Migration from local query files

Do not load the package alongside older Wazuh REST sensor definitions. That
would duplicate unique IDs and continue unnecessary polling.

1. Back up the existing Home Assistant configuration.
2. Record any locally renamed entity IDs.
3. Remove or disable the old Wazuh REST resources only after placing this
   package and its secrets.
4. Run the complete Home Assistant configuration check.
5. Restart Home Assistant and verify all expected entities before deleting the
   backup.

The unique IDs and default entity names match [`CONTRACT.md`](CONTRACT.md), so
an existing entity registry can retain published entity IDs across migration.

## Polling model

Version 1 uses two shared responses:

| Response | Default interval | Purpose | Requests/hour |
| --- | ---: | --- | ---: |
| `fast-v1` | 120 seconds | Last five security alerts and SafeLine activity | 30 |
| `summary-v1` | 300 seconds | Severity, source, UniFi, and UGREEN summaries | 12 |
| **Total** |  |  | **42** |

The development installation currently uses five resources and approximately
96 requests per hour. Two responses preserve the existing two-minute and
five-minute freshness classes while reducing request count by approximately
56 percent. This is a request-count comparison, not a claim about Indexer CPU or
query latency; those values must be measured during implementation.

A single two-minute query was rejected for version 1 because it would execute
every summary aggregation 30 times per hour. Keeping the heavier summary query
at five minutes avoids increasing its execution frequency.

## Response schemas

The response body remains native Wazuh Indexer/OpenSearch JSON. Adapter-owned
aggregations live under `aggregations.adapter_v1`, which is the versioned
boundary consumed by Home Assistant templates.

- [`schema/fast-v1.schema.json`](schema/fast-v1.schema.json)
- [`schema/summary-v1.schema.json`](schema/summary-v1.schema.json)

Adding optional fields is compatible. Renaming or removing a documented path,
changing its type, or changing its meaning requires a new schema version.

## Optional sources

UniFi, Synology, Home Assistant, SafeLine, and UGREEN are independently
optional. A source that is not installed produces valid zero counts and empty
hit lists. It does not make the adapter unavailable.

The following states have distinct meanings:

| Condition | Numeric state | Text/list state | Availability |
| --- | --- | --- | --- |
| Source absent or no matching alert | `0` | `n/a` or empty list | Available |
| Complete valid response | Parsed value | Parsed value | Available |
| Required branch missing | No fallback to zero | No fallback to empty | Affected entity unavailable |
| Authentication, TLS, timeout, or transport failure | No fallback to zero | No fallback to empty | All entities on that response unavailable |

This prevents an Indexer failure from looking like a quiet security period.

## Last five security alerts

`sensor.wazuh_security_last_5` remains part of the contract. It represents the
five newest alerts from the last 24 hours with `rule.level >= 10`, across every
available source.

Its state is the number of returned hits from 0 through 5. Within each hit, the
query limits `_source` to these fields:

- `@timestamp`
- `rule.id`, `rule.level`, and `rule.description`
- `agent.name`
- `decoder.name`
- `location`

OpenSearch also returns standard hit metadata such as `_index`, `_id`, `_score`,
and `sort`. These values are not additional log content, but consumers must not
treat their presence or exact format as part of the adapter contract.

These are security alerts and are not guaranteed to represent five distinct
attack types. Repeated alerts remain visible because collapsing them could hide
an active repeated probe.

The YAML implementation will exclude this entity, both source-specific last
event entities, and all five source-summary entities from Recorder. Their
current states and attributes remain available to dashboards, but alert details
are not written into Home Assistant's historical database by default. Wazuh
remains the source of truth for historical security events.

## Local validation result

The two-response design was validated on the audited development deployment
before publication:

- Home Assistant configuration validation passed
- the REST integration reloaded without a Core restart
- all 32 contracted entities remained present and available
- `sensor.wazuh_security_last_5` retained five bounded recent hits
- an optional source with no matching events returned valid zero and empty states
- the number of configured REST resources decreased from five to two

This verifies backward-compatible behavior on one deployment only. It does not
replace the independent deployments required by Phase 5 of the roadmap.

## Fixtures

The sanitized fixtures exercise contract behavior without containing production
identifiers:

- [`fixtures/fast-full.json`](fixtures/fast-full.json) — recent security and
  SafeLine hits
- [`fixtures/summary-full.json`](fixtures/summary-full.json) — every source
  represented
- [`fixtures/summary-missing-sources.json`](fixtures/summary-missing-sources.json)
  — optional sources with zero matches
- [`fixtures/summary-empty.json`](fixtures/summary-empty.json) — empty index
  window
- [`fixtures/summary-partial.json`](fixtures/summary-partial.json) — a missing
  required aggregation branch
- [`fixtures/authentication-failure.json`](fixtures/authentication-failure.json)
  — HTTP failure metadata, not a successful response body

The partial and authentication-failure fixtures are intentionally not valid
successful `summary-v1` responses. They exist to verify availability behavior.

## Validation and support boundary

The published package preserves every entity ID in [`CONTRACT.md`](CONTRACT.md)
and uses the two documented REST resources. The equivalent two-resource
configuration passed Home Assistant 2026.10.0 configuration validation on the
audited proxy deployment. All 32 contract entities were available and both
shared REST resources continued polling successfully after the upgrade. The
fixtures cover full, absent-source, empty, partial, and failed responses.

This is one deployment validation, not a general compatibility claim.

This remains an example until Phase 5 validates multiple independent proxy
deployments with different source subsets. Report results with the Home
Assistant version, Wazuh version, proxy design, index pattern, source subset,
and sanitized validation output. An existing, intentionally segmented direct
deployment may also report results, but direct access is not a validation
requirement or the recommended architecture.
