# SafeLine collector

The production-confirmed schema-v1 collector is stored at:

```text
safeline/collector/safeline-wazuh-collector.py
```

Install it on the SafeLine host as:

```bash
sudo install -o root -g root -m 0755 \
  safeline/collector/safeline-wazuh-collector.py \
  /usr/local/bin/safeline-wazuh-collector.py
```

The tracked collector SHA-256 is:

```text
2c7a4b0a3ebe01314db33682af4ccc523499f30f473ae155f489a41b2a9912f7
```

## Production data flow

```text
SafeLine Open API (/api/open/records)
  → /usr/local/bin/safeline-wazuh-collector.py
  → /var/log/safeline/attacks.json (schema-v1 JSONL)
  → Wazuh Agent 023 localfile collection
  → Wazuh Manager built-in JSON decoder
  → SafeLine rules 100500–100551
  → alerts.json / Wazuh Indexer
```

Runtime paths used by the collector:

| Purpose | Path |
|---|---|
| API token, read at runtime | `/etc/safeline-wazuh/token` |
| Dedupe state | `/var/lib/safeline-wazuh/state.json` |
| JSONL output | `/var/log/safeline/attacks.json` |

The API token and state file are runtime data and must never be committed. The
collector sends the token only through the `X-SLCE-API-Token` request header.
Scheduling or service management remains host-specific and is not included in
this repository.

## Schema and privacy behavior

The collector emits `schema_version=1`, preserves separate `source_ip` and
`socket_ip`, and adds Wazuh static aliases such as `srcip`, `srcport`, `dstip`,
and `dstport` only when values are valid. It also emits `action_name`,
`attack_type_name`, and query-free `path_only` while preserving the original
`url_path`.

Raw request/response headers, bodies, payloads, and standalone query strings are
not copied to Wazuh. The nested `safeline` object is restricted to an explicit
metadata allowlist. `reason` is retained only as enrichment; rules classify
attacks from `attack_type`.

This exact collector version was validated end to end with blocked XSS and SQLi
events plus repeated and multi-vector correlations on Wazuh 4.14.8.
