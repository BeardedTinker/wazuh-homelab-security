# Roadmap

This roadmap favors reproducible installation and backward compatibility over
adding sources quickly. Dates are intentionally omitted; a phase is complete
when its exit criteria are met.

## Current baseline

- Detection content is production-audited on Wazuh 4.14.9 after an in-place
  upgrade with an exact pre/post regression match.
- The regression suite reports 25 PASS, 0 FAIL, 2 PENDING, and 0 XPASS.
- UniFi, Synology, Home Assistant, SafeLine, UGREEN, and Minecraft Paper content
  is present.
- Release candidates `v0.2.0-rc.1` through `v0.2.0-rc.4` are published; no
  stable `0.2.0` release exists.
- Protected pull requests require both dependency-free static validation and
  reproducible runtime regression against the pinned Wazuh 4.14.9 package.
- An optional Home Assistant YAML polling adapter is published with a versioned
  contract, one-deployment validation, and a sanitized standard-card dashboard
  example; no supported dashboard export or custom integration is published.
- Fresh-install issue #1 is fixed in the repository but awaits user confirmation.

## Phase 1: Stabilize installation

Goal: a new user can install one source without risking an unbootable manager.

Work:

- reproduce or obtain confirmation for issue #1 and close it with exact version data
- maintain the concise quick-start for one source at a time
- document backup, validation, restart, verification, and rollback
- add a compatibility matrix for Wazuh and relevant operating-system packages
- maintain the read-only rule-ID and decoder-name collision checker
- add source setup pages for UniFi, Synology, and Home Assistant

Exit criteria:

- a clean Wazuh 4.14.9 installation passes daemon validation after following the docs
- every source has an independent install and uninstall path
- no instruction requires replacing a complete manager configuration directory

## Phase 2: Automate release confidence

Goal: prevent a decoder or rule change from reproducing a startup failure.

Work:

- add CI for XML parsing and repository structure checks
- keep the regression suite running in the pinned Wazuh 4.14.9 CI environment
- verify documented rule IDs, decoder names, groups, and sample metadata
- retain the machine-readable CI regression report and attach it to releases
  when the release workflow is automated
- maintain issue forms that request Wazuh version, validation output, and exact source format

Exit criteria:

- pull requests cannot merge when static validation fails
- the supported baseline has a reproducible regression result
- PENDING scenarios remain visibly separate from passing coverage

## Phase 3: Publish a versioned baseline

Goal: give users an immutable version instead of requiring a clone of `main`.

Work:

- resolve the current `Unreleased` changelog into a semantic version
- publish release notes with compatibility, install, upgrade, and rollback guidance
- attach checksums or a source archive generated from the release commit
- identify every compatibility-sensitive identifier changed since `0.1.0`

Suggested first target: `0.2.0`, because the source set and regression model have
expanded materially while the project is still pre-1.0.

Exit criteria:

- users can pin an exact tag
- documentation refers to the released files, not moving branch content
- upgrade notes cover users of the initial public configuration

## Phase 4: Design the Home Assistant adapter (v1 complete)

Goal: define the adapter contract before publishing implementation details.

Status: completed for the published version 1 YAML adapter. Future contract
changes remain subject to the same design gates.

Work:

- document endpoint, authentication, TLS, and index-pattern options
- define stable entity IDs and units
- define a versioned shared-response schema
- create fixtures for full, partial, empty, and failed responses
- make UniFi, Synology, Home Assistant, SafeLine, UGREEN, and Minecraft independently optional
- measure Indexer request volume and response size
- document Recorder exclusions and freshness semantics

The initial implementation should remain a transparent YAML example. It must
not be described as a supported custom integration.

Exit criteria:

- existing published entities survive a query deduplication refactor
- a missing source produces zero or empty data without template errors
- authentication and transport failures cannot be mistaken for valid zero counts
- one setup guide works without exposing credentials or requiring local IP edits in several files

## Phase 5: Validate the adapter with other users

Goal: prove that the adapter is not tied to one homelab topology.

Work:

- test multiple independent read-only-proxy deployments
- accept direct-Indexer results only from deployments where an isolated,
  source-restricted management network already exists; do not make direct
  access a validation requirement
- test users with different subsets of telemetry sources
- collect field-mapping and index-pattern differences
- document migration from the YAML prototype
- decide whether support demand justifies a Home Assistant custom integration

Exit criteria:

- more than one independent deployment follows the documentation successfully
- compatibility differences are represented by configuration, not source edits
- the support and upgrade burden is understood

## Phase 6: Optional monitors and active response

Goal: add response behavior only after detection and presentation are trustworthy.

Possible work:

- OpenSearch monitor examples
- attack-chain visualization
- optional notification examples
- active-response examples disabled by default

Exit criteria:

- false-positive behavior is documented from production evidence
- rollback and lockout-recovery procedures are tested
- no automatic blocking is enabled by merely installing the repository

## Ongoing rules

- Production evidence outranks synthetic convenience.
- A missing authentic sample stays PENDING.
- Every source remains optional.
- Documentation changes accompany compatibility changes.
- Security-sensitive examples are sanitized before publication.
- Major structural or correlation changes are discussed before implementation.
