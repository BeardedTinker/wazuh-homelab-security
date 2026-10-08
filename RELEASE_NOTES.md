# Wazuh Homelab Security 0.2.0-rc.2

This second release candidate adds the optional Home Assistant YAML presentation
adapter to the Wazuh 4.14.8 detection baseline published in `0.2.0-rc.1`.
Decoder, rule, collector, and regression expectations are unchanged from RC1.

Do not treat the `rc` suffix as a claim of broad production compatibility.
Review the source-specific contracts and validate against your own Wazuh
manager before restart.

## Changes since 0.2.0-rc.1

- added a transparent Home Assistant YAML package with 32 stable entities
- reduced the adapter from five REST resources to two shared responses
- retained the last five alerts at rule level 10 or higher
- added versioned fast and summary response schemas
- added sanitized full, missing-source, empty, partial, and failed fixtures
- documented TLS, read-only credentials, migration, freshness, and Recorder
  behavior
- extended dependency-free validation with adapter-specific invariants
- expanded `SHA256SUMS` to include the adapter package and secrets example

## Compatibility

The audited baseline is:

- Wazuh Manager 4.14.8
- UniFi UCG Ultra production message formats documented in `unifi/README.md`
- Synology DSM `Connection:` authentication messages documented in
  `synology/README.md`
- Home Assistant journald events with program name `homeassistant`, documented
  in `homeassistant/README.md`
- SafeLine 9.4.2 with collector schema version 1
- UGREEN DXP4800 GT running UGOS Pro with the pinned Fluent Bit 5.1.2 pipeline
- Home Assistant adapter locally validated on Home Assistant 2026.9.4 through a
  read-only HTTPS proxy

Compatibility with another product, firmware, message language, transport
shape, or Wazuh version is not implied.

## Included content

- source-organized Wazuh decoders and rules
- secure agent and enrollment configuration snippets
- source-specific localfile snippets
- SafeLine schema-v1 collector
- UGREEN Fluent Bit, rsyslog, and log rotation examples
- optional Wazuh Indexer GeoIP pipeline
- 18 passing production-derived regression scenarios
- 2 explicitly pending scenarios
- dependency-free static repository validation in GitHub Actions
- architecture, installation, source setup, dashboard, and regression guides
- optional Home Assistant YAML adapter, schema contract, and sanitized fixtures

## Integrity verification

`SHA256SUMS` covers shipped operational configuration, collectors, and tooling.
From the release checkout, verify it with:

```bash
sha256sum -c SHA256SUMS
```

The generated GitHub source archive is not listed inside `SHA256SUMS`; GitHub
creates that archive after the tag exists. Pin the exact tag and verify the
tracked files after extraction.

## Fresh installation

1. Read `ARCHITECTURE.md` and `INSTALL.md`.
2. Install one telemetry source at a time.
3. Follow that source's README and input-format contract.
4. Back up manager configuration before copying or merging files.
5. Check custom rule IDs and decoder names for collisions.
6. Run all manager daemon tests and the complete regression suite.
7. Restart only after validation succeeds.
8. Verify manager health, event ingestion, and indexed alerts before installing
   another source.

Never copy the whole repository over `/var/ossec/etc`.

## Optional Home Assistant adapter

The adapter is an optional presentation layer. It does not install Wazuh rules,
configure the Indexer, or make Home Assistant responsible for detection.

1. Read `homeassistant/adapter/README.md` and `CONTRACT.md`.
2. Copy `homeassistant/adapter/wazuh_adapter.yaml` into the Home Assistant
   packages directory.
3. Merge the three keys from `secrets.example.yaml` into the existing
   `secrets.yaml`; never replace that file.
4. Use the complete HTTPS `_search` URL with the desired index pattern and a
   least-privilege read-only account.
5. Keep TLS verification enabled and run the full Home Assistant configuration
   check before restart.
6. Verify the freshness sensor, a populated source, an absent source, and the
   last-five list after startup.

The default polling model performs approximately 42 Indexer requests per hour:
30 fast requests at 120 seconds and 12 summary requests at 300 seconds. The
package excludes eight entities carrying recent-event attributes from Recorder;
Wazuh remains the source of truth for incident history.

Existing local Wazuh REST definitions must be removed or disabled during
migration. Loading both versions creates duplicate unique IDs and preserves the
old polling load. The package does not include a Home Assistant dashboard.

## Upgrade from 0.2.0-rc.1

No Wazuh manager content changed. Users who do not want the optional Home
Assistant presentation adapter can update without deploying it.

Users adopting the adapter should follow the optional adapter steps above and
must not copy example secrets over an existing Home Assistant secrets file.

## Upgrade from the initial public configuration

The changelog contains an initial `0.1.0` baseline, but no historical Git tag
was published for it. Existing users must compare their installed files with
their own original checkout or backup rather than assuming a specific commit.

Before upgrading:

1. Record the current repository commit and Wazuh version.
2. Back up `ossec.conf`, custom decoder files, and custom rule files.
3. Identify whether repository content was copied as separate files or merged
   into `local_decoder.xml` and `local_rules.xml`.
4. Check for duplicate custom rule IDs and decoder names.

Important migration points:

- Remove the obsolete `unifi-wan-kernel` decoder if it was manually merged into
  another file. The current `unifi-wan-local` decoder does not depend on a
  `kernel` parent.
- Do not load the same rule or decoder from both a split repository file and a
  local combined file.
- SafeLine uses the built-in JSON decoder plus
  `wazuh/ossec.conf.snippets/0450-localfiles-safeline.xml` on the collecting
  agent.
- Home Assistant detection is confirmed for the journald-derived
  `homeassistant` program shape, not the optional raw log-file fallback.
- UGREEN intentionally uses RFC 3164 because the tested RFC 5424 pipeline
  inserted a byte-order mark that broke decoder matching.

Run `wazuh-analysisd -t`, the other daemon tests in `INSTALL.md`, and
`tools/regression/run_samples.py` before restart.

## Rollback

If pre-restart validation fails, do not restart. Restore only the files changed
during this upgrade and rerun all daemon tests.

If the manager has already attempted to load the candidate configuration:

1. Restore the backed-up `ossec.conf`, decoder, and rule files.
2. Remove only newly added split files that did not exist in the backup.
3. Undo only the affected source transport change.
4. Confirm all Wazuh daemon tests pass.
5. Restart the manager and verify health and logs.

Do not restore a full backup over unrelated configuration changes made after
that backup.

## Validation status

The audited runtime baseline is:

```text
PASS=18, FAIL=0, PENDING=2, XPASS=0
```

The PENDING scenarios are:

- Home Assistant non-ban invalid authentication
- Synology repeated authentication failures in the alternative or legacy
  `DSM Login:` format

Static GitHub Actions validation checks XML fragments, custom identifier
uniqueness and range, JSON/scenario structure, Python and shell syntax, local
Markdown links, adapter resource and entity invariants, and release checksums.
It does not execute Wazuh runtime regression or a live Home Assistant config
check and does not replace manager-side daemon tests.

## Known limitations

- Fresh-install issue #1 has a repository-side fix, but independent reporter
  confirmation is still pending.
- Runtime regression is not yet executed in a pinned GitHub Actions Wazuh
  environment.
- Several source contracts intentionally support only production-observed IPv4
  and English-language messages.
- SafeLine collector scheduling is host-specific, and the collector does not
  implement an inter-process lock.
- UGREEN UDP syslog is unencrypted and unauthenticated; deploy it only on a
  trusted, filtered network.
- The Home Assistant adapter has been validated on one deployment through a
  read-only HTTPS proxy. Independent Indexer-direct and different-source-subset
  validation is still required.
- No supported Home Assistant dashboard export is included.

Report compatibility results with the exact Wazuh version, source product and
firmware, transport format, validation output, and a minimal sanitized sample.
