# Regression runner

`run_samples.py` executes every scenario containing `expected.json` and compares
the result with the actual Wazuh decoder/rule output. All lines from one
`raw.log` are sent to one process so frequency and timeframe rules retain state.

## Wazuh manager host

Run against the currently installed manager configuration:

```bash
sudo python3 tools/regression/run_samples.py
```

The defaults are:

- binary: `/var/ossec/bin/wazuh-logtest-legacy`
- Wazuh root: `/var/ossec`
- configuration: `etc/ossec.conf`

Use an isolated Wazuh tree by overriding them:

```bash
python3 tools/regression/run_samples.py \
  --logtest-bin /path/to/var/ossec/bin/wazuh-logtest-legacy \
  --wazuh-root /path/to/var/ossec \
  --config etc/ossec-audit.conf \
  --json-report regression-results.json
```

`scenario.json` classifies a scenario:

- `pass`: expected to pass now.
- `known_fail`: desired behavior is documented in `expected.json`, but a known
  production decoder/rule bug currently makes it fail. It remains a real FAIL.
- `pending`: skipped because a genuine sanitized production event is missing.

An unexpected pass for a `known_fail` scenario is reported as `XPASS`, requiring
review before the metadata is changed.

The audited Wazuh 4.14.8 baseline currently has no `known_fail` scenarios. Two
scenarios remain PENDING because authentic production input is unavailable:

- `homeassistant/auth-failed`
- `synology/bruteforce-login`

Do not add fabricated `raw.log` files to make these scenarios executable.
