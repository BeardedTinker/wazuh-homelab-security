# Release process

Releases use a manual, fail-closed GitHub Actions workflow. The workflow validates
an existing annotated tag and creates an unpublished draft release for human
review. It does not create or push tags and never publishes a release.

Public release publication remains a separate, explicit maintainer action.

## 1. Prepare the release in a pull request

Before creating a tag:

1. resolve the relevant `Unreleased` changelog entries into a dated semantic
   version heading
2. update `RELEASE_NOTES.md` so its first heading contains the same version
   without the leading `v`
3. update the README's latest-release reference
4. regenerate `SHA256SUMS` when operational files changed
5. run static validation, checksum verification, and runtime regression
6. merge through the protected `main` branch only after required checks pass

The workflow accepts tags shaped like `v1.2.3` or `v1.2.3-rc.1`. Release notes
must begin with:

```text
# Wazuh Homelab Security 1.2.3-rc.1
```

The changelog must contain a dated heading such as:

```text
## [1.2.3-rc.1] - 2026-10-19
```

## 2. Create an annotated tag

After the release-preparation pull request is merged and the exact `main` commit
is verified, create an annotated tag locally:

```bash
git switch main
git pull --ff-only origin main
git tag -a v1.2.3-rc.1 -m "Wazuh Homelab Security v1.2.3-rc.1"
git show --no-patch --show-signature v1.2.3-rc.1
```

Review the tag target before pushing it. Tag creation and tag push are separate
maintainer-approved actions; the release workflow performs neither.

## 3. Prepare the draft release

In GitHub Actions:

1. open **Prepare draft release**
2. choose **Run workflow**
3. select the release tag as the workflow ref
4. enter the same tag in the required `tag` field
5. start the workflow

The workflow rejects:

- a branch run or a mismatch between the selected ref and entered tag
- a lightweight tag
- a tag that does not resolve to the workflow commit
- unsupported tag syntax
- mismatched release-note, changelog, or README versions
- failed static or runtime validation
- failed, unexpected-pass, known-fail, empty, or malformed regression output
- invalid repository checksums
- an existing GitHub release for the tag

## 4. Review the draft

A successful run creates an unpublished draft containing:

- the tagged `RELEASE_NOTES.md` as the release body
- the repository `SHA256SUMS`
- `wazuh-regression-results.json` generated from the tagged commit
- `wazuh-regression-results.json.sha256`

Before publication, verify the draft title, notes, tag, target commit, regression
counts, asset digest, compatibility claims, install instructions, upgrade notes,
and rollback guidance. GitHub generates source archives from the tag separately;
those archives are not covered by the repository `SHA256SUMS`.

Publishing, editing, or deleting the draft, release, or tag requires a separate
explicit maintainer decision. A failed or partial workflow must be inspected
before retrying; do not assume that no draft was created.
