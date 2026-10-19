# Rule-ID and decoder-name collision checks

`tools/check_wazuh_collisions.py` is a dependency-free, read-only preflight
check for a supported Wazuh installation. It compares identifiers in one
repository source package with identifiers already present in the target Wazuh
tree.

Run it before copying a decoder or rule file. A passing result does not replace
`wazuh-analysisd -t`, the other daemon tests, or the regression suite.

## What it checks

For the selected source, the tool extracts:

- numeric IDs from repository `<rule id="...">` elements
- names from repository `<decoder name="...">` elements

It compares those identifiers with XML files under:

```text
/var/ossec/etc/rules
/var/ossec/etc/decoders
/var/ossec/ruleset/rules
/var/ossec/ruleset/decoders
```

Both custom and built-in trees are included. XML comments are ignored. The tool
does not read logs, credentials, agent keys, or event data and does not write to
the Wazuh installation.

The supported source keys are:

```text
unifi
synology
homeassistant
safeline
ugreen
minecraft
all
```

SafeLine has repository rules but no custom decoder because it uses Wazuh's
built-in JSON decoder.

## New installation

From the pinned repository checkout, select exactly the source being installed:

```bash
sudo python3 tools/check_wazuh_collisions.py --source unifi
```

Replace `unifi` with the selected source key. Use `--source all` only when
deliberately reviewing every repository source against the same manager.

A clean result ends with:

```text
Collision check passed: no unapproved rule-ID or decoder-name matches found.
```

Any match fails the command and prints the identifier, candidate file, and
installed file. Stop before copying files or restarting Wazuh.

## Existing split-file upgrade

An upgrade can legitimately replace an older repository file with the same
basename. The default remains fail-closed and reports those identifiers as
collisions.

Only after backing up and reviewing the installed file against the candidate,
allow same-file replacement explicitly:

```bash
sudo python3 tools/check_wazuh_collisions.py \
  --source unifi \
  --allow-same-file
```

`--allow-same-file` permits a matching identifier only when it appears in a
custom file under `etc/rules` or `etc/decoders` with the same basename as the
repository candidate. It never permits:

- a match in a differently named custom file such as `local_rules.xml`
- a match in the built-in `ruleset` tree
- a missing or unreadable required Wazuh directory

The allowance confirms only filename placement. It does not prove that the
installed and candidate files are equivalent. Review the diff and follow the
normal backup, validation, restart, verification, and rollback sequence.

## Non-default Wazuh root

For an extracted package tree or another deliberate root:

```bash
python3 tools/check_wazuh_collisions.py \
  --source unifi \
  --wazuh-root /path/to/wazuh-root
```

The root must contain all four supported `etc` and `ruleset` rule/decoder
directories. Missing directories fail closed.

## Exit status

| Exit | Meaning |
|---:|---|
| `0` | no unapproved matching identifier was found |
| `1` | collision, missing tree, unreadable file, or invalid candidate selection |
| `2` | command-line usage error reported by `argparse` |

Automation must treat every nonzero result as a stop condition.

## Scope limits

The checker identifies rule-ID and decoder-name reuse. It does not detect:

- duplicate `<localfile>` blocks or duplicate transports
- conflicting ports, file ownership, or permissions
- semantic differences between rules that use different IDs
- whether a source event matches the documented input contract
- whether Wazuh can load the complete resulting configuration

Use the [quick start](QUICKSTART.md), complete
[installation guide](../INSTALL.md), and all Wazuh validation commands after a
clean collision check.
