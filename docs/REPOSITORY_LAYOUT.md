# Repository layout

The repository is organized by telemetry source and architectural layer. Each
source remains optional; no folder should require an unrelated source to be
installed.

```text
.
├── docs/
├── homeassistant/
│   └── adapter/
├── minecraft/
├── safeline/
│   └── collector/
├── samples/
│   ├── homeassistant/
│   ├── minecraft/
│   ├── safeline/
│   ├── synology/
│   ├── ugreen/
│   └── unifi/
├── synology/
├── tools/
│   ├── regression/
│   ├── sanitize/
│   └── wazuh-aio-upgrade/
├── ugreen/
│   ├── fluent-bit/
│   └── rsyslog/
├── unifi/
└── wazuh/
    ├── decoders/
    ├── indexer/
    ├── manager/
    ├── ossec.conf.snippets/
    └── rules/
```

## Source directories

### `unifi/`, `synology/`, `homeassistant/`, and `minecraft/`

These directories contain the source-specific input contract, installation,
validation, privacy, and compatibility documentation. Their manager detection
files remain under `wazuh/decoders/` and `wazuh/rules/`.

### `safeline/`

Contains the production-confirmed schema-v1 SafeLine collector and its setup,
runtime-path, pipeline, and privacy documentation. Tokens and state files are
runtime-only and are not stored in this repository.

### `ugreen/`

Contains the sanitized UGOS Pro transport example: pinned Fluent Bit Compose,
strict source allowlists, RFC 3164 output, rsyslog source routing, log rotation,
and end-to-end installation notes.

## Detection content

### `wazuh/decoders/`

Custom decoders are grouped by source:

- `0100-unifi-decoders.xml`
- `0200-synology-decoders.xml`
- `0300-homeassistant-decoders.xml`
- `0500-ugreen-decoders.xml`
- `0600-minecraft-decoders.xml`

The UniFi UCG Ultra CEF decoder extracts `srcip`, `dstip`, `srcport`, `dstport`,
`protocol`, and `action` from the documented IDS/IPS event shape.

### `wazuh/rules/`

Custom rules are grouped by source:

- `0100-unifi-rules.xml`
- `0200-synology-rules.xml`
- `0300-homeassistant-rules.xml`
- `0480-safeline-rules.xml`
- `0500-ugreen-rules.xml`
- `0600-minecraft-rules.xml`

The `0480` SafeLine prefix intentionally loads after the built-in parent rule
`86600`. Do not also install the former `0400` filename because both contain the
same rule IDs.

### `wazuh/ossec.conf.snippets/`

Contains configuration fragments for secure agent transport, password-protected
enrollment, and source-specific collection. These are fragments to merge inside
the correct `<ossec_config>` exactly once; they are not complete manager files.

In the tested deployment, `rsyslogd` owns UDP/514 and writes UniFi, Synology,
and UGREEN events to source-specific files. Home Assistant and Minecraft inputs
belong on their emitting host agents.

### `wazuh/manager/`

Documents manager-level production assumptions. The tracked
`local_internal_options.conf` intentionally has no custom runtime override.
Enrollment secrets, agent keys, certificates, and credentials are never stored
in the repository.

### `wazuh/indexer/`

Contains optional Indexer-side resources such as the GeoIP ingest pipeline.
Indexer enrichment happens after manager detection and cannot be referenced by
manager rules.

## Samples and tooling

### `samples/`

Contains sanitized production-derived regression scenarios. A source directory
typically contains:

```text
raw.log
expected.json
scenario.json
```

`expected.json` describes decoder, field, and rule expectations.
`scenario.json` classifies the scenario as passing, pending, or another explicit
regression state.

### `tools/regression/`

`run_samples.py` sends each non-PENDING scenario through
`wazuh-logtest-legacy`, preserving state across all lines in that scenario.
GitHub Actions repeats the suite against a checksum-pinned Wazuh Manager
4.14.9-1 package and retains a machine-readable result artifact. See the
[regression guide](../tools/regression/README.md).

### `tools/sanitize/`

Contains helpers used before publishing logs. Sanitization removes or replaces
private addresses, hostnames, usernames, device IDs, sensitive URLs, tokens,
and other private identifiers.

Run the UniFi sanitizer with a file or standard input:

```bash
bash tools/sanitize/sanitize-unifi.sh raw.log > sanitized.log
cat raw.log | bash tools/sanitize/sanitize-unifi.sh > sanitized.log
```

It replaces MAC values and maps non-documentation IPv4 addresses consistently
to RFC 5737 TEST-NET space.

### `tools/wazuh-aio-upgrade/`

Contains the fail-closed upgrade helper for package-based, single-node Wazuh AIO
installations on Ubuntu 24.04. The generic profile covers standard components;
the homelab profile additionally protects repository rules, decoders, rsyslog
routing, source ingest, and the regression baseline. Read the
[upgrade and recovery guide](../tools/wazuh-aio-upgrade/README.md) before use.

## Optional presentation

### `homeassistant/adapter/`

Contains the optional versioned YAML polling adapter, response schemas,
fixtures, and sanitized standard-card dashboard example. It is a transparent
example, not a supported Home Assistant custom integration.

### Dashboard documentation

[`SECURITY-DASHBOARD.md`](../SECURITY-DASHBOARD.md) contains Wazuh panel recipes.
No supported saved-object export is included.
