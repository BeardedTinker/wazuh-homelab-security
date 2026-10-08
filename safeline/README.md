# SafeLine collector and Wazuh setup

This guide connects production-confirmed SafeLine WAF events to the Wazuh
4.14.8 baseline in this repository. The collector runs on the SafeLine host,
normalizes Open API records into schema-v1 JSONL, and lets a local Wazuh agent
forward that file to the manager.

Follow the backup, validation, restart, and rollback gates in
[`INSTALL.md`](../INSTALL.md). SafeLine is an independent optional source.

## Compatibility boundaries

The current implementation was validated with:

- SafeLine 9.4.2
- collector schema version 1
- Wazuh Agent and Manager 4.14.8
- the Wazuh 4.14.8 built-in JSON decoder and rule `86600`

The collector has fixed runtime assumptions:

| Purpose | Value |
|---|---|
| API endpoint | `https://127.0.0.1:9443/api/open/records` |
| API token file | `/etc/safeline-wazuh/token` |
| Dedupe state | `/var/lib/safeline-wazuh/state.json` |
| JSONL output | `/var/log/safeline/attacks.json` |
| Page size | 100 records |
| Maximum pages per run | 20 |
| Remembered event IDs | 2,000 |

The API endpoint is not configurable. Run this collector on the SafeLine host;
do not repurpose its disabled certificate verification for a remote or
untrusted endpoint. Certificate verification is disabled only because the
production collector reaches the local management endpoint by loopback IP and
its certificate may not validate for `127.0.0.1`.

Compatibility with another SafeLine or Wazuh version must be confirmed with
sanitized fixtures and the complete regression suite. In particular, rule
`100500` is deliberately a child of built-in Wazuh rule `86600`, whose behavior
is part of the audited 4.14.8 contract.

## Production data flow

```text
SafeLine Open API (/api/open/records)
  → /usr/local/bin/safeline-wazuh-collector.py
  → /var/log/safeline/attacks.json (schema-v1 JSONL)
  → Wazuh agent JSON localfile collection
  → Wazuh Manager built-in JSON decoder
  → SafeLine rules 100500–100551
  → alerts.json / Wazuh Indexer
```

## Install and verify the collector

Install the tracked collector on the SafeLine host:

```bash
sudo install -o root -g root -m 0755 \
  safeline/collector/safeline-wazuh-collector.py \
  /usr/local/bin/safeline-wazuh-collector.py
```

Verify the installed file before first use:

```bash
sha256sum /usr/local/bin/safeline-wazuh-collector.py
```

The production-confirmed SHA-256 is:

```text
2c7a4b0a3ebe01314db33682af4ccc523499f30f473ae155f489a41b2a9912f7
```

Stop if the checksum differs unexpectedly. A deliberate collector change must
update this checksum, schema fixtures when applicable, and release notes
together.

## Store the API token

Create the token directory and edit the token with a root-only editor:

```bash
sudo install -d -o root -g root -m 0700 /etc/safeline-wazuh
sudoedit /etc/safeline-wazuh/token
sudo chown root:root /etc/safeline-wazuh/token
sudo chmod 0600 /etc/safeline-wazuh/token
```

The file contains only the SafeLine Open API token. Do not place the token in a
command-line argument, environment file committed to Git, service unit, sample,
or issue report. The collector sends it only in the
`X-SLCE-API-Token` request header.

## Perform one manual collection

Run the collector once before configuring a scheduler:

```bash
sudo /usr/local/bin/safeline-wazuh-collector.py
```

A successful run prints only the number of newly written events. It creates or
updates the state file and appends previously unseen events to the JSONL output.
The API returns newest events first; the collector reverses each new batch so
the output remains chronological.

If at least one event was written, validate the last JSONL row without printing
it:

```bash
sudo tail -n 1 /var/log/safeline/attacks.json \
  | python3 -m json.tool >/dev/null
```

Do not publish the raw output. Although the collector removes headers, bodies,
payloads, and standalone query strings, retained enrichment can still identify
internal services or clients.

## Configure the Wazuh agent

Merge the tracked fragment into the Wazuh agent running on the SafeLine host or
into that agent's shared configuration:

```xml
<localfile>
  <log_format>json</log_format>
  <location>/var/log/safeline/attacks.json</location>
</localfile>
```

The fragment is stored at:

```text
wazuh/ossec.conf.snippets/0450-localfiles-safeline.xml
```

Add it exactly once. It belongs on the agent that can read the JSONL file, not
automatically on the Wazuh manager. Verify that the agent process can read the
file while the token and dedupe state remain root-only.

## Install the manager rules

SafeLine uses Wazuh's built-in JSON decoder, so no custom decoder file is
installed. After creating the manager backup described in `INSTALL.md`, install
only the SafeLine rules:

```bash
sudo install -o root -g wazuh -m 0640 \
  wazuh/rules/0400-safeline-rules.xml \
  /var/ossec/etc/rules/0400-safeline-rules.xml
```

## Validate before restart

Run the authoritative manager test and SafeLine regression scenarios:

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo python3 tools/regression/run_samples.py --samples samples/safeline
```

Do not restart if either command fails. Restore the files changed during this
installation using the rollback procedure in `INSTALL.md`.

After validation passes, complete the remaining daemon tests from `INSTALL.md`,
restart the manager, and verify that no new `ERROR` or `CRITICAL` message
appears in `/var/ossec/logs/ossec.log`.

## Scheduling contract

Scheduling or service management remains host-specific and is intentionally not
shipped as an unvalidated service unit or timer. Any scheduler must:

- run with access to the root-only token and state
- preserve the collector's nonzero exit status and stderr
- prevent overlapping collector processes
- avoid printing the API token or JSONL event content
- monitor stale output and repeated failures separately from valid zero-event
  runs

The collector does not currently implement an inter-process lock. Concurrent
runs can read the same dedupe state and append duplicate records. Validate a
host-specific timer or service before describing it as supported.

## Schema and privacy behavior

The collector emits `schema_version=1`, preserves separate `source_ip` and
`socket_ip`, and adds Wazuh static aliases such as `srcip`, `srcport`, `dstip`,
and `dstport` only when values are valid. It also emits `action_name`,
`attack_type_name`, and query-free `path_only` while preserving the original
`url_path`.

Raw request and response headers, bodies, payloads, and standalone query strings
are not copied to Wazuh. The nested `safeline` object is restricted to an
explicit metadata allowlist. `reason` is retained only as enrichment; rules
classify attacks from numeric `attack_type` values.

## Detection and regression status

All current SafeLine scenarios are production-derived PASS cases:

- blocked risk-tier-3 SQL injection, rule `100510`
- blocked risk-tier-3 XSS, rule `100520`
- five same-source tier-3 attacks in five minutes, rule `100550`
- same-source XSS and SQL injection within five minutes, rule `100551`

SafeLine correlations do not use global frequency history because all validated
events originate from one Wazuh agent. Every tier-3 child retains group
`safeline_waf_tier3_event` so correlation does not depend on one final rule ID.

## Troubleshooting

### Collector reports an API or token error

Confirm that the token file exists, contains one non-empty token, and remains
mode `0600`. Verify the local SafeLine Open API is available at the fixed
loopback endpoint. Do not print the token while diagnosing the request.

### Collector succeeds but the agent sends no event

Confirm that `/var/log/safeline/attacks.json` exists, contains one valid JSON
object per line, and is readable by the Wazuh agent process. Verify that the
JSON localfile fragment is loaded exactly once on the SafeLine agent.

### JSON decodes but rule `100500` does not match

Verify the event has `schema_version=1`, `integration=safeline`, and
`event_type=waf_attack`. Then confirm the installed Wazuh version's built-in
JSON rule `86600` still provides the parent behavior audited on 4.14.8.

### Duplicate events appear

Check for overlapping scheduler runs before changing dedupe logic. The state
file records a bounded set of seen event IDs but does not lock concurrent
collector processes.
