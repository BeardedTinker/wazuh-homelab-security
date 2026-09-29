# Contributing

Thanks for considering contributing to **Wazuh Homelab Security**.

This repository is meant to stay practical, readable, and directly useful for real homelab environments.

The best contributions are usually:

- new decoders
- new rules
- sample logs
- dashboard ideas
- documentation improvements
- false positive reductions
- better sanitization workflows

---

# Contribution principles

Please keep contributions aligned with these goals:

- focus on **realistic homelab security use cases**
- prefer **high-signal detections**
- avoid overly noisy rules unless clearly documented
- keep examples **sanitized**
- prefer **simple and maintainable** logic over clever but fragile logic

---

# Repository structure

```
samples/
tools/regression/
tools/sanitize/
wazuh/decoders/
wazuh/manager/
wazuh/rules/
wazuh/ossec.conf.snippets/
```

Please place contributions in the correct folder.

Examples:

- new Home Assistant decoder → `wazuh/decoders/`
- new Synology rule → `wazuh/rules/`
- new sample logs → `samples/<source>/`

---

# Before opening a pull request

Please do the following:

1. validate XML syntax
2. test with `wazuh-logtest-legacy` on Wazuh 4.14.8
3. verify expected field extraction
4. verify rule behavior on repeated events if relevant
5. sanitize logs before publishing
6. update documentation when needed
7. run `python3 tools/regression/run_samples.py`

Recommended commands:

```
sudo /var/ossec/bin/wazuh-analysisd -t
sudo /var/ossec/bin/wazuh-authd -t
sudo /var/ossec/bin/wazuh-modulesd -t
sudo /var/ossec/bin/wazuh-logtest-legacy
sudo python3 tools/regression/run_samples.py
```

---

# Sample log guidelines

When adding sample logs:

- remove or replace public IPs if needed
- remove usernames unless essential
- remove serial numbers, IDs, tokens, and internal URLs
- keep samples short but representative
- add matching `expected.json`
- use `scenario.json` to distinguish `pass`, `known_fail`, and `pending`
- never replace a missing authentic event with a synthetic one just to pass CI

A good sample set should make it obvious:

- which decoder should match
- which fields should be extracted
- which rules should trigger

---

# Rule contribution guidelines

When adding or changing rules:

- use clear descriptions
- group related rules together
- avoid duplicate logic
- document noisy rules clearly
- prefer source-specific detections where possible
- use correlation carefully

Important:

Cross-source correlation must be validated against Wazuh history scope and
final-SID behavior; use `<global_frequency/>` only when cross-agent matching is intentional.

---

# Commit message suggestions

Recommended commit style:

```
feat: add Home Assistant authentication samples
fix: improve Home Assistant srcip extraction
docs: expand README with dashboard setup
chore: sanitize sample logs
```

---

# Pull request checklist

Before submitting, confirm:

- [ ] XML validates correctly
- [ ] rule behavior was tested
- [ ] logs are sanitized
- [ ] documentation was updated if needed
- [ ] filenames follow repository structure
- [ ] changes are scoped and understandable

---

# What not to contribute

Please avoid:

- unsanitized raw logs
- rules with heavy false positives and no explanation
- enterprise-only detections with no homelab relevance
- unrelated tooling
- breaking structural changes without discussion first

---

# Discussion first

For larger changes, open a discussion first.

Good examples:

- major rule restructuring
- folder structure changes
- dashboard export format changes
- active response design changes
- multi-source correlation strategy

---

# Thank you

Even small contributions help.

A cleaned sample log, one fixed regex, or one reduced false positive can save someone a lot of time.
