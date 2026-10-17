# Wazuh AIO upgrade helper

This helper upgrades a package-based single-node Wazuh AIO on Ubuntu 24.04. It
starts with Wazuh `4.14.8` → `4.14.9` and intentionally does not perform an
automatic Wazuh Indexer rollback.

Do not run `apply` until the generated `preflight` log has been reviewed.

## Supported boundary

- Ubuntu 24.04, package-based installation
- one host running Wazuh Indexer, Manager, Dashboard, and Filebeat
- one-node Indexer cluster
- systemd and APT
- local Indexer admin certificate authentication

`PROFILE="generic"` is the default and checks only standard Wazuh components.
`PROFILE="homelab"` adds the BeardedTinker rsyslog ownership, custom telemetry,
repository regression and aggregate source-ingest checks. Docker, RPM and
multi-node deployments are outside this helper's scope.

An empty agent list is a warning in the generic profile, because a fresh AIO can
legitimately have no enrolled agents. It is blocking in the homelab profile.

It refuses another OS, missing central packages, a multi-node Indexer cluster,
wrong source versions, a pending reboot, failed configuration tests, unhealthy
services, insufficient disk, or unavailable target packages.

With `--refresh-apt`, an already-active official Wazuh source is used normally.
If the official source is commented out, the helper refreshes Wazuh metadata
through a root-only ephemeral source list in its run directory; it does not
permanently enable the repository. `apply` always performs this refresh and
installs the exact `.deb` artifacts downloaded before maintenance.

## Preserved production behavior

Every successful `preflight` creates and verifies a root-only configuration
archive before it can pass. It protects:

- `/var/ossec/etc`, including `ossec.conf`, custom decoders and custom rules
- Indexer, Filebeat and Dashboard configuration
- the installed Filebeat Wazuh module
- logrotate configuration

The homelab profile additionally protects rsyslog routing, checks UniFi and
UGREEN manager-side log paths, and validates SafeLine, Home Assistant and other
custom rules. Both profiles preserve manager rules, agent keys and secure
TCP/1514 configuration through `/var/ossec/etc`.

It also exports the live Indexer security configuration, records installed and
target package versions, service enablement, plugin inventories, regression
results and strict configuration checksums. The archive is listed, checked for
mandatory paths and verified against its SHA-256 checksum. It remains owned by
root because it contains certificates, agent keys and security configuration.

In the homelab profile, custom integration presence is checked by decoder names
and rule IDs across all XML files, not by assuming production filenames. Known
UGREEN production-vs-repository scenarios are explicit accepted failures and
remain warnings. Any other regression failure blocks preflight. Verification
reruns the suite and requires the complete JSON result to match the pre-upgrade
baseline exactly; changes require manual review.

The homelab verification phase also checks that rsyslog remains the only UDP/514
owner and that Wazuh does not start a competing syslog listener.

## Official order implemented

The `apply` command follows the official Wazuh central-component order:

1. Run validation, export Indexer security configuration, create and verify the
   root-only configuration backup, and create a successful Indexer snapshot.
2. Stop Filebeat and Dashboard.
3. Back up Indexer security configuration.
4. Disable shard replication, flush, and stop the single-node Manager.
5. Stop and upgrade Indexer; merge existing JVM customizations onto the new
   package file; initialize security; re-enable allocation; wait for green.
6. Upgrade Manager and run daemon configuration tests before starting it.
7. Refresh the Wazuh Filebeat module and template, preserve `filebeat.yml`,
   upgrade Filebeat, and upload pipelines/index management.
8. Upgrade Dashboard and merge existing Dashboard customization onto the new
   package file, then wait for the Dashboard HTTP endpoint to become ready.
9. Disable the Wazuh APT repository to prevent an accidental later upgrade.
10. Run full verification.

Any active official Wazuh `.list` entry changed in step 9 is copied into the
run directory before it is commented out.

The script uses `diff3` with the installed package baseline, live file, and new
package baseline for `jvm.options` and `opensearch_dashboards.yml`. It stops
before maintenance if either customization cannot be merged cleanly.
All package upgrades preserve existing conffiles by default. The two reviewed
three-way merge candidates are then installed explicitly, which also protects
custom Indexer settings such as `path.repo`.

The temporary Debian `policy-rc.d` guard is restored on success, command error,
`Ctrl+C`, and SIGTERM. Final verification waits a bounded time for all services,
requires complete green shard allocation, and verifies the exact Filebeat
target version. The install phase uses `--no-download`, so maintenance cannot
silently fetch a second copy instead of using the prepared local `.deb` files.
A failure to refresh unrelated APT metadata after disabling the Wazuh repository
is reported as a warning without skipping verification.

## Required preparation on ZimaBlade

After transferring and extracting the bundle, install it with:

```bash
sudo install -d -m 0750 /opt/wazuh-aio-upgrade
sudo install -o root -g root -m 0750 \
  wazuh-aio-upgrade.sh /opt/wazuh-aio-upgrade/wazuh-aio-upgrade.sh
sudo install -o root -g root -m 0640 \
  README.md /opt/wazuh-aio-upgrade/README.md
sudo install -o root -g root -m 0600 \
  wazuh-aio-upgrade.conf.example /etc/wazuh-aio-upgrade.conf
```

The command above installs the generic example. For the BeardedTinker host, use
`wazuh-aio-upgrade-homelab.conf.example` instead. An existing production
configuration without `PROFILE` must explicitly add `PROFILE="homelab"` before
installing this version; otherwise installation-specific checks intentionally
will not run.

Edit only non-secret settings. Set the snapshot repository name, Dashboard URL,
and optional expected agent-name substrings. The homelab profile also needs the
regression checkout path. Never place a password, token, private key, or
certificate content in this file.

1. Reboot first if Ubuntu reports `System restart required`.
2. Export Dashboard saved objects to:

   ```text
   /root/wazuh-dashboard-export.ndjson
   ```

   Keep it root-only. The script checks that the file exists and is non-empty.

3. Configure and verify an OpenSearch snapshot repository. Enter its name in
   `/etc/wazuh-aio-upgrade.conf`. The helper creates a pre-upgrade snapshot and
   records its exact repository/name, but never restores it automatically.

4. With `PROFILE="homelab"`, ensure the Wazuh Homelab Security checkout is
   available at `REPO_CHECKOUT` so the complete regression suite can run.

## Commands

After a host reboot, run the bounded read-only readiness check. It waits for
central services, reports the running kernel and reboot marker, verifies the
loaded snapshot path, distinguishes unassigned primaries from expected
single-node replicas, and checks Wazuh, Filebeat and Dashboard. The homelab
profile additionally checks rsyslog:

```bash
sudo /opt/wazuh-aio-upgrade/wazuh-aio-upgrade.sh post-reboot
```

The Wazuh daemon check requires the Manager daemons used by this deployment. It
does not fail merely because optional `clusterd`, `maild`, `agentlessd`,
`integratord`, or `csyslogd` processes are intentionally disabled.

Refresh APT metadata and run preflight:

```bash
sudo /opt/wazuh-aio-upgrade/wazuh-aio-upgrade.sh \
  preflight --refresh-apt --target 4.14.9
```

Review the newest log under `/var/log/wazuh-aio-upgrade/`. Do not continue with
any `FAIL` result. Unlike a read-only audit, `preflight` exports Indexer security
configuration, creates a root-only configuration backup, and creates an
OpenSearch snapshot when all validation gates pass. It does not stop services
or install packages.

The configuration backup is attempted after the checks even when a non-backup
gate fails, so a failed preflight can still leave a verified configuration
archive. The Indexer snapshot is created only when every earlier preflight gate
has passed.

After review and an explicit maintenance-window decision:

```bash
sudo /opt/wazuh-aio-upgrade/wazuh-aio-upgrade.sh \
  apply --target 4.14.9 --confirm-upgrade
```

Run verification again if needed, reusing the apply run ID printed in its log:

```bash
sudo /opt/wazuh-aio-upgrade/wazuh-aio-upgrade.sh \
  verify --target 4.14.9 --run-id REPLACE_WITH_APPLY_RUN_ID
```

## Checkpoints and logs

- execution log: `/var/log/wazuh-aio-upgrade/<run-id>.log`
- state and generated reports: `/var/lib/wazuh-aio-upgrade/<run-id>/`
- root-only backup under the configured `BACKUP_ROOT`
- last completed step: `<run-dir>/last-checkpoint`
- snapshot identity: `<run-dir>/index-snapshot`

Generated snapshot names contain only lowercase characters accepted by
OpenSearch. The exact repository/name is logged before creation and recorded in
both the run directory and the verified configuration-backup directory.

The script stops on the first command failure and prints the last checkpoint.
It does not run rollback commands from an error trap.

## Recovery guidance

### Failure before `central-services-stopped`

No Wazuh package has been upgraded. Review the log, correct the blocker, verify
all services remain active, and rerun `preflight` with a new run ID.

### Failure after allocation was set to `primaries`

Do not blindly rerun `apply`. First determine whether Indexer is running and
which package version is installed. If the old Indexer is healthy, re-enable
allocation manually only after review:

```bash
sudo /opt/wazuh-aio-upgrade/wazuh-aio-upgrade.sh verify \
  --target CURRENTLY_INSTALLED_VERSION --run-id FAILED_RUN_ID
```

Use the official Indexer API procedure to set
`cluster.routing.allocation.enable=all` when appropriate. The helper does not do
this automatically after an error because the correct action depends on the
actual Indexer state.

### Failure after `indexer-upgraded-green`

Do not downgrade or restore Indexer automatically. Preserve the log and run
directory, verify cluster health, and decide whether to continue the remaining
Manager/Filebeat/Dashboard steps or restore the recorded OpenSearch snapshot
using the official restore procedure.

### Configuration recovery

The backup archive contains sensitive configuration and certificates. Keep it
root-only and never attach it to an issue. Restore individual reviewed files,
not the entire archive over a partially upgraded system. Run the relevant
configuration test before restarting a service.

For Manager configuration:

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo /var/ossec/bin/wazuh-modulesd -t
sudo /var/ossec/bin/wazuh-logcollector -t
```

For Filebeat output, and rsyslog when using the homelab profile:

```bash
sudo rsyslogd -N1
sudo filebeat test config -e
sudo filebeat test output -e
```

### Package recovery

Do not improvise a mixed central-component version. Wazuh requires Indexer,
Manager and Dashboard to use the same patch version, while Manager must be the
same version or newer than agents. Follow official Wazuh recovery guidance and
use the recorded package versions when planning any package repair.

## Verification interpretation

In the homelab profile, no recent source event is a warning, not proof of a
broken integration. The authoritative custom-detection check is the sanitized
repository regression suite. The helper never logs raw indexed documents,
credentials, tokens, agent keys, or event payloads; source checks report only
aggregate counts.

## References

- Wazuh central-component upgrade guide:
  <https://documentation.wazuh.com/current/upgrade-guide/upgrading-central-components.html>
- Wazuh 4.14.9 release notes:
  <https://documentation.wazuh.com/current/release-notes/release-4-14-9.html>
- Wazuh backup and restore guide:
  <https://documentation.wazuh.com/current/migration-guide/index.html>
