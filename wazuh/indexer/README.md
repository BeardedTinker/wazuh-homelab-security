# Wazuh Indexer pipelines

This directory contains optional OpenSearch / Wazuh Indexer components used to enrich security events before they are stored in the alerts index.

The most important pipeline provided here is **GeoIP enrichment**.

---

# GeoIP enrichment

The file:

`geoip-pipeline.json`

adds geographic context to alert events by resolving the source IP address of an attack.

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

Place the file in the Indexer ingest-geoip directory:

```text
/usr/share/wazuh-indexer/modules/ingest-geoip/
```

In the tested homelab setup, the database file was available on the same host as Wazuh Indexer and used by the ingest pipeline.

---

# Create the pipeline

Use authenticated Indexer credentials from environment variables; never put
them in this repository or shell history:

```
curl --user "$INDEXER_USER:$INDEXER_PASSWORD" -X PUT \
"https://localhost:9200/_ingest/pipeline/wazuh-geoip" \
-H "Content-Type: application/json" \
-d @geoip-pipeline.json
```

This creates an ingest pipeline named:

```
wazuh-geoip
```

---

# Attach the pipeline to Wazuh alerts

Attach the pipeline to the Wazuh alerts index template so that alert documents are enriched automatically when they are indexed.

Example:

```
curl --user "$INDEXER_USER:$INDEXER_PASSWORD" -X PUT "https://localhost:9200/_index_template/wazuh-alerts" \
-H "Content-Type: application/json" -d '
{
  "index_patterns": ["wazuh-alerts-*"],
  "template": {
    "settings": {
      "index.default_pipeline": "wazuh-geoip"
    }
  }
}'
```

If your existing deployment uses a different index template name, adjust the template accordingly.

---

# Verify the pipeline

Generate a test alert that contains:

```
data.srcip
```

Then query the indexed alert document and verify that it contains:

```
GeoLocation.country_name
GeoLocation.location
```

Example search:

```
curl --user "$INDEXER_USER:$INDEXER_PASSWORD" -X POST "https://localhost:9200/wazuh-alerts-*/_search" \
-H "Content-Type: application/json" -d '
{
  "size": 1,
  "sort": [
    {
      "@timestamp": {
        "order": "desc"
      }
    }
  ],
  "query": {
    "term": {
      "data.srcip": "198.51.100.12"
    }
  }
}'
```

Expected result shape (values depend on the test address and database):

```
"GeoLocation": {
  "country_name": "Example country",
  "location": {
    "lon": 0.0,
    "lat": 0.0
  }
}
```

---

# Result

Once the pipeline is active, indexed alert documents can include fields like:

```
GeoLocation.country_name
GeoLocation.location
```

These fields can then be used in dashboards, visualizations, filters, and maps.

---

# Dashboard usage

Recommended fields for dashboards:

```
GeoLocation.country_name
GeoLocation.location
data.srcip.keyword
manager.name.keyword
```

Avoid using scripted fields to extract source IP addresses from raw logs.

In this repository the UniFi decoder already extracts structured fields such as:

```
data.srcip
data.dstip
data.dstport
```

These fields should be used directly in visualizations and aggregations.

---

# Notes

- GeoIP enrichment in this homelab setup is performed in the **Wazuh Indexer**, not in the Wazuh manager alert JSON.
- This means `alerts.json` may not contain `GeoLocation`, while indexed documents in `wazuh-alerts-*` do.
- Stock Wazuh 4.14.8 manager GeoIP uses legacy libGeoIP data and does not consume the GeoLite2 `.mmdb` pipeline database.
- The production deployment shows Indexer-side `GeoLocation.*` enrichment, but
  the exact live template and credential configuration are intentionally not
  exported into this repository.
