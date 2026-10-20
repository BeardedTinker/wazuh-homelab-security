# Changelog

All notable changes to this project will be documented in this file.

This project loosely follows the ideas from **Keep a Changelog** and **Semantic Versioning**.

---

## [Unreleased]

## [0.2.0] - 2026-10-20

### Added
- a concise source-by-source quick start covering preflight, backup, validation,
  restart verification, and rollback gates
- a dependency-free, read-only preflight tool for checking repository rule IDs
  and decoder names against custom and built-in Wazuh XML trees
- structured bug-report and detection-request forms that require versioned,
  sanitized reproduction evidence
- a manual, fail-closed workflow that validates an existing annotated tag and
  prepares an unpublished release draft with checksums and regression evidence

### Changed
- reorganized the oversized root README into a concise project landing page and
  versioned documentation for compatibility, detections, repository layout, and
  troubleshooting
- treated the live Home Assistant 2026.10.2 adapter deployment, fixtures, and
  contract checks as the proportionate v1 baseline while keeping community
  compatibility reports optional

## [0.2.0-rc.4] - 2026-10-19

### Added
- reproducible GitHub Actions runtime regression against a SHA-256-pinned Wazuh
  Manager 4.14.9 package, with a machine-readable result artifact
- a fail-closed helper that prepares an isolated Wazuh test tree without
  installing or starting manager services
- sanitized Wazuh dashboard panel recipes and a standard-card Home Assistant
  dashboard example for the version 1 adapter

### Fixed
- renamed the SafeLine rule file from `0400` to `0480` so built-in parent rule
  `86600` loads first on fresh split-file installations; rule IDs and detection
  logic are unchanged

---

## [0.2.0-rc.3] - 2026-10-18

### Added
- Minecraft Java Paper decoders and rules for pre-login disconnects, whitelist
  rejection, authentication-service outages, distributed scanning,
  same-source player-name rotation, and completed logins
- sanitized production-derived Minecraft regression scenarios, including a
  negative assertion for normal post-login disconnects
- MineOS/Paper host-path discovery, agent collection, validation, privacy, and
  threshold documentation
- an additive Minecraft source entity in the Home Assistant adapter with
  pre-login, whitelist, authentication-backend, spray, player-name rotation,
  successful-login, severity, and sanitized latest-event attributes
- compatible summary-v1 schema coverage and sanitized Minecraft fixtures

### Changed
- extended the regression runner with forbidden-rule assertions and the
  Minecraft disconnect-reason field
- updated the current production compatibility baseline from Wazuh 4.14.8 to
  4.14.9 after an in-place upgrade, daemon validation, and exact pre/post
  regression match
- updated the Home Assistant telemetry guide for add-on 1.2.3, bundled Wazuh
  Agent 4.14.9-1, and required Manager 4.14.9 or newer
- synchronized project and adapter status documentation with the existing
  `v0.2.0-rc.2` release
- made a constrained read-only HTTPS proxy the recommended Home Assistant
  adapter boundary and marked direct Indexer access as a non-recommended,
  already-segmented deployment exception
- validated the equivalent two-resource proxy configuration on Home Assistant
  2026.10.0 with all 32 contract entities available
- extended the adapter contract to 33 entities while preserving all existing
  entity IDs and required summary-v1 paths

---

## [0.2.0-rc.2] - 2026-10-08

### Added
- an optional transparent Home Assistant YAML presentation adapter using two
  shared Wazuh Indexer responses
- a versioned Home Assistant entity and response-schema contract
- sanitized adapter fixtures for full, missing-source, empty, partial, and
  authentication-failure responses
- Home Assistant adapter installation, migration, TLS, polling-load, freshness,
  and Recorder guidance

### Changed
- extended dependency-free repository validation with Home Assistant adapter
  resource, TLS, polling, unique-ID, secret, and Recorder invariants
- expanded release checksums to cover the Home Assistant package and secrets
  example

No Wazuh decoder, rule, collector, or regression expectation changed from
`0.2.0-rc.1`.

---

## [0.2.0-rc.1] - 2026-10-08

### Added
- Home Assistant decoders
- Home Assistant rules
- Home Assistant sample logs
- initial Wazuh dashboard panels
- documentation for Home Assistant journald ingestion
- production-aligned secure-agent and password-protected enrollment snippets
- regression coverage for rules 100150, 100301, 100310, and 100433
- manager baseline documentation and an empty `local_internal_options.conf`
- SafeLine schema-v1 WAF rules for blocked SQLi, blocked XSS, repeated attacks,
  and same-source multi-vector correlation
- sanitized production-derived SafeLine samples for rules 100510, 100520,
  100550, and 100551
- production-confirmed SafeLine schema-v1 collector and installation/pipeline
  documentation
- production-aligned UGREEN UGOS Pro transport, decoders, rules, and
  sanitized regression scenarios for web authentication and storage I/O errors
- architecture, compatibility-contract, roadmap, and safe-installation guides
- source-specific setup guides for UniFi, Synology, Home Assistant, SafeLine,
  and UGREEN
- a SafeLine JSON localfile snippet for the agent collecting schema-v1 events
- dependency-free repository validation and a SHA-pinned GitHub Actions workflow

### Changed
- repository structure aligned with source-based rulesets
- improved README documentation
- improved sample log structure
- synchronized rules, decoders, and regression expectations with the production-confirmed Wazuh 4.14.8 configuration
- replaced final-SID-only UniFi correlations with shared group-history correlations
- sanitized all publishable samples to RFC 5737 TEST-NET addressing
- marked the SafeLine leaf and correlation rules production-confirmed after
  end-to-end manager validation
- extended the regression parser with the UGREEN `storage_device` dynamic field
- documented exact input contracts, unsupported formats, validation gates, and
  rollback expectations for every telemetry source

### Removed
- broad Home Assistant websocket detection that classified normal traffic as suspicious
- inert Wazuh UDP/514 and manager-side GeoIP snippets from the tested configuration

---

## [0.1.0] - Initial public release

### Added
- UniFi firewall decoders
- UniFi firewall rules
- Synology DSM authentication decoders
- Synology DSM authentication rules
- sample logs for UniFi and Synology
- ossec.conf configuration snippets
- repository documentation
