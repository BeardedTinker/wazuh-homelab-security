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

An expected result can also declare `rules_forbidden`. The scenario fails if
any listed rule appears, which protects narrow decoders against known benign
formats such as a normal Minecraft post-login disconnect.

The audited Wazuh 4.14.9 baseline currently has 25 passing scenarios, no
`known_fail` scenarios, and two
scenarios remain PENDING because authentic production input is unavailable:

- `homeassistant/auth-failed`
- `synology/bruteforce-login`

Do not add fabricated `raw.log` files to make these scenarios executable.

## GitHub Actions baseline

The repository workflow also runs the complete suite in an isolated Wazuh
Manager `4.14.9-1` tree on `ubuntu-24.04`. The preparation helper downloads the
exact official `amd64` package, verifies its pinned SHA-256 and Debian package
metadata, extracts it without installing manager services, and copies only this
repository's published decoder, rule, and internal-options files into the test
tree.

The workflow creates the package-required local `wazuh` service identity on the
disposable runner. It does not start Wazuh, open listeners, contact a live
manager, or use repository secrets. A successful or failed executable run
uploads `wazuh-regression-results-4.14.9` as a JSON artifact for 14 days. The
package cache is an optimization only; every cached package is checked against
the pinned digest before extraction.

To prepare the same isolated tree manually on a compatible Debian or Ubuntu
`amd64` host:

```bash
sudo groupadd --system wazuh
sudo useradd --system --gid wazuh --home-dir /var/ossec \
  --no-create-home --shell /usr/sbin/nologin wazuh
bash tools/regression/prepare_ci_wazuh.sh \
  .cache/wazuh/wazuh-manager_4.14.9-1_amd64.deb \
  /path/to/new/wazuh-manager-4.14.9
```

Use a destination that does not already exist. The helper deliberately refuses
to replace or clean an existing path.
