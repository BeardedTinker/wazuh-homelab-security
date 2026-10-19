# Documentation index

This directory contains detailed project documentation that would make the
repository landing page difficult to scan. Documents remain in the repository
so they are versioned with each tag, reviewed through pull requests, and checked
by repository validation.

## Begin here

1. Read the [architecture and compatibility contract](../ARCHITECTURE.md).
2. Review the [validated compatibility baseline](COMPATIBILITY.md).
3. Follow the [safe installation and rollback guide](../INSTALL.md).
4. Open the setup guide for exactly one telemetry source.
5. Use the [troubleshooting guide](TROUBLESHOOTING.md) if validation fails.

## Core documentation

| Topic | Document |
|---|---|
| Architecture, public contracts, and non-goals | [`ARCHITECTURE.md`](../ARCHITECTURE.md) |
| Installation, backup, validation, restart, and rollback | [`INSTALL.md`](../INSTALL.md) |
| Versions and deployment assumptions | [`COMPATIBILITY.md`](COMPATIBILITY.md) |
| Detection coverage, correlations, and rule reference | [`DETECTION_REFERENCE.md`](DETECTION_REFERENCE.md) |
| Repository structure and folder purpose | [`REPOSITORY_LAYOUT.md`](REPOSITORY_LAYOUT.md) |
| Testing and troubleshooting | [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) |
| Project phases and validation gates | [`ROADMAP.md`](../ROADMAP.md) |
| Release-specific compatibility and migration | [`RELEASE_NOTES.md`](../RELEASE_NOTES.md) |

## Source setup guides

| Source | Guide |
|---|---|
| UniFi | [`unifi/README.md`](../unifi/README.md) |
| Synology DSM | [`synology/README.md`](../synology/README.md) |
| Home Assistant | [`homeassistant/README.md`](../homeassistant/README.md) |
| SafeLine WAF | [`safeline/README.md`](../safeline/README.md) |
| UGREEN UGOS Pro | [`ugreen/README.md`](../ugreen/README.md) |
| Minecraft Java Paper | [`minecraft/README.md`](../minecraft/README.md) |

## Tooling and optional layers

| Topic | Document |
|---|---|
| Regression runner and isolated CI tree | [`tools/regression/README.md`](../tools/regression/README.md) |
| Wazuh AIO upgrade and recovery helper | [`tools/wazuh-aio-upgrade/README.md`](../tools/wazuh-aio-upgrade/README.md) |
| Sample structure and regression metadata | [`samples/README.md`](../samples/README.md) |
| Wazuh dashboard panel recipes | [`SECURITY-DASHBOARD.md`](../SECURITY-DASHBOARD.md) |
| Indexer GeoIP enrichment | [`wazuh/indexer/README.md`](../wazuh/indexer/README.md) |
| Home Assistant adapter | [`homeassistant/adapter/README.md`](../homeassistant/adapter/README.md) |
| Home Assistant dashboard example | [`homeassistant/adapter/DASHBOARD.md`](../homeassistant/adapter/DASHBOARD.md) |

## Project participation

- [Contributing guide](../CONTRIBUTING.md)
- [Changelog](../CHANGELOG.md)
- [License](../LICENSE)
