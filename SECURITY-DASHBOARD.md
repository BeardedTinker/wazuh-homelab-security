# Wazuh Homelab Security Dashboard

This document describes the dashboard used together with the rules and decoders from this repository.

The goal is to provide a **simple but effective SIEM-style overview for a homelab environment**.

The examples assume the following index pattern:

```
wazuh-alerts-*
```

---

# Dashboard panels

## Top attacking IPs

Shows the most active attacking source IP addresses.

Configuration:

Metric:
```
Count
```

Bucket:

```
Terms
Field: data.srcip
Size: 10
```

Recommended filter:

```
rule.id:(100132 OR 100300 OR 100310)
```

This panel helps identify:

- repeated scanners
- brute-force attempts
- persistent attackers

---

## Attack timeline

Shows attacks over time.

Configuration:

Metric:

```
Count
```

Bucket:

```
Date Histogram
Field: timestamp
Interval: Auto
```

Recommended filter:

```
rule.id:(100132 OR 100300 OR 100310)
```

Useful for:

- spotting scanning waves
- identifying attack bursts
- correlating events with external triggers

---

## Top attacked services

Shows which ports or services are most frequently targeted.

Configuration:

Metric:

```
Count
```

Bucket:

```
Terms
Field: dstport
Size: 10
```

Example detections include:

- SSH probes
- Home Assistant probes
- Synology DSM probes
- HTTP background scanning

---

## Attack sources map

Geographic visualization of attack sources.

Configuration:

Metric:

```
Count
```

Bucket:

```
Geohash
Field: GeoLocation.location
Precision: 3 or 4
```

This uses the GeoIP enrichment already present in Wazuh.

The map helps visualize:

- attack distribution
- geographic clustering
- unusual regions of activity

---

## Alert severity

Displays distribution of alert severity levels.

Configuration:

Metric:

```
Count
```

Bucket:

```
Terms
Field: rule.level
```

Example severity levels used in this repository:

Level | Meaning
-----|--------
5 | low signal / noise
8 | suspicious activity
10 | confirmed attack event
14 | brute force detection
15 | multi-stage attack correlation

---

## Top attackers (24h)

Shows most active attackers within the last 24 hours.

Configuration is identical to **Top attacking IPs**, but the dashboard time filter is set to:

```
Last 24 hours
```

This highlights **current active threats**.

---

## Top attackers (history)

Shows historical attack sources.

Typical dashboard time filter:

```
Last 30 days
```

This helps detect:

- persistent scanners
- recurring attackers
- background internet noise

---

# Example detection flow

Example attack chain detected by the system:

1. UniFi detects probe on port 8123
2. Home Assistant logs repeated authentication failures
3. Wazuh rule detects brute-force pattern

Example rules:

UniFi probe → `100132`

Home Assistant auth failure → `100300`

Home Assistant brute force → `100310`

Correlation key:

```
data.srcip
```

---

# Dashboard usage tips

Recommended workflow when investigating events:

1. start with **Attack timeline**
2. identify spike in activity
3. check **Top attacking IPs**
4. verify service targeted in **Top attacked services**
5. check origin using **Attack sources map**

This provides a quick but effective investigation path.

---

# Future improvements

Possible dashboard improvements:

- attack chain visualization
- automated attack scoring
- long-term attacker reputation
- OpenSearch monitor alerts
- automatic firewall blocking triggers
