# Testing and troubleshooting

Use this guide after reading the selected source contract and the
[safe installation guide](../INSTALL.md). Do not broaden a decoder or lower a
threshold solely to make a synthetic or legacy sample pass.

## Testing approach

When modifying decoders or rules:

1. Validate XML and all manager daemon configuration.
2. Test individual authentic events with `wazuh-logtest-legacy`.
3. Test repeated-event thresholds while preserving scenario state.
4. Verify extracted fields and final matched rules.
5. Run the complete repository regression suite.
6. Verify indexed alert fields before creating dashboards or monitors.

Typical commands are documented in [`INSTALL.md`](../INSTALL.md) and the
[regression guide](../tools/regression/README.md).

## An event has no custom decoder

1. Preserve the complete transport prefix and message body.
2. Run the exact line through `wazuh-logtest-legacy`.
3. Verify that the event matches the source guide's documented input contract.
4. For UniFi, distinguish CEF IDS/IPS input from raw WAN_LOCAL input.
5. Do not broaden the decoder solely for a synthetic or unsupported format.

## A frequency rule misses child events

Wazuh correlation history follows the final matched rule. A child match does
not also populate `if_matched_sid` history for every parent. Verify the dedicated
group on each relevant final child and use `if_matched_group`; do not recreate
the removed per-SID helper pattern.

See [correlation behavior](DETECTION_REFERENCE.md#correlation-implementation)
for the groups used by the current rules.

## UniFi or Synology events stop arriving

Check the rsyslog UDP/514 listener and the corresponding `/var/log/*.log` file
before changing a decoder. Then verify the Wazuh `<localfile>` collector. Wazuh
itself does not bind UDP/514 in the documented baseline.

## Enrollment fails but existing agents work

Enrollment uses authd TCP/1515 and `/var/ossec/etc/authd.pass`. Existing agents
use established keys over secure TCP/1514. Diagnose enrollment and ongoing agent
transport as separate paths.

## GeoIP fields are absent

Check the Indexer pipeline and index template. Manager validation can pass while
`GeoLocation.*` is absent because enrichment occurs after manager rule
evaluation.

If dashboards remain empty, verify in order:

1. decoders loaded correctly
2. alerts contain fields such as `data.srcip`
3. the ingest pipeline is active in the Wazuh Indexer
4. the dashboard uses the structured indexed field names

## A dashboard is empty

An empty dashboard is not proof that collection is healthy. Verify a matching
indexed document and its mapping before changing a query. Follow the sanitized
[Wazuh dashboard recipes](../SECURITY-DASHBOARD.md) and the
[Home Assistant dashboard guide](../homeassistant/adapter/DASHBOARD.md).

## Validation fails before restart

Do not restart the manager. Restore only the files changed during the attempted
installation and rerun all daemon tests. Follow the rollback sequence in
[`INSTALL.md`](../INSTALL.md); do not restore a complete backup over unrelated
newer changes.

## Active response warning

Automatic blocking should be enabled only after decoder accuracy, false-positive
behavior, event flow, rollback, and lockout recovery are understood. The
recommended first step is an example that remains disabled by default. Installing
this repository does not enable active response.
