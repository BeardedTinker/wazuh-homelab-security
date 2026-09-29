# SafeLine samples

These samples contain collector-normalized SafeLine WAF events for Wazuh rule
regression testing.

All four scenarios are derived from end-to-end production events observed with
SafeLine 9.4.2, collector schema version 1, Wazuh agent 023, and Wazuh 4.14.8:

| Scenario | Production-confirmed result |
|---|---|
| `production-xss-sanitized` | blocked XSS rule `100520` |
| `production-sqli-sanitized` | standalone blocked SQLi rule `100510` |
| `production-repeated-xss-sanitized` | fifth same-source event triggers `100550` |
| `production-multi-vector-sanitized` | same-source XSS followed by SQLi triggers `100551` |

The samples preserve confirmed field structure and rule semantics while
replacing source addresses, hostnames, event identifiers, JA4 fingerprints, and
geographic data with documentation-only placeholders. The redundant nested
`safeline` metadata object is omitted because the rules use normalized top-level
fields.

Production also confirmed the complete path from the SafeLine Open API through
the collector, JSONL log, agent, built-in JSON decoder, custom rules, and
`alerts.json`. The SQLi `reason` value is retained in its sanitized sample only
as enrichment; rules classify the event from `attack_type=0` and never match on
localized reason text.
