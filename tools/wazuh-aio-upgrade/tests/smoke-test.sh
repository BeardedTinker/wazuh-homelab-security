#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/wazuh-aio-upgrade.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

bash -n "$SCRIPT" || fail "bash syntax"
pass "bash syntax"

grep -q '^SCRIPT_VERSION="0.2.8"$' "$SCRIPT" || fail "release version"
if grep -qi 'draft' "$SCRIPT" "$ROOT/README.md"; then
  fail "draft marker remains in release files"
fi
pass "release metadata"

if ! output=$(bash "$SCRIPT" --help --config /definitely/missing/wazuh.conf 2>&1); then
  fail "help must not load configuration"
fi
grep -q 'preflight' <<<"$output" || fail "help lists preflight"
grep -q 'post-reboot' <<<"$output" || fail "help lists post-reboot"
grep -q 'apply' <<<"$output" || fail "help lists apply"
grep -q 'verify' <<<"$output" || fail "help lists verify"
pass "help lists all modes without loading configuration"

grep -q 'apply requires --confirm-upgrade' "$SCRIPT" || fail "apply confirmation gate"
grep -q 'No automatic Indexer rollback was attempted' "$SCRIPT" || fail "no automatic rollback statement"
grep -q 'systemctl stop filebeat wazuh-dashboard' "$SCRIPT" || fail "official initial service stop"
grep -q 'set_allocation primaries' "$SCRIPT" || fail "allocation is reduced before Indexer stop"
grep -q 'set_allocation all' "$SCRIPT" || fail "allocation is restored after Indexer start"
grep -q 'export_indexer_security' "$SCRIPT" || fail "preflight security export"
grep -q 'create_backup' "$SCRIPT" || fail "preflight configuration backup"
grep -q 'create_index_snapshot' "$SCRIPT" || fail "preflight Indexer snapshot"
grep -q 'sha256sum -c' "$SCRIPT" || fail "backup checksum verification"
grep -q 'check_xml_marker' "$SCRIPT" || fail "semantic XML checks"
grep -q 'REGRESSION_ALLOWED_FAILURES' "$SCRIPT" || fail "explicit regression baseline"
grep -q 'compare_regression_results' "$SCRIPT" || fail "pre/post regression comparison"
grep -q 'check_loaded_snapshot_path' "$SCRIPT" || fail "post-reboot snapshot path check"
grep -q 'check_post_reboot_indexer_health' "$SCRIPT" || fail "post-reboot shard health check"
grep -q 'check_required_wazuh_daemons' "$SCRIPT" || fail "required daemon check"
grep -q "trap restore_policy_rcd EXIT" "$SCRIPT" || fail "policy guard EXIT cleanup"
grep -q 'apt_install_exact wazuh-indexer "$indexer_pkg" confold' "$SCRIPT" \
  || fail "Indexer conffile preservation"
grep -q 'apt_install_exact wazuh-dashboard "$dashboard_pkg" confold' "$SCRIPT" \
  || fail "Dashboard conffile preservation"
grep -q 'filebeat_target=' "$SCRIPT" || fail "exact Filebeat verification"
grep -q 'PROFILE="generic"' "$SCRIPT" || fail "generic default profile"
grep -q 'PROFILE="homelab"' "$ROOT/wazuh-aio-upgrade-homelab.conf.example" \
  || fail "homelab profile example"
grep -q 'Dashboard HTTP endpoint did not become ready' "$SCRIPT" \
  || fail "bounded Dashboard readiness wait"
grep -q 'generic profile allows an empty deployment' "$SCRIPT" \
  || fail "generic profile empty-agent handling"
if grep -q 'apt-get install -y --only-upgrade' "$SCRIPT"; then
  fail "local package install can fall back to repository download"
fi
grep -q 'apt-get install -y --no-download' "$SCRIPT" \
  || fail "local package install is not download-guarded"
if grep -q 'HOST_BACKUP_ACK_FILE' "$SCRIPT"; then
  fail "obsolete manual backup marker is still present"
fi
if grep -q 'head -n1' "$SCRIPT"; then
  fail "pipefail-unsafe first-line selection is still present"
fi
pass "critical safety gates are present"

bash -c '
  source "$1"
  PROFILE=generic
  configure_profile
  [[ " ${CORE_SERVICES[*]} " != *" rsyslog "* ]]
' _ "$SCRIPT" || fail "generic profile isolation"
pass "generic profile isolation"

bash -c '
  source "$1"
  PROFILE=homelab
  configure_profile
  [[ " ${CORE_SERVICES[*]} " == *" rsyslog "* ]]
  [[ " ${STRICT_CONFIG_PATHS[*]} " == *" /etc/rsyslog.conf "* ]]
' _ "$SCRIPT" || fail "homelab profile activation"
pass "homelab profile activation"

bash -c '
  source "$1"
  regression_failure_is_allowed "ugreen/web-login-success"
  if regression_failure_is_allowed "unifi/wan-local-high-rate"; then
    exit 1
  fi
' _ "$SCRIPT" || fail "regression allowlist behavior"
pass "regression allowlist behavior"

snapshot_name=$(bash -c '
  source "$1"
  make_snapshot_name
' _ "$SCRIPT")
[[ "$snapshot_name" =~ ^[a-z0-9._-]+$ ]] || fail "snapshot name is not OpenSearch-safe"
[[ "$snapshot_name" == wazuh-aio-pre-4-14-9-* ]] || fail "snapshot name prefix"
pass "snapshot name safety"

set_plus_e_count=$(grep -c '^  set +e$' "$SCRIPT" || true)
[[ "$set_plus_e_count" == "1" ]] || fail "unexpected set +e usage can bypass ERR handling"
pass "expected non-zero handling"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$SCRIPT" "$0"
  pass "shellcheck"
else
  echo "SKIP: shellcheck is not installed"
fi

echo "All Wazuh AIO upgrade helper smoke tests passed"
