# Wazuh Homelab Security 0.2.0

This is the first stable versioned baseline for the expanded homelab detection
set. It combines the production-audited Wazuh 4.14.9 content from the release
candidates with reproducible runtime CI, source-by-source installation guidance,
collision checks, structured support intake, and guarded draft-release
automation.

Stable means the documented baseline, compatibility contracts, and upgrade path
are ready to pin. It does not imply compatibility with every Wazuh version,
product firmware, transport shape, language, or homelab topology. Validate the
selected source against the target manager before restart.

## Changes since 0.2.0-rc.4

- reorganized the root README into a concise landing page and focused,
  versioned documentation
- added a source-by-source quick start with backup, validation, verification,
  and rollback gates
- added a dependency-free, read-only rule-ID and decoder-name collision checker
  with unit tests and CI coverage
- added structured bug-report and detection-request forms that require exact
  versions and sanitized evidence
- added a manual, fail-closed workflow that reruns validation for an existing
  annotated tag and creates only an unpublished draft release
- confirmed the Home Assistant 2026.10.2 adapter baseline with all 33 contracted
  entities present and available on the live read-only-proxy deployment
- kept additional community adapter reports optional rather than treating an
  enterprise-scale number of deployments as a release gate

No Wazuh rule IDs, decoder names, detection logic, collector behavior, or Home
Assistant adapter entity contracts changed after `v0.2.0-rc.4`.

## Compatibility

The audited baseline is:

- Wazuh Manager 4.14.9
- UniFi UCG Ultra production message formats documented in `unifi/README.md`
- Synology DSM `Connection:` authentication messages documented in
  `synology/README.md`
- Home Assistant journald events with program name `homeassistant`, documented
  in `homeassistant/README.md`
- SafeLine 9.4.2 with collector schema version 1
- UGREEN DXP4800 GT running UGOS Pro with the pinned Fluent Bit 5.1.2 pipeline
- Minecraft Java Paper production message formats documented in
  `minecraft/README.md`
- Home Assistant adapter baseline validated through a read-only HTTPS proxy;
  the additive Minecraft source was validated on Home Assistant 2026.10.2

Compatibility with another product, firmware, message language, transport
shape, or Wazuh version is not implied.

## Included content

- source-organized Wazuh decoders and rules
- secure agent and enrollment configuration snippets
- source-specific localfile snippets
- SafeLine schema-v1 collector
- UGREEN Fluent Bit, rsyslog, and log rotation examples
- optional Wazuh Indexer GeoIP pipeline
- 25 passing production-derived regression scenarios
- 2 explicitly pending scenarios
- dependency-free static validation and pinned Wazuh 4.14.9 runtime regression
  in GitHub Actions
- architecture, quick-start, installation, compatibility, collision-check,
  troubleshooting, source setup, dashboard, and regression guides
- structured issue forms and guarded draft-release preparation
- optional 33-entity Home Assistant YAML adapter, schema contract, and sanitized
  fixtures
- sanitized Wazuh panel recipes and a standard-card Home Assistant dashboard
  example

## Integrity verification

`SHA256SUMS` covers shipped operational configuration, collectors, and tooling.
From the release checkout, verify it with:

```bash
sha256sum -c SHA256SUMS
```

The generated GitHub source archive is not listed inside `SHA256SUMS`; GitHub
creates that archive after the tag exists. Pin the exact tag and verify the
tracked files after extraction.

The GitHub release also attaches the machine-readable runtime regression report
generated from the exact release commit and its SHA-256 digest.

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
package excludes nine entities carrying recent-event attributes from Recorder;
Wazuh remains the source of truth for incident history.

Existing local Wazuh REST definitions must be removed or disabled during
migration. Loading both versions creates duplicate unique IDs and preserves the
old polling load. The optional standard-card dashboard is a portable example,
not a supported saved-object export, and is not installed automatically.

## Upgrade from 0.2.0-rc.4

No deployed Wazuh or Home Assistant adapter file requires replacement solely to
move from `v0.2.0-rc.4` to `v0.2.0`. The stable release adds documentation,
preflight tooling, support forms, and release automation around the same runtime
contracts.

Users may adopt `tools/check_wazuh_collisions.py` before future source-file
changes. Follow `docs/COLLISION_CHECKS.md`; a nonzero result is a stop condition.

## Upgrade from earlier 0.2.0 release candidates

Users upgrading from `v0.2.0-rc.3` or earlier must include the SafeLine load-order
fix introduced in `v0.2.0-rc.4`. SafeLine users with split rule files must replace
`0400-safeline-rules.xml` with `0480-safeline-rules.xml`. Never load both
filenames: they contain the same rule IDs. The rename changes only load order;
rule IDs and detection logic are unchanged.

No deployed Home Assistant adapter change is required. The dashboard file is an
optional example and does not modify a live dashboard. Users adopting it should
follow `homeassistant/adapter/DASHBOARD.md`, keep private deployment data out of
published screenshots, and run a full Home Assistant configuration check before
registering a YAML-mode dashboard.

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
PASS=25, FAIL=0, PENDING=2, XPASS=0
```

The PENDING scenarios are:

- Home Assistant non-ban invalid authentication
- Synology repeated authentication failures in the alternative or legacy
  `DSM Login:` format

Static GitHub Actions validation checks XML fragments, custom identifier
uniqueness and range, JSON/scenario structure, Python and shell syntax, local
Markdown links, adapter resource and entity invariants, and release checksums.
The separate required runtime job executes the complete suite against an
isolated tree from the SHA-256-pinned official Wazuh Manager 4.14.9-1 amd64
package and retains a machine-readable report. CI does not run a live Home
Assistant configuration check or replace manager-side daemon tests on the
target deployment.

## Known limitations

- Fresh-install issue #1 has a repository-side fix, but independent reporter
  confirmation is still pending.
- Runtime CI validates an isolated package tree, not a complete running Wazuh
  service stack or a distribution other than the documented amd64 baseline.
- Several source contracts intentionally support only production-observed IPv4
  and English-language messages.
- SafeLine collector scheduling is host-specific, and the collector does not
  implement an inter-process lock.
- UGREEN UDP syslog is unencrypted and unauthenticated; deploy it only on a
  trusted, filtered network.
- The Home Assistant adapter has been validated on one deployment through a
  read-only HTTPS proxy. Additional topology and source-subset reports can expand
  the compatibility evidence but are not a release requirement.
- The Home Assistant dashboard is a sanitized standard-card example, not a
  supported saved-object export; frontend rendering is not covered by CI.

Report compatibility results with the exact Wazuh version, source product and
firmware, transport format, validation output, and a minimal sanitized sample.
