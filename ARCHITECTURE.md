# Architecture and compatibility contract

This document defines the intended boundaries of Wazuh Homelab Security and the
compatibility promises that must exist before optional integrations are
published for other users.

## Project status

The repository is an early public project built from a production homelab. Its
current audited baseline is Wazuh 4.14.8. Unless a release or this document says
otherwise, examples from other Wazuh versions are not assumed to be compatible.

The repository currently ships detection content and transport examples. It
does **not** currently ship a supported Home Assistant dashboard or polling
adapter. Any local Home Assistant configuration used to develop such an adapter
is a prototype, not a public API.

## Architectural layers

### 1. Detection core

The detection core is the primary product:

- Wazuh decoders
- Wazuh rules and correlations
- manager configuration snippets
- sanitized production-derived samples
- the regression runner and expected results

Changes here can affect whether `wazuh-analysisd` starts and which alerts are
generated. They require the strongest compatibility and validation guarantees.

### 2. Source collectors and transports

Collectors and transport examples bring source telemetry to the detection core:

- SafeLine schema-versioned JSON collector
- UGREEN Fluent Bit and rsyslog pipeline
- UniFi, Synology, and Home Assistant localfile or journald snippets

Every source is optional. Installing one source must not require installing any
other source. A collector failure must not stop the Wazuh manager or unrelated
collectors.

### 3. Indexer enrichment and presentation

Indexer pipelines, dashboards, monitors, and Home Assistant adapters consume
alerts after manager-side detection. They are optional presentation layers and
must not be prerequisites for decoder or rule operation.

Manager rules must not depend on fields created later by Indexer enrichment.
For example, `GeoLocation.*` may be used by dashboards but not by manager rules.

## Public compatibility contract

The following identifiers are public once included in a tagged release:

- custom rule IDs and their documented meaning
- decoder names
- correlation group names
- structured fields used by documented queries and dashboards
- collector `schema_version` values and documented field semantics
- file paths explicitly documented as runtime interfaces

These identifiers must not be renamed or repurposed silently. A breaking change
requires a migration note and a release that clearly identifies the break.

Alert counts are not a stable contract when a detection is deliberately tuned
to reduce false positives. The rule meaning, migration notes, and regression
expectations are the contract.

## Version support

Each release must state:

- the Wazuh version used for production validation
- other versions covered by automated or user-confirmed testing
- operating-system or package assumptions that affect built-in decoders
- known unsupported combinations

Before support is claimed for another Wazuh version, the complete regression
suite and daemon configuration tests must pass on that version.

## Safe installation and upgrade behavior

Documentation must treat manager configuration as safety-critical:

1. Back up the current manager configuration.
2. Check that rule IDs and decoder names do not already exist.
3. Install or merge each source exactly once.
4. Run daemon configuration tests before restart.
5. Run the regression suite.
6. Restart only after validation succeeds.
7. Verify alert ingestion and keep a documented rollback path.

Copying the whole repository over `/var/ossec/etc` is not a supported
installation method.

## Source independence

Rules, queries, and adapters must behave predictably when a source is absent:

- missing sources produce no matching alerts, not setup failures
- dashboards show zero or an explicitly empty state
- source-specific attributes may be absent
- no query assumes that every user has UniFi, Synology, SafeLine, UGREEN, or
  Home Assistant telemetry

Cross-source correlations are opt-in behavior. Their source, field, agent-scope,
and timeframe assumptions must be documented alongside the rule.

## Proposed Home Assistant adapter boundary

A future Home Assistant adapter belongs to the optional presentation layer. Its
first public version should be a documented YAML example under a dedicated
`home-assistant/` directory. A custom integration should be considered only
after the query and entity contracts have been validated by multiple users.

The adapter must:

- use a configurable, constrained read-only HTTPS proxy endpoint by default
- treat direct Indexer access as a non-recommended exception for deployments
  that already isolate the Indexer on a source-restricted management network;
  never require port `9200` to be opened for the adapter
- keep credentials in Home Assistant secrets or a config entry
- verify TLS by default and document any proxy trust model
- allow a configurable index pattern
- aggregate all dashboard data through the minimum practical number of requests
- preserve published entity IDs across internal query refactors
- tolerate every optional source being absent
- avoid storing large raw responses in Recorder by default
- document query frequency and expected Indexer load
- expose freshness and failure state separately from valid zero counts

A single shared polling response is preferred over one request per entity, but
that response becomes a versioned schema. It must be covered by fixtures that
represent all sources, missing sources, empty indices, authentication failures,
and partial aggregation responses.

## Security and privacy boundaries

The repository must never contain:

- API tokens, passwords, enrollment secrets, or agent keys
- private keys or certificates
- unsanitized internal addresses, hostnames, usernames, or device identifiers
- raw request bodies or headers that are not required for a detection

Example addresses use documentation ranges. Public samples remain short and
retain only the fields necessary to reproduce decoder and rule behavior.

## Non-goals

The project does not aim to:

- provide a complete enterprise SIEM distribution
- install or upgrade Wazuh itself
- promise compatibility with untested Wazuh versions
- enable automatic blocking by default
- require all supported telemetry sources
- make Home Assistant responsible for security detection

## Change process

Large changes start with an issue or design note before implementation. This
includes rule-range restructuring, collector schema changes, dashboard export
formats, active response, and cross-source correlation strategy.

Every implementation change should answer:

1. Which layer does it belong to?
2. Which public identifiers can it affect?
3. How is backward compatibility tested?
4. What does a user without this source observe?
5. How does a user roll back safely?
