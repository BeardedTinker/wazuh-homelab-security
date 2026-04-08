# Wazuh Homelab Security

Practical Wazuh rules, decoders, sample logs, and dashboard building blocks for a real homelab setup.

This repository focuses on three common homelab telemetry sources:

- UniFi firewall / IDS / IPS events
- Synology DSM authentication events
- Home Assistant security-relevant logs via Wazuh Agent + journald

The goal is simple: detect real security signals in a homelab without introducing enterprise-only complexity.

This repository reflects a real working homelab deployment.

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
- suspicious websocket authentication activity
- repeated websocket suspicious activity
- Moonraker websocket reconnect noise suppression

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
├── samples/
│   ├── homeassistant/
│   ├── synology/
│   └── unifi/
├── tools/
│   └── sanitize/
└── wazuh/
    ├── decoders/
    ├── indexer/
    ├── ossec.conf.snippets/
    └── rules/
```

---

# Folder purpose

### samples/

Contains sanitized real-world log samples.

Each source folder typically contains:

- raw.log
- expected.json

This allows regression testing of decoders and rules.

---

### tools/sanitize/

Utilities used to sanitize logs before publishing them.

Typical sanitization includes:

- replacing internal IPs
- removing usernames
- removing device IDs
- removing sensitive URLs or tokens

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

Rules are intentionally organized by source domain to keep the repository readable.

The UniFi rules include both:

- firewall / WAN_LOCAL detections
- IDS / IPS detections and correlation rules

---

### wazuh/ossec.conf.snippets/

Configuration snippets intended to be merged into ossec.conf.

Examples include:

- remote syslog listener
- UniFi log ingestion
- Synology log ingestion
- journald ingestion for Home Assistant
- optional manager-side GeoIP database reference

Note: manager-side GeoIP support may depend on how the Wazuh manager package was built.

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

1. copy decoders to Wazuh decoder directory
2. copy rules to Wazuh rules directory
3. merge required ossec.conf snippets
4. create optional Indexer ingest pipelines
5. validate configuration
6. restart Wazuh manager
7. test with wazuh-logtest
8. verify indexed documents in Wazuh Indexer / Dashboard

Typical commands:

```
sudo /var/ossec/bin/wazuh-analysisd -t
sudo systemctl restart wazuh-manager
sudo /var/ossec/bin/wazuh-logtest
```

---

# Home Assistant integration notes

Home Assistant logs are ingested through a Wazuh Agent with journald access.

This means:

- events originate from the HA agent
- source IP extraction happens in custom decoders
- brute-force detection is done with Wazuh rules
- cross-source correlations are handled at the dashboard or monitor level

Example detection chain:

1. UniFi detects probe on port 8123
2. Home Assistant logs repeated invalid authentication
3. Wazuh rule triggers brute-force alert

Because these events may come from different data sources, correlation is often more reliable at the dashboard or monitor level.

Example correlation pattern:

UniFi probe rule → 100132  
Home Assistant brute force rule → 100310

Correlation can be done on:

```
data.srcip
```

within a time window.

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
rule.id:(100132 OR 100300 OR 100310)
```

---

# Known limitations

- cross-source correlation is intentionally not implemented purely as Wazuh rules
- some detections depend on original log formatting
- sample logs are sanitized and simplified

---

# Testing approach

When modifying decoders or rules:

1. validate XML syntax
2. test single events with wazuh-logtest
3. test repeated-event thresholds
4. verify extracted fields
5. verify indexing in dashboard

Only then add dashboards or active response.

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

Choose any license appropriate for sharing detection logic.

Permissive licenses are typically easiest for reuse.

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
Wazuh 4.14.x
```

Earlier versions may still work but some features behave differently depending on the Wazuh release.

In particular:

- UniFi IDS / IPS events rely on the custom `unifi-ucg-cef` decoder included in this repository.
- Some Wazuh manager builds may not include GeoIP support in the alert pipeline.
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
