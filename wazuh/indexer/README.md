# Wazuh Indexer pipelines

This directory contains optional OpenSearch / Wazuh Indexer components used to enrich security events before they are stored in the alerts index.

The most important pipeline provided here is **GeoIP enrichment**.

---

# GeoIP enrichment

The file:

`geoip-pipeline.json`

adds geographic context to alert events by resolving the **source IP address** of an attack.

The pipeline enriches the document with a new object:

`GeoLocation`

which contains fields such as:

```
GeoLocation.country_name
GeoLocation.location.lat
GeoLocation.location.lon
```

This allows Wazuh dashboards to display:

- attack source countries
- geographic maps of attack origins
- top attacking regions
- correlation of attack activity by geography

---

# Requirements

Download the MaxMind GeoLite database.

Example:

`GeoLite2-Country.mmdb`

Place the file in the Wazuh Indexer GeoIP database directory.

Typical locations:

```
/usr/share/wazuh-indexer/modules/ingest-geoip/
```

or

```
/var/ossec/etc/
```

depending on your deployment.

---

# Create the pipeline

Example command:

```
curl -k -u admin:admin -X PUT \
"https://localhost:9200/_ingest/pipeline/wazuh-geoip" \
-H "Content-Type: application/json" \
-d @geoip-pipeline.json
```

---

# Attach pipeline to Wazuh alerts index

Attach the pipeline to the alerts index template so that every alert document is enriched automatically.

Example:

```
PUT _index_template/wazuh-alerts
```

with the pipeline defined in the index settings.

---

# Result

After the pipeline is active, alert documents will contain:

```
GeoLocation.country_name
GeoLocation.location
```

Example:

```
"GeoLocation": {
  "country_name": "Russia",
  "location": {
    "lat": 55.7386,
    "lon": 37.6068
  }
}
```

---

# Dashboard usage

Recommended fields for dashboards:

```
GeoLocation.country_name
GeoLocation.location
data.srcip.keyword
manager.name.keyword
```

Avoid using scripted fields to extract IP addresses from logs.

The UniFi decoder already extracts structured fields such as:

```
data.srcip
data.dstip
data.dstport
```

These should be used directly in visualizations and aggregations.
