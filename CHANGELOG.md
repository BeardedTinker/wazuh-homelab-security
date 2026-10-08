# Changelog

All notable changes to this project will be documented in this file.

This project loosely follows the ideas from **Keep a Changelog** and **Semantic Versioning**.

---

## [Unreleased]

### Changed
- made a constrained read-only HTTPS proxy the recommended Home Assistant
  adapter boundary and marked direct Indexer access as a non-recommended,
  already-segmented deployment exception

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
