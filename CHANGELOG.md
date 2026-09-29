# Changelog

All notable changes to this project will be documented in this file.

This project loosely follows the ideas from **Keep a Changelog** and **Semantic Versioning**.

---

## [Unreleased]

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

### Changed
- repository structure aligned with source-based rulesets
- improved README documentation
- improved sample log structure
- synchronized rules, decoders, and regression expectations with the production-confirmed Wazuh 4.14.8 configuration
- replaced final-SID-only UniFi correlations with shared group-history correlations
- sanitized all publishable samples to RFC 5737 TEST-NET addressing
- marked the SafeLine leaf and correlation rules production-confirmed after
  end-to-end manager validation

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
