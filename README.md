# Wazuh Homelab Security

Practical Wazuh rules, decoders, sanitized samples, regression tooling, and
optional presentation examples for a real homelab deployment.

The project focuses on six telemetry sources:

| Source | Coverage | Setup guide |
|---|---|---|
| UniFi | Firewall, IDS/IPS, probing, and reconnaissance | [`unifi/README.md`](unifi/README.md) |
| Synology DSM | Authentication success, failure, and correlation | [`synology/README.md`](synology/README.md) |
| Home Assistant | Security-relevant journald events and cross-source correlation | [`homeassistant/README.md`](homeassistant/README.md) |
| SafeLine WAF | Schema-v1 attack events and same-source correlation | [`safeline/README.md`](safeline/README.md) |
| UGREEN UGOS Pro | Authentication, account, and storage events | [`ugreen/README.md`](ugreen/README.md) |
| Minecraft Java Paper | Pre-login scanning, rejection, outages, and completed logins | [`minecraft/README.md`](minecraft/README.md) |

Every source is optional. Install and validate one source at a time.

## Project status

The primary product is the Wazuh detection core: decoders, rules, collectors,
sanitized samples, and regression tooling. Indexer enrichment, dashboards, and
the Home Assistant YAML adapter are optional presentation layers.

The current audited baseline is **Wazuh 4.14.9** and the latest prerelease is
[`v0.2.0-rc.4`](https://github.com/BeardedTinker/wazuh-homelab-security/releases/tag/v0.2.0-rc.4).
The repository remains an early project and does not claim broad compatibility
outside the documented baseline.

Current regression status: **25 PASS, 0 FAIL, 2 PENDING, 0 XPASS**. The PENDING
scenarios are `homeassistant/auth-failed` and `synology/bruteforce-login`;
synthetic events must not be used to close them.

## Start safely

Start with the concise [`docs/QUICKSTART.md`](docs/QUICKSTART.md), then use
[`INSTALL.md`](INSTALL.md) for the complete procedure. The supported workflow is
source-by-source:

1. Pin the exact tag or commit being installed.
2. Back up the affected manager configuration.
3. Install only the selected source files and collection snippet.
4. Run all documented daemon tests and the complete regression suite.
5. Restart only after validation succeeds, then verify ingestion and alerts.

Never copy the complete repository over `/var/ossec/etc`. Configuration snippets
are fragments and must not replace a complete `ossec.conf`.

## Documentation

[`docs/README.md`](docs/README.md) is the documentation index.

| Topic | Document |
|---|---|
| Source-by-source quick start | [`docs/QUICKSTART.md`](docs/QUICKSTART.md) |
| Architecture and compatibility contract | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
| Installation, backup, validation, and rollback | [`INSTALL.md`](INSTALL.md) |
| Rule-ID and decoder-name collision checks | [`docs/COLLISION_CHECKS.md`](docs/COLLISION_CHECKS.md) |
| Validated versions and deployment assumptions | [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) |
| Detection coverage, correlations, and rule IDs | [`docs/DETECTION_REFERENCE.md`](docs/DETECTION_REFERENCE.md) |
| Repository structure and folder purpose | [`docs/REPOSITORY_LAYOUT.md`](docs/REPOSITORY_LAYOUT.md) |
| Testing and troubleshooting | [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) |
| Regression runner | [`tools/regression/README.md`](tools/regression/README.md) |
| Wazuh dashboard recipes | [`SECURITY-DASHBOARD.md`](SECURITY-DASHBOARD.md) |
| Home Assistant adapter | [`homeassistant/adapter/README.md`](homeassistant/adapter/README.md) |
| Roadmap | [`ROADMAP.md`](ROADMAP.md) |
| Release notes | [`RELEASE_NOTES.md`](RELEASE_NOTES.md) |
| Contributing | [`CONTRIBUTING.md`](CONTRIBUTING.md) |

## Repository contents

- `wazuh/decoders/` and `wazuh/rules/` contain source-organized detection
  content.
- `wazuh/ossec.conf.snippets/` contains fragments to merge exactly once into
  the appropriate manager, agent, or shared configuration.
- `samples/` contains sanitized production-derived regression scenarios.
- `tools/regression/` contains the local and CI regression tooling.
- `tools/sanitize/` contains sanitization helpers.
- `safeline/` and `ugreen/` contain source-specific collectors and transports.
- `homeassistant/adapter/` contains the optional versioned YAML presentation
  adapter and a standard-card dashboard example.

See [`docs/REPOSITORY_LAYOUT.md`](docs/REPOSITORY_LAYOUT.md) for the complete
layout and folder responsibilities.

## Validation

Pull requests and pushes to `main` run two required checks:

- **Static validation** checks XML fragments, identifiers, scenarios, Markdown
  links, adapter invariants, checksums, and helper smoke tests.
- **Runtime regression** runs every scenario against an isolated tree from the
  SHA-256-pinned official Wazuh Manager 4.14.9-1 amd64 package.

Local deployment validation remains mandatory. CI does not replace daemon tests
or verification on the target manager.

## Optional presentation layers

The repository includes an optional Wazuh Indexer GeoIP pipeline, sanitized
dashboard recipes, and a Home Assistant YAML polling adapter. None is required
for manager-side detection. The Home Assistant adapter is an example, not a
supported custom integration, and has not yet been validated by multiple
independent deployments.

## Security and privacy

Never publish credentials, enrollment secrets, agent keys, private addresses,
hostnames, usernames, player names, device identifiers, or unsanitized raw
events. Use documentation address ranges and keep only fields required to
reproduce decoder or rule behavior.

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before proposing detection changes.
Major rule restructuring, schema changes, active response, dashboard exports,
and cross-source correlation strategy should be discussed before implementation.

## License

This project is licensed under the [MIT License](LICENSE).
