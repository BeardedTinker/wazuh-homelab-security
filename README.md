# Wazuh Homelab Security

Detection rules and decoders used in the BeardedTinker homelab SIEM setup.
Practical Wazuh rules, decoders, sample logs, and dashboard building blocks for a real homelab setup.

This repository focuses on five common homelab telemetry sources:

- UniFi firewall / IDS / IPS events
- Synology DSM authentication events
- Home Assistant security-relevant logs via Wazuh Agent + journald
- SafeLine WAF attack events via a schema-versioned JSON collector
- UGREEN UGOS Pro authentication and storage events via a narrow Fluent Bit pipeline

The goal is simple: detect real security signals in a homelab without introducing enterprise-only complexity.

This repository reflects a real working homelab deployment.

## Audited production baseline

The current baseline was exported from and validated on **Wazuh 4.14.8**.

| Status | Meaning |
|---|---|
| Production-confirmed | Decoder/rule behavior was validated with the production manager and sanitized regression inputs. |
| Known limitation | The behavior is understood and intentionally retained. |
| PENDING | No claim is made until an authentic production event is available. |

Current regression status: **18 PASS, 0 FAIL, 2 PENDING, 0 XPASS**.
The two PENDING scenarios are `homeassistant/auth-failed` and
`synology/bruteforce-login`; synthetic events must not be used to close them.

## Production data flow

```text
UniFi / Synology ──UDP/514──> rsyslogd ──> /var/log/*.log ──> Wazuh localfile
UGREEN ──Fluent Bit RFC3164 UDP/514──> rsyslogd ──> /var/log/ugreen.log
Home Assistant ──agent secure TCP/1514──────────────────────> Wazuh remoted
SafeLine Open API ──schema-v1 collector──> attacks.json ──> Wazuh Agent 023
New agents ──password-protected TCP/1515────────────────────> Wazuh authd
Wazuh alerts ──Filebeat──> Wazuh Indexer ingest pipeline ──> GeoLocation.*
```

Wazuh does not own UDP/514 in this deployment. GeoIP enrichment happens after
manager rule evaluation and therefore cannot be referenced by manager rules.

---

# What this repo covers

## UniFi

Detection ideas currently implemented:

- WAN_LOCAL firewall drops
- SSH probes
- Synology DSM exposure attempts
- Home Assistant exposure attempts
- HTTP / HTTPS background probing
- high-rate repeated probes from the same source
- UniFi CEF IDS / IPS event parsing
- IDS targeting SSH management services
- IDS targeting HTTPS management services
- IDS targeting Home Assistant
- IDS targeting Synology DSM
- repeated IDS targeting of Home Assistant
- repeated IDS targeting of Synology DSM
- reconnaissance / multi-service probing detection

---

## Synology DSM

Detection ideas currently implemented:

- login success
- login failure
- repeated login failures from the same IP
- success after multiple failures from the same IP and user

---

## Home Assistant

Detection ideas currently implemented:

- invalid authentication from http.ban
- repeated invalid authentication from the same IP
- narrowly scoped Moonraker offline connection-error suppression
- UniFi port 8123 probe followed by Home Assistant brute force from the same source

---

## SafeLine WAF

Production-confirmed detections on Wazuh 4.14.8:

- blocked risk-level-3 SQL injection (`100510`)
- blocked risk-level-3 XSS (`100520`)
- five same-source risk-level-3 attacks in 300 seconds (`100550`)
- same-source XSS and SQLi within 300 seconds (`100551`)

SafeLine events use the built-in JSON decoder. Rule `100500` is a constrained
child of built-in rule `86600`, which otherwise claims JSON containing both
`timestamp` and `event_type`. Correlation uses the collector's static `srcip`
field and shared `safeline_waf_tier3_event` history.

`reason` remains enrichment only. A production SQLi event reported a numeric
attack value in localized reason text, so classification is based on
`attack_type`, not `reason`.

The production-confirmed collector source is tracked at
`safeline/collector/safeline-wazuh-collector.py` and installs as
`/usr/local/bin/safeline-wazuh-collector.py`. See `safeline/README.md` for its
runtime paths, privacy behavior, and pipeline.

---

## UGREEN UGOS Pro

Production deployment and regression coverage on Wazuh 4.14.8 includes:

- UGOS web login success and failure (`100600`, `100601`)
- repeated same-source web failures (`100610`)
- same-source web success after a failure (`100611`)
- root password changes at a deliberately low severity (`100620`)
- storage I/O errors and repeated same-device correlation (`100630`, `100631`)
- built-in Wazuh SSH and account rules `5715`, `5901`, and `5902`

The collector forwards only allowlisted `auth.log`, `kern.log`, and
`_COMM=log_serv` events. See `ugreen/README.md` for the pinned Fluent Bit
example, rsyslog routing, retention, and deployment constraints.

---

## GeoIP enrichment

This repository also includes an optional Wazuh Indexer GeoIP pipeline for enriching alerts with geographic context.

This allows dashboards to display:

- attack source countries
- geographic attack origin maps
- top attacking regions
- attack activity by geography

In the tested setup, GeoIP enrichment is performed in the Wazuh Indexer, not in the Wazuh manager alert JSON.

---

# Repository layout

```
.
├── safeline/
│   ├── collector/
│   └── README.md
├── ugreen/
│   ├── fluent-bit/
│   ├── rsyslog/
│   └── README.md
├── samples/
│   ├── homeassistant/
│   ├── safeline/
│   ├── synology/
│   ├── ugreen/
│   └── unifi/
├── tools/
│   ├── regression/
│   └── sanitize/
└── wazuh/
    ├── decoders/
    ├── indexer/
    ├── manager/
    ├── ossec.conf.snippets/
    └── rules/
```

---

# Folder purpose

### safeline/

Contains the production-confirmed schema-v1 SafeLine collector and its setup,
runtime-path, pipeline, and privacy documentation. Tokens and state files are
runtime-only and are not stored in this repository.

---

### samples/

Contains sanitized real-world log samples.

Each source folder typically contains:

- raw.log
- expected.json

This allows regression testing of decoders and rules.

### ugreen/

Contains the sanitized UGOS Pro transport example: pinned Fluent Bit Compose,
strict source allowlists, RFC3164 output, rsyslog source routing, log rotation,
and end-to-end installation notes.

---

### tools/sanitize/

Utilities used to sanitize logs before publishing them.

Typical sanitization includes:

- replacing internal IPs
- removing usernames
- removing device IDs
- removing sensitive URLs or tokens

Run the UniFi sanitizer with either a file or stdin:

```bash
bash tools/sanitize/sanitize-unifi.sh raw.log > sanitized.log
cat raw.log | bash tools/sanitize/sanitize-unifi.sh > sanitized.log
```

It replaces MAC values and maps non-documentation IPv4 addresses consistently
to RFC 5737 TEST-NET space.

---

### tools/regression/

`run_samples.py` sends every non-PENDING scenario through
`wazuh-logtest-legacy`, preserving state across all lines in each scenario.
See `tools/regression/README.md` for production and isolated-tree commands.

---

### wazuh/decoders/

Custom decoders grouped by source.

Examples:

- 0100-unifi-decoders.xml
- 0200-synology-decoders.xml
- 0300-homeassistant-decoders.xml

This includes the working UniFi UCG Ultra CEF decoder used to extract:

- srcip
- dstip
- srcport
- dstport
- protocol
- action

from UniFi IDS / IPS CEF events.

---

### wazuh/rules/

Custom rules grouped by source.

Examples:

- 0100-unifi-rules.xml
- 0200-synology-rules.xml
- 0300-homeassistant-rules.xml
- 0400-safeline-rules.xml
- 0500-ugreen-rules.xml

Rules are intentionally organized by source domain to keep the repository readable.

The UniFi rules include both:

- firewall / WAN_LOCAL detections
- IDS / IPS detections and correlation rules

---

### wazuh/manager/

Documents manager-level production assumptions. The tracked
`local_internal_options.conf` intentionally has no custom runtime override.
Enrollment secrets, agent keys, certificates, and credentials are never stored
in the repository.

---

### wazuh/ossec.conf.snippets/

Configuration snippets intended to be merged into ossec.conf.

Examples include:

- secure agent TCP/1514 transport
- password-protected authd TCP/1515 enrollment
- UniFi file-based log ingestion
- Synology log ingestion
- journald ingestion for Home Assistant
- UGREEN file-based log ingestion

In the tested deployment, `rsyslogd` owns UDP/514 and writes UniFi, Synology,
and UGREEN events to source-specific files; Wazuh reads them through
`<localfile>`. Stock Wazuh 4.14.8 manager-side GeoIP expects legacy libGeoIP
data and is not configured.

---

### wazuh/indexer/

Indexer-side files such as ingest pipelines.

This is where GeoIP enrichment for indexed alerts is defined.

Files in this directory can be used to enrich alerts with fields such as:

- GeoLocation.country_name
- GeoLocation.location

---

# Installation order

Recommended workflow when applying these rules:

1. Back up the current manager configuration.
2. Install or merge the decoder XML into `/var/ossec/etc/decoders/`.
3. Install or merge the rule XML into `/var/ossec/etc/rules/`.
4. Merge the required `ossec.conf.snippets/` sections exactly once.
5. Store the enrollment password in `/var/ossec/etc/authd.pass`; never put it
   in Git or inline XML.
6. Configure rsyslog to write UniFi, Synology, and UGREEN events to the paths
   consumed by the `<localfile>` blocks.
7. Optionally configure the Indexer GeoIP pipeline.
8. Validate XML and all Wazuh daemons before restarting.
9. Run the complete regression suite and verify indexed documents.

Do not load the same rule or decoder both from `local_rules.xml` and a split
repository XML file; that creates duplicate IDs or decoder names.

Typical commands:

```
sudo /var/ossec/bin/wazuh-analysisd -t
sudo /var/ossec/bin/wazuh-authd -t
sudo /var/ossec/bin/wazuh-modulesd -t
sudo /var/ossec/bin/wazuh-logtest-legacy
sudo python3 tools/regression/run_samples.py
sudo systemctl restart wazuh-manager
```

---

# Home Assistant integration notes

Home Assistant logs are ingested through a Wazuh Agent with journald access.

This means:

- events originate from the HA agent
- source IP extraction happens in custom decoders
- brute-force detection is done with Wazuh rules
- rule 100433 correlates the UniFi and Home Assistant events across agents

Example detection chain:

1. UniFi detects probe on port 8123
2. Home Assistant logs repeated invalid authentication
3. Wazuh rule 100410 triggers the brute-force alert
4. Wazuh rule 100433 correlates both sources by `srcip` within 900 seconds

Example correlation pattern:

- UniFi probe rule → 100132
- Home Assistant brute force rule → 100410
- Cross-agent attack-chain rule → 100433

Correlation can be done on:

```
data.srcip
```

within a time window.

## Correlation implementation

Wazuh stores correlation history for the final matched rule. A child rule such
as `100302` therefore does not also populate `if_matched_sid` history for parent
`100300`. The production rules avoid that blind spot with dedicated groups:

| Group | Used by |
|---|---|
| `unifi_wan_local_event` | `100150` high-rate WAN_LOCAL detection |
| `unifi_cef_ids_event` | `100301` repeated IDS and `100310` multi-port reconnaissance |
| `unifi_cef_homeassistant_event` | `100306` repeated Home Assistant targeting |
| `unifi_cef_synology_event` | `100307` repeated Synology targeting |
| `unifi_ha_probe_event` | `100433` UniFi→Home Assistant attack chain |
| `safeline_waf_tier3_event` | `100550` repeated attacks and `100551` multi-vector attacks |

One `100310` rule searches the shared CEF group; separate helpers for every
possible previous final SID are neither present nor required.

Rule `100433` uses `<global_frequency/>` because its UniFi and Home Assistant
events can originate from different agents. Its correlation logic is confirmed
with production `wazuh-logtest-legacy`; a real cross-agent runtime sequence was
not executed because it could trigger Home Assistant IP banning.

SafeLine correlations do not use `<global_frequency/>`: all validated SafeLine
events originate from agent 023. Every possible final tier-3 SafeLine child,
including correlation rules, retains `safeline_waf_tier3_event` so group history
does not depend on one final SID.

---

# Rule reference

| Rule | Level | Purpose | Status |
|---|---:|---|---|
| 100110 | 3 | WAN_LOCAL base event | Production-confirmed |
| 100116 / 100117 / 100119 | 12 / 5 / 5 | SSH, HTTPS, and HTTP probes | Production-confirmed |
| 100132 / 100133 | 10 / 12 | Home Assistant and Synology probes | Production-confirmed |
| 100150 | 13 | 12 WAN_LOCAL drops from one source in 120 seconds | Production-confirmed |
| 100300 | 5 | UniFi CEF IDS/IPS base event | Production-confirmed |
| 100301 | 13 | Five CEF IDS events from one source in 10 minutes | Production-confirmed |
| 100302–100305 | 13–14 | CEF targeting SSH, Home Assistant, Synology, or HTTPS | Production-confirmed |
| 100306 / 100307 | 15 | Repeated HA/Synology CEF targeting | Production-confirmed; service-wide threshold |
| 100310 | 15 | Same source targeting different destination ports | Production-confirmed |
| 100200 / 100201 | 3 / 12 | Synology login success/failure | Production-confirmed |
| 100210 | 15 | Five Synology failures from one source | Rule configured; authentic repeated production sample PENDING |
| 100220 | 16 | Two failures then success for the same user and source | Production-confirmed |
| 100419 | 0 | Exact Moonraker offline connection-error suppression | Production-confirmed |
| 100400 / 100410 | 10 / 14 | HA ban-component failure and brute force | Production-confirmed |
| 100433 | 15 | UniFi probe followed by HA brute force | Production logtest-confirmed; runtime cross-agent sequence not executed |
| 100420 / 100421 | 8 / 13 | HA auth failure outside ban component and repetition | PENDING authentic production event |
| 100500 | 3 | SafeLine schema-v1 WAF base child of built-in `86600` | Production-confirmed |
| 100503 / 100504 | 10 / 11 | Risk-level-3 event and blocked risk-level-3 event | Production-confirmed for risk 3/action 1 |
| 100510 / 100520 | 12 | Blocked SQLi / XSS | Production-confirmed |
| 100550 | 13 | Five same-source risk-level-3 attacks in 300 seconds | Production-confirmed |
| 100551 | 14 | Same-source attacks with different `attack_type` in 300 seconds | Production-confirmed |
| 100600 / 100601 | 3 / 5 | UGOS web login success/failure | Production-confirmed |
| 100610 | 12 | Five same-source UGOS web failures in five minutes | Production logtest-confirmed |
| 100611 | 10 | UGOS web success after same-source failure | Production logtest-confirmed |
| 100620 | 5 | UGREEN root password change | Production-confirmed; low severity is intentional |
| 100630 / 100631 | 10 / 13 | UGREEN storage I/O error and repeated same-device correlation | Production logtest-confirmed |

---

# Sample logs

Each source includes sample logs intended for testing.

Structure:

```
raw.log
expected.json
```

The expected file describes which decoder and rules should match.

This helps ensure that rule changes do not silently break detection logic.

---

# Dashboard ideas

Suggested dashboard panels:

- Top attacking IPs
- Attack timeline
- Top attacked services
- Attack sources map
- Top attackers (last 24 hours)
- Top attackers (historical)
- Alert severity distribution

Recommended index pattern:

```
wazuh-alerts-*
```

Example filter:

```
rule.id:(100132 OR 100300 OR 100310 OR 100410 OR 100433)
```

---

# Known limitations

- Rule 100433 depends on the same observable `srcip` across both sources; NAT or
  reverse proxies can merge unrelated clients.
- Rules 100306 and 100307 are service-wide and do not require `same_srcip`.
- The CEF decoder expects the documented extension-field ordering.
- Manager rules cannot use `GeoLocation.*` because Indexer enrichment happens later.
- some detections depend on original log formatting
- sample logs are sanitized and simplified

---

# Testing approach

When modifying decoders or rules:

1. validate XML syntax
2. test single events with `wazuh-logtest-legacy`
3. test repeated-event thresholds
4. verify extracted fields
5. verify indexing in dashboard

Only then add dashboards or active response.

---

# Troubleshooting

## An event has no custom decoder

1. Preserve the complete transport prefix and message body.
2. Run the exact line through `wazuh-logtest-legacy`.
3. Verify whether the event is CEF or raw WAN_LOCAL before changing a regex.
4. Do not broaden the decoder solely for a synthetic or legacy sample.

## A frequency rule misses child events

Wazuh correlation history follows the final matched rule. Verify the dedicated
group on every relevant final child and use `if_matched_group`; do not recreate
the removed per-SID helper pattern.

## UniFi or Synology events stop arriving

Check rsyslog UDP/514 and the corresponding `/var/log/*.log` file first, then
check the Wazuh `<localfile>` collector. Wazuh itself does not bind UDP/514 in
this baseline.

## Enrollment fails but existing agents work

Enrollment uses authd TCP/1515 and `/var/ossec/etc/authd.pass`. Existing agents
use their established keys over secure TCP/1514, so the two paths must be
diagnosed separately.

## GeoIP fields are absent

Check the Indexer pipeline and index template. Manager validation can pass while
`GeoLocation.*` is absent because enrichment occurs after rule evaluation.

---

# Active response warning

Automatic blocking should be enabled only after careful validation.

Before enabling active response:

- confirm decoder accuracy
- understand false positive patterns
- validate event flow end-to-end

A recommended first step is deploying active response disabled by default.

---

# Sanitization

Before publishing logs always sanitize:

- IP addresses
- hostnames
- usernames
- internal paths
- tokens or IDs

---

# License

This project is licensed under the [MIT License](LICENSE).

---

## Rule ID ranges

Custom rules in this repository use a dedicated rule ID range to avoid conflicts with built-in Wazuh rules or other custom rule sets.

```
100100–100199   UniFi firewall detections
100200–100299   Synology DSM authentication detections
100300–100399   UniFi IDS / IPS detections
100400–100499   Home Assistant detections
100500–100599   SafeLine WAF detections
100600–100699   UGREEN UGOS Pro detections
```

If you extend this repository, it is recommended to keep new rules within the same logical ranges.

---

# Contributing

Future improvements may include:

- additional Home Assistant detections
- UniFi IDS enrichment
- dashboard exports
- OpenSearch monitor examples
- optional active response examples

---

# Supported Wazuh version

This repository is tested primarily with:

```
Wazuh 4.14.8
```

Earlier versions may still work but some features behave differently depending on the Wazuh release.

In particular:

- UniFi IDS / IPS events rely on the custom `unifi-ucg-cef` decoder included in this repository.
- Stock Wazuh 4.14.8 manager packages do not consume GeoLite2 `.mmdb` files for rule evaluation.
- In this setup GeoIP enrichment is performed in the **Wazuh Indexer** using an ingest pipeline.

Because of these differences, dashboards and monitors should rely on structured fields such as:

```
data.srcip.keyword
manager.name.keyword
GeoLocation.country_name
GeoLocation.location
```

instead of scripted fields extracted from `full_log`.

If dashboards appear empty, first verify:

1. decoders are loaded correctly
2. alerts contain extracted fields such as `data.srcip`
3. the ingest pipeline is active in the Wazuh Indexer
