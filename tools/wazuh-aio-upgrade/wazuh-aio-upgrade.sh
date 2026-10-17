#!/usr/bin/env bash

# Guard chains use pass/fail helpers; fail exits and pass returns success.
# shellcheck disable=SC2015

set -Eeuo pipefail
umask 077

SCRIPT_VERSION="0.2.8"
DEFAULT_CONFIG="/etc/wazuh-aio-upgrade.conf"
PROFILE="generic"
SOURCE_VERSION="4.14.8"
TARGET_VERSION="4.14.9"
MIN_FREE_GIB="10"
INDEXER_URL="https://127.0.0.1:9200"
INDEXER_CA="/etc/wazuh-indexer/certs/root-ca.pem"
INDEXER_ADMIN_CERT="/etc/wazuh-indexer/certs/admin.pem"
INDEXER_ADMIN_KEY="/etc/wazuh-indexer/certs/admin-key.pem"
INDEXER_INSECURE="false"
SNAPSHOT_REPOSITORY=""
SNAPSHOT_PATH="/var/backups/wazuh-indexer-snapshots"
ALLOW_NO_INDEX_SNAPSHOT="false"
DASHBOARD_EXPORT_ACK_FILE="/root/wazuh-dashboard-export.ndjson"
ALLOW_NO_DASHBOARD_EXPORT="false"
MAX_ACK_AGE_HOURS="24"
REPO_CHECKOUT="/opt/wazuh-homelab-security"
BACKUP_ROOT="/var/backups"
STATE_ROOT="/var/lib/wazuh-aio-upgrade"
LOG_ROOT="/var/log/wazuh-aio-upgrade"
DASHBOARD_URL="https://127.0.0.1"
INGEST_LOOKBACK="24h"
EXPECTED_AGENT_NAMES=""
REGRESSION_TIMEOUT_SECONDS="300"
REGRESSION_ALLOWED_FAILURES="ugreen/storage-repeated-io ugreen/web-bruteforce ugreen/web-login-success ugreen/web-success-after-failure"
SERVICE_WAIT_SECONDS="300"
DASHBOARD_WAIT_SECONDS="300"
CONFIG_FILE="$DEFAULT_CONFIG"
REFRESH_APT="false"
CONFIRM_UPGRADE="false"
MODE=""
RUN_ID=""
RUN_DIR=""
LOG_FILE=""
LAST_CHECKPOINT="not-started"
PREFLIGHT_FAILURES=0
PREFLIGHT_WARNINGS=0
POLICY_RCD_CREATED="false"
POLICY_RCD_BACKUP=""

readonly CENTRAL_PACKAGES=(wazuh-indexer wazuh-manager wazuh-dashboard)
CORE_SERVICES=(wazuh-indexer wazuh-manager filebeat wazuh-dashboard)
PRESERVE_PATHS=(
  /var/ossec/etc
  /etc/wazuh-indexer
  /etc/filebeat
  /etc/wazuh-dashboard
  /etc/logrotate.d
  /usr/share/filebeat/module/wazuh
)
STRICT_CONFIG_PATHS=(
  /var/ossec/etc/ossec.conf
  /var/ossec/etc/local_internal_options.conf
  /var/ossec/etc/decoders
  /var/ossec/etc/rules
)

usage() {
  cat <<'EOF'
Usage:
  sudo ./wazuh-aio-upgrade.sh preflight [options]
  sudo ./wazuh-aio-upgrade.sh post-reboot [options]
  sudo ./wazuh-aio-upgrade.sh apply --confirm-upgrade [options]
  sudo ./wazuh-aio-upgrade.sh verify [options]

Options:
  --config PATH          Configuration file (default: /etc/wazuh-aio-upgrade.conf)
  --source VERSION       Required installed version (default: 4.14.8)
  --target VERSION       Upgrade target (default: 4.14.9)
  --refresh-apt          Run apt-get update before checking package candidates
  --run-id ID            Reuse a specific run identifier for verify
  --confirm-upgrade      Required acknowledgement for apply
  -h, --help             Show this help

This script supports a package-based, single-node Ubuntu 24.04 Wazuh AIO only.
The generic profile checks standard Wazuh components. Installation-specific
rsyslog, telemetry and regression checks require PROFILE="homelab" in config.
It never performs an automatic Wazuh Indexer rollback.
EOF
}

parse_args() {
  [[ $# -ge 1 ]] || { usage; exit 2; }
  MODE="$1"
  shift
  case "$MODE" in
    preflight|post-reboot|apply|verify) ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown mode: $MODE" >&2; usage; exit 2 ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config) CONFIG_FILE="$2"; shift 2 ;;
      --source) SOURCE_VERSION="$2"; shift 2 ;;
      --target) TARGET_VERSION="$2"; shift 2 ;;
      --refresh-apt) REFRESH_APT="true"; shift ;;
      --run-id) RUN_ID="$2"; shift 2 ;;
      --confirm-upgrade) CONFIRM_UPGRADE="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
  done
}

preload_config_path() {
  local previous=""
  for argument in "$@"; do
    if [[ "$previous" == "--config" ]]; then
      CONFIG_FILE="$argument"
      return
    fi
    previous="$argument"
  done
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    [[ ! -L "$CONFIG_FILE" ]] || { echo "Configuration must not be a symlink: $CONFIG_FILE" >&2; exit 2; }
    [[ "$(stat -c %u "$CONFIG_FILE")" == "0" ]] \
      || { echo "Configuration must be owned by root: $CONFIG_FILE" >&2; exit 2; }
    if find "$CONFIG_FILE" -prune -perm /022 | grep -q .; then
      echo "Configuration must not be group/world writable: $CONFIG_FILE" >&2
      exit 2
    fi
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  elif [[ "$CONFIG_FILE" != "$DEFAULT_CONFIG" ]]; then
    echo "Configuration file not found: $CONFIG_FILE" >&2
    exit 2
  fi
}

configure_profile() {
  case "$PROFILE" in
    generic) ;;
    homelab)
      CORE_SERVICES+=(rsyslog)
      PRESERVE_PATHS+=(/etc/rsyslog.conf /etc/rsyslog.d)
      STRICT_CONFIG_PATHS+=(/etc/rsyslog.conf /etc/rsyslog.d)
      ;;
    *) echo "Unsupported profile: $PROFILE (expected generic or homelab)" >&2; exit 2 ;;
  esac
  [[ "$SERVICE_WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]] \
    || { echo "SERVICE_WAIT_SECONDS must be a positive integer" >&2; exit 2; }
  [[ "$DASHBOARD_WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]] \
    || { echo "DASHBOARD_WAIT_SECONDS must be a positive integer" >&2; exit 2; }
}

initialize_run() {
  [[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
  if [[ -z "$RUN_ID" ]]; then
    RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-${MODE}-${TARGET_VERSION}"
  fi
  [[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid run ID." >&2; exit 2; }
  RUN_DIR="$STATE_ROOT/$RUN_ID"
  LOG_FILE="$LOG_ROOT/$RUN_ID.log"
  install -d -m 0700 "$RUN_DIR"
  if [[ -e "$BACKUP_ROOT" ]]; then
    [[ -d "$BACKUP_ROOT" && ! -L "$BACKUP_ROOT" ]] \
      || { echo "Backup root must be a real directory: $BACKUP_ROOT" >&2; exit 2; }
  else
    install -d -m 0700 "$BACKUP_ROOT"
  fi
  install -d -m 0750 "$LOG_ROOT"
  touch "$LOG_FILE"
  chmod 0600 "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
  printf '\n[%s] Wazuh AIO upgrade helper %s: %s\n' "$(date -Is)" "$SCRIPT_VERSION" "$MODE"
  printf 'Run ID: %s\nLog: %s\n' "$RUN_ID" "$LOG_FILE"
}

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
pass() { log "PASS: $*"; }
warn() { log "WARN: $*"; PREFLIGHT_WARNINGS=$((PREFLIGHT_WARNINGS + 1)); }
fail() { log "FAIL: $*"; PREFLIGHT_FAILURES=$((PREFLIGHT_FAILURES + 1)); }
die() { log "ERROR: $*"; exit 1; }

checkpoint() {
  LAST_CHECKPOINT="$1"
  printf '%s\n' "$LAST_CHECKPOINT" > "$RUN_DIR/last-checkpoint"
  printf '%s %s\n' "$(date -Is)" "$LAST_CHECKPOINT" >> "$RUN_DIR/checkpoints.log"
  log "CHECKPOINT: $LAST_CHECKPOINT"
}

on_error() {
  local rc=$?
  set +e
  restore_policy_rcd
  log "STOPPED at checkpoint '$LAST_CHECKPOINT' (exit $rc)."
  log "No automatic Indexer rollback was attempted."
  log "Read the recovery section in README.md before taking further action."
  exit "$rc"
}

trap on_error ERR
trap restore_policy_rcd EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

bool_true() { [[ "${1,,}" == "true" ]]; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
service_exists() {
  systemctl list-unit-files "$1.service" --no-legend 2>/dev/null \
    | awk -v unit="$1.service" '$1 == unit {found=1} END {exit found ? 0 : 1}'
}
package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null \
    | awk '$0 == "install ok installed" {found=1} END {exit found ? 0 : 1}'
}
package_version() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true; }
base_version() { sed -E 's/^v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/' <<<"$1"; }

target_package_version() {
  local package="$1"
  apt-cache madison "$package" 2>/dev/null \
    | awk -v target="$TARGET_VERSION" '
        $3 ~ ("^" target "-") && found == "" {found=$3}
        END {if (found != "") print found}
      '
}

file_age_seconds() {
  local path="$1" now mtime
  now=$(date +%s)
  mtime=$(stat -c %Y "$path")
  echo $((now - mtime))
}

check_commands() {
  local command missing=()
  local commands=(apt-cache apt-get cmp curl diff diff3 dpkg-deb dpkg-query filebeat
    findmnt python3 runuser systemctl tar timeout)
  [[ "$PROFILE" == "homelab" ]] && commands+=(rsyslogd ss)
  for command in "${commands[@]}"; do
    command_exists "$command" || missing+=("$command")
  done
  if ((${#missing[@]})); then
    fail "Missing required commands: ${missing[*]}"
    return 1
  fi
  pass "Required host commands are available"
}

refresh_apt_metadata() {
  local active_source commented_source temporary_source
  log "Refreshing normal APT metadata"
  apt-get update
  active_source=$(grep -hE '^[[:space:]]*deb .*packages\.wazuh\.com/4\.x/apt' \
    /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null \
    | awk 'NR == 1 {first=$0} END {if (first != "") print first}' || true)
  [[ -n "$active_source" ]] && return 0

  commented_source=$(grep -hE '^[[:space:]]*#[[:space:]]*deb .*packages\.wazuh\.com/4\.x/apt' \
    /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null \
    | awk 'NR == 1 {first=$0} END {if (first != "") print first}' || true)
  [[ -n "$commented_source" ]] \
    || die "No official Wazuh 4.x APT source was found, active or commented"
  temporary_source="$RUN_DIR/wazuh-temporary.list"
  sed -E 's/^[[:space:]]*#[[:space:]]*//' <<<"$commented_source" > "$temporary_source"
  chmod 0600 "$temporary_source"
  log "Refreshing Wazuh metadata through an ephemeral source list"
  apt-get update \
    -o "Dir::Etc::sourcelist=$temporary_source" \
    -o 'Dir::Etc::sourceparts=-' \
    -o 'APT::Get::List-Cleanup=0'
}

indexer_curl() {
  local args=(--silent --show-error --fail-with-body --connect-timeout 10 --max-time 120)
  if bool_true "$INDEXER_INSECURE"; then
    args+=(-k)
  else
    [[ -r "$INDEXER_CA" ]] || die "Indexer CA not readable: $INDEXER_CA"
    args+=(--cacert "$INDEXER_CA")
  fi
  [[ -r "$INDEXER_ADMIN_CERT" ]] || die "Indexer admin certificate not readable: $INDEXER_ADMIN_CERT"
  [[ -r "$INDEXER_ADMIN_KEY" ]] || die "Indexer admin key not readable: $INDEXER_ADMIN_KEY"
  args+=(--cert "$INDEXER_ADMIN_CERT" --key "$INDEXER_ADMIN_KEY")
  curl "${args[@]}" "$@"
}

json_field() {
  local expression="$1"
  python3 -c "import json,sys; d=json.load(sys.stdin); print($expression)"
}

check_os_and_layout() {
  [[ -r /etc/os-release ]] || { fail "/etc/os-release is missing"; return; }
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]] \
    && pass "Ubuntu 24.04 detected" \
    || fail "Supported OS is Ubuntu 24.04; detected ${PRETTY_NAME:-unknown}"

  local missing=()
  for package in "${CENTRAL_PACKAGES[@]}" filebeat; do
    package_installed "$package" || missing+=("$package")
  done
  ((${#missing[@]} == 0)) \
    && pass "All AIO packages are installed" \
    || fail "Missing AIO packages: ${missing[*]}"

  local nodes
  nodes=$(indexer_curl "$INDEXER_URL/_cluster/health" | json_field "d.get('number_of_nodes', 0)") || {
    fail "Cannot query Indexer cluster health"
    return
  }
  [[ "$nodes" == "1" ]] && pass "Single-node Indexer confirmed" || fail "Expected one Indexer node, found $nodes"
}

check_reboot_state() {
  if [[ -e /var/run/reboot-required ]]; then
    fail "System reboot is required; reboot and rerun preflight"
    if [[ -r /var/run/reboot-required.pkgs ]]; then
      log "Packages requesting reboot:"
      sed 's/^/  - /' /var/run/reboot-required.pkgs
    fi
  else
    pass "No pending reboot marker"
  fi
}

check_versions_and_candidates() {
  local package installed candidate filebeat_origin
  for package in "${CENTRAL_PACKAGES[@]}"; do
    installed=$(package_version "$package")
    [[ "$(base_version "$installed")" == "$SOURCE_VERSION" ]] \
      && pass "$package installed version is $installed" \
      || fail "$package is $installed; expected source $SOURCE_VERSION"
    candidate=$(target_package_version "$package")
    [[ -n "$candidate" ]] \
      && pass "$package target is available: $candidate" \
      || fail "$package target $TARGET_VERSION is unavailable in APT metadata"
  done
  candidate=$(apt-cache policy filebeat 2>/dev/null | awk '/Candidate:/ {print $2}')
  if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
    filebeat_origin=$(apt-cache madison filebeat 2>/dev/null \
      | awk -v version="$candidate" '
          $3 == version && /packages\.wazuh\.com/ && found == "" {found=$0}
          END {if (found != "") print found}
        ')
    [[ -n "$filebeat_origin" ]] \
      && pass "Filebeat candidate is available from the Wazuh repository: $candidate" \
      || fail "Filebeat candidate $candidate is not provided by packages.wazuh.com"
  else
    fail "Filebeat has no APT candidate"
  fi
}

check_services() {
  local service
  for service in "${CORE_SERVICES[@]}"; do
    if ! service_exists "$service"; then
      fail "Service unit is missing: $service"
    elif systemctl is-active --quiet "$service"; then
      pass "$service is active"
    else
      fail "$service is not active"
    fi
  done
}

check_disk() {
  local path available_kb required_kb
  required_kb=$((MIN_FREE_GIB * 1024 * 1024))
  for path in / /var /var/lib/wazuh-indexer "$BACKUP_ROOT"; do
    [[ -e "$path" ]] || continue
    available_kb=$(df -Pk "$path" | awk 'NR==2 {print $4}')
    if ((available_kb >= required_kb)); then
      pass "$path has at least ${MIN_FREE_GIB} GiB free"
    else
      fail "$path has less than ${MIN_FREE_GIB} GiB free"
    fi
  done
  log "Filesystem: $(findmnt -n -o SOURCE,FSTYPE,OPTIONS / || true)"
  command_exists lvs && log "LVM detected; review lvs output for host snapshot capability" || true
  command_exists zfs && log "ZFS tooling detected; review dataset snapshot capability" || true
  [[ "$(findmnt -n -o FSTYPE / 2>/dev/null)" == "btrfs" ]] && log "Btrfs root detected" || true
}

run_config_checks() {
  local check
  for check in wazuh-analysisd wazuh-modulesd wazuh-logcollector; do
    if [[ -x "/var/ossec/bin/$check" ]]; then
      if "/var/ossec/bin/$check" -t >/dev/null; then
        pass "$check configuration test"
      else
        fail "$check configuration test"
      fi
    fi
  done
  if [[ "$PROFILE" == "homelab" ]]; then
    rsyslogd -N1 >/dev/null 2>&1 && pass "rsyslog configuration test" || fail "rsyslog configuration test"
  fi
  filebeat test config -e >/dev/null 2>&1 && pass "Filebeat configuration test" || fail "Filebeat configuration test"
  filebeat test output -e >/dev/null 2>&1 && pass "Filebeat output test" || fail "Filebeat output test"
}

check_indexer_health() {
  local phase="${1:-current}" health status nodes unassigned relocating initializing
  health=$(indexer_curl "$INDEXER_URL/_cluster/health") || { fail "Indexer health request failed"; return; }
  status=$(json_field "d.get('status', 'unknown')" <<<"$health")
  nodes=$(json_field "d.get('number_of_nodes', 0)" <<<"$health")
  unassigned=$(json_field "d.get('unassigned_shards', -1)" <<<"$health")
  relocating=$(json_field "d.get('relocating_shards', -1)" <<<"$health")
  initializing=$(json_field "d.get('initializing_shards', -1)" <<<"$health")
  [[ "$status" == "green" && "$nodes" == "1" && "$unassigned" == "0" \
    && "$relocating" == "0" && "$initializing" == "0" ]] \
    && pass "Indexer is green with no pending shard allocation" \
    || fail "Indexer health is status=$status nodes=$nodes unassigned=$unassigned relocating=$relocating initializing=$initializing"
  if /usr/share/wazuh-indexer/bin/opensearch-plugin list \
    > "$RUN_DIR/indexer-plugins.$phase.txt"; then
    pass "Indexer plugin inventory captured"
  else
    fail "Cannot list Indexer plugins"
  fi
  if runuser -u wazuh-dashboard -- \
    /usr/share/wazuh-dashboard/bin/opensearch-dashboards-plugin list \
    > "$RUN_DIR/dashboard-plugins.$phase.txt"; then
    pass "Dashboard plugin inventory captured"
  else
    fail "Cannot list Dashboard plugins"
  fi
  if [[ "$phase" == "after" ]] && grep -qi outdated \
    "$RUN_DIR/indexer-plugins.$phase.txt" "$RUN_DIR/dashboard-plugins.$phase.txt"; then
    fail "At least one Wazuh plugin is marked outdated"
  fi
}

check_snapshot_and_exports() {
  local repositories maximum_age_seconds
  maximum_age_seconds=$((MAX_ACK_AGE_HOURS * 3600))
  repositories=$(indexer_curl "$INDEXER_URL/_snapshot/_all") || repositories="{}"
  if ! python3 -c '
import json, sys
wanted = sys.argv[1]
data = json.load(sys.stdin)
names = sorted(data)
print("Configured snapshot repositories: " + (", ".join(names) if names else "none"))
if wanted and wanted not in data:
    raise SystemExit(1)
' "$SNAPSHOT_REPOSITORY" <<<"$repositories"; then
    fail "Configured snapshot repository is not available: $SNAPSHOT_REPOSITORY"
  fi
  if [[ -n "$SNAPSHOT_REPOSITORY" ]]; then
    indexer_curl "$INDEXER_URL/_snapshot/$SNAPSHOT_REPOSITORY/_verify" -X POST >/dev/null \
      && pass "Snapshot repository verified: $SNAPSHOT_REPOSITORY" \
      || fail "Snapshot repository verification failed: $SNAPSHOT_REPOSITORY"
  elif bool_true "$ALLOW_NO_INDEX_SNAPSHOT"; then
    warn "No Indexer snapshot repository configured; explicit override is enabled"
  else
    fail "Set SNAPSHOT_REPOSITORY or explicitly allow proceeding without an Indexer snapshot"
  fi

  if [[ -s "$DASHBOARD_EXPORT_ACK_FILE" ]]; then
    if (( $(file_age_seconds "$DASHBOARD_EXPORT_ACK_FILE") <= maximum_age_seconds )); then
      pass "Dashboard saved-object export is recent"
    else
      fail "Dashboard saved-object export is older than $MAX_ACK_AGE_HOURS hours"
    fi
  elif bool_true "$ALLOW_NO_DASHBOARD_EXPORT"; then
    warn "Dashboard export is missing; explicit override is enabled"
  else
    fail "Export Dashboard saved objects to $DASHBOARD_EXPORT_ACK_FILE"
  fi

}

check_ingest_contracts() {
  local path
  for path in /var/log/unifi.log /var/log/ugreen.log; do
    if [[ -r "$path" ]]; then
      pass "Ingest file is readable: $path"
      (( $(file_age_seconds "$path") <= 86400 )) || warn "$path has not changed in 24 hours"
    else
      fail "Required ingest file is not readable: $path"
    fi
  done
  [[ -r /var/log/synology.log ]] && pass "Synology ingest file is readable" || warn "Synology ingest file is absent"

  if ss -lunp 2>/dev/null | grep -E '(:|\])514[[:space:]]' > "$RUN_DIR/udp-514.before.txt"; then
    grep -qi rsyslog "$RUN_DIR/udp-514.before.txt" \
      && pass "rsyslog owns UDP/514" \
      || fail "UDP/514 is not owned by rsyslog"
    grep -qi wazuh "$RUN_DIR/udp-514.before.txt" && fail "Wazuh must not bind UDP/514" || true
  else
    fail "No UDP/514 listener detected"
  fi

  check_xml_marker "UniFi decoder" '<decoder name="unifi-ucg-cef"' /var/ossec/etc/decoders
  check_xml_marker "Home Assistant decoder" '<decoder name="homeassistant-http-ban"' /var/ossec/etc/decoders
  check_xml_marker "UGREEN decoder" '<decoder name="ugreen-web-login-success"' /var/ossec/etc/decoders
  check_xml_marker "Synology decoder" '<decoder name="synology-dsm-auth"' /var/ossec/etc/decoders
  check_xml_marker "UniFi rules" '<rule id="100110"' /var/ossec/etc/rules
  check_xml_marker "Home Assistant rules" '<rule id="100400"' /var/ossec/etc/rules
  check_xml_marker "SafeLine rules" '<rule id="100500"' /var/ossec/etc/rules
  check_xml_marker "UGREEN rules" '<rule id="100600"' /var/ossec/etc/rules
  grep -Rqs '<location>/var/log/unifi.log</location>' /var/ossec/etc/ossec.conf \
    && pass "UniFi localfile is configured" || fail "UniFi localfile is not configured"
  grep -Rqs '<location>/var/log/ugreen.log</location>' /var/ossec/etc/ossec.conf \
    && pass "UGREEN localfile is configured" || fail "UGREEN localfile is not configured"
}

check_xml_marker() {
  local label="$1" marker="$2" directory="$3"
  if grep -RqsF -- "$marker" "$directory"; then
    pass "$label marker is present"
  else
    fail "$label marker is missing under $directory"
  fi
}

check_agents() {
  local phase="${1:-current}" listing connected name output
  output="$RUN_DIR/agents.$phase.txt"
  listing=$(/var/ossec/bin/agent_control -lc 2>/dev/null || true)
  printf '%s\n' "$listing" > "$output"
  connected=$(grep -ciE 'active|connected' <<<"$listing" || true)
  if ((connected > 0)); then
    pass "$connected connected/active agent rows detected"
  elif [[ "$PROFILE" == "homelab" ]]; then
    fail "No connected agents detected"
  else
    warn "No connected agents detected; generic profile allows an empty deployment"
  fi
  for name in $EXPECTED_AGENT_NAMES; do
    grep -Fqi "$name" <<<"$listing" && pass "Expected agent present: $name" || fail "Expected agent missing: $name"
  done
}

compare_agent_counts() {
  local before="$RUN_DIR/agents.before.txt" after="$RUN_DIR/agents.after.txt"
  local before_count after_count
  [[ -f "$before" && -f "$after" ]] || { warn "Cannot compare pre/post agent counts"; return; }
  before_count=$(grep -ciE 'active|connected' "$before" || true)
  after_count=$(grep -ciE 'active|connected' "$after" || true)
  if ((after_count >= before_count)); then
    pass "Connected agent count did not decrease ($before_count -> $after_count)"
  else
    fail "Connected agent count decreased ($before_count -> $after_count)"
  fi
}

regression_failure_is_allowed() {
  local scenario="$1" allowed
  for allowed in $REGRESSION_ALLOWED_FAILURES; do
    [[ "$scenario" == "$allowed" ]] && return 0
  done
  return 1
}

run_repository_regression() {
  local phase="${1:-current}" output json_report rc scenario
  local unexpected=()
  local allowed_failures=()
  local xpasses=()
  output="$RUN_DIR/regression.$phase.txt"
  json_report="$RUN_DIR/regression.$phase.json"
  if [[ -x "$REPO_CHECKOUT/tools/regression/run_samples.py" || -f "$REPO_CHECKOUT/tools/regression/run_samples.py" ]]; then
    log "Running repository regression suite (timeout ${REGRESSION_TIMEOUT_SECONDS}s)"
    if timeout --signal=TERM --kill-after=15s "${REGRESSION_TIMEOUT_SECONDS}s" \
      python3 "$REPO_CHECKOUT/tools/regression/run_samples.py" \
      --json-report "$json_report" > "$output" 2>&1; then
      rc=0
    else
      rc=$?
    fi
    if ((rc == 124 || rc == 137)); then
      fail "Repository regression suite timed out; see $output"
      return
    fi
    if ((rc > 1)); then
      fail "Repository regression runner exited with status $rc; see $output"
      return
    fi
    [[ -s "$json_report" ]] || { fail "Repository regression JSON report is missing"; return; }
    while IFS='|' read -r scenario status; do
      case "$status" in
        FAIL)
          if regression_failure_is_allowed "$scenario"; then
            allowed_failures+=("$scenario")
          else
            unexpected+=("$scenario")
          fi
          ;;
        XPASS) xpasses+=("$scenario") ;;
      esac
    done < <(python3 - "$json_report" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    for result in json.load(stream):
        print(f"{result['scenario']}|{result['status']}")
PY
)
    for scenario in "${allowed_failures[@]}"; do
      warn "Accepted pre-existing regression failure: $scenario"
    done
    if ((${#xpasses[@]})); then
      fail "Repository regression has XPASS scenarios: ${xpasses[*]}"
    fi
    if ((${#unexpected[@]})); then
      fail "Repository regression has unexpected failures: ${unexpected[*]}"
    elif ((${#xpasses[@]} == 0)); then
      pass "Repository regression matches the accepted production baseline"
    fi
  else
    fail "Regression checkout not found at $REPO_CHECKOUT"
  fi
}

compare_regression_results() {
  local before="$RUN_DIR/regression.before.json" after="$RUN_DIR/regression.after.json"
  [[ -s "$before" && -s "$after" ]] \
    || { fail "Cannot compare pre/post regression reports"; return; }
  if cmp -s "$before" "$after"; then
    pass "Post-upgrade regression result exactly matches pre-upgrade baseline"
  else
    diff -u "$before" "$after" > "$RUN_DIR/regression.before-after.diff" || true
    fail "Post-upgrade regression changed; see $RUN_DIR/regression.before-after.diff"
  fi
}

write_strict_manifest() {
  local destination="$1" path
  : > "$destination"
  for path in "${STRICT_CONFIG_PATHS[@]}"; do
    [[ -e "$path" ]] || continue
    if [[ -d "$path" ]]; then
      find "$path" -xdev -type f -print0
    else
      printf '%s\0' "$path"
    fi
  done | sort -z | xargs -0 -r sha256sum >> "$destination"
}

preflight() {
  checkpoint "preflight-started"
  check_commands || return 1
  if bool_true "$REFRESH_APT"; then
    refresh_apt_metadata
  fi
  check_os_and_layout
  check_reboot_state
  check_versions_and_candidates
  check_services
  check_disk
  run_config_checks
  check_indexer_health before
  check_snapshot_and_exports
  [[ "$PROFILE" != "homelab" ]] || check_ingest_contracts
  check_agents before
  [[ "$PROFILE" != "homelab" ]] || run_repository_regression before
  write_strict_manifest "$RUN_DIR/strict-config.before.sha256"
  export_indexer_security || true
  create_backup
  if ((PREFLIGHT_FAILURES == 0)); then
    create_index_snapshot
    [[ ! -f "$RUN_DIR/index-snapshot" ]] || record_snapshot_receipt
  else
    warn "Indexer snapshot skipped because preflight has failures"
  fi
  checkpoint "preflight-finished"
  log "Preflight result: failures=$PREFLIGHT_FAILURES warnings=$PREFLIGHT_WARNINGS"
  ((PREFLIGHT_FAILURES == 0)) || return 1
}

download_deb() {
  local package="$1" version="$2" destination="$3" before after
  install -d -m 0700 "$destination"
  before=$(find "$destination" -maxdepth 1 -type f -name '*.deb' -printf '%f\n' | sort)
  (cd "$destination" && apt-get download "$package=$version" >/dev/null)
  after=$(comm -13 <(printf '%s\n' "$before") \
    <(find "$destination" -maxdepth 1 -type f -name '*.deb' -printf '%f\n' | sort) \
    | awk 'NR == 1 {first=$0} END {if (first != "") print first}')
  if [[ -n "$after" ]]; then
    printf '%s/%s\n' "$destination" "$after"
  else
    find "$destination" -maxdepth 1 -type f -name "${package}_*.deb" -print -quit
  fi
}

prepare_merge_candidate() {
  local package="$1" config_path="$2" target_pkg="$3" output="$4"
  local current_pkg old_deb new_deb old_root new_root relative
  current_pkg=$(package_version "$package")
  relative=".${config_path}"
  old_root="$RUN_DIR/package-baselines/${package}-old"
  new_root="$RUN_DIR/package-baselines/${package}-new"
  old_deb=$(download_deb "$package" "$current_pkg" "$RUN_DIR/debs") \
    || die "Cannot download installed $package package $current_pkg"
  new_deb=$(download_deb "$package" "$target_pkg" "$RUN_DIR/debs") \
    || die "Cannot download target $package package $target_pkg"
  mkdir -p "$old_root" "$new_root"
  dpkg-deb -x "$old_deb" "$old_root"
  dpkg-deb -x "$new_deb" "$new_root"
  [[ -f "$old_root/$relative" && -f "$new_root/$relative" && -f "$config_path" ]] \
    || die "Cannot prepare three-way merge for $config_path"
  local rc
  if diff3 -m "$config_path" "$old_root/$relative" "$new_root/$relative" > "$output"; then
    rc=0
  else
    rc=$?
  fi
  ((rc == 0)) || die "Configuration merge conflict for $config_path; resolve before apply"
  chmod --reference="$config_path" "$output"
  chown --reference="$config_path" "$output"
  pass "Prepared conflict-free merge candidate for $config_path"
}

prepare_artifacts() {
  local package version
  checkpoint "artifacts-started"
  install -d -m 0700 "$RUN_DIR/artifacts" "$RUN_DIR/merged-config"
  for package in "${CENTRAL_PACKAGES[@]}"; do
    version=$(target_package_version "$package")
    [[ -n "$version" ]] || die "Missing target package: $package"
    printf '%s=%s\n' "$package" "$version" >> "$RUN_DIR/package-targets"
    download_deb "$package" "$version" "$RUN_DIR/debs" >/dev/null
  done
  version=$(apt-cache policy filebeat | awk '/Candidate:/ {print $2}')
  printf 'filebeat=%s\n' "$version" >> "$RUN_DIR/package-targets"
  download_deb filebeat "$version" "$RUN_DIR/debs" >/dev/null

  prepare_merge_candidate wazuh-indexer /etc/wazuh-indexer/jvm.options \
    "$(target_package_version wazuh-indexer)" "$RUN_DIR/merged-config/jvm.options"
  prepare_merge_candidate wazuh-dashboard /etc/wazuh-dashboard/opensearch_dashboards.yml \
    "$(target_package_version wazuh-dashboard)" "$RUN_DIR/merged-config/opensearch_dashboards.yml"

  curl --fail --silent --show-error --location \
    "https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.5.tar.gz" \
    -o "$RUN_DIR/artifacts/wazuh-filebeat-0.5.tar.gz"
  tar -tzf "$RUN_DIR/artifacts/wazuh-filebeat-0.5.tar.gz" >/dev/null
  curl --fail --silent --show-error --location \
    "https://raw.githubusercontent.com/wazuh/wazuh/v${TARGET_VERSION}/extensions/elasticsearch/7.x/wazuh-template.json" \
    -o "$RUN_DIR/artifacts/wazuh-template.json"
  python3 -m json.tool "$RUN_DIR/artifacts/wazuh-template.json" >/dev/null
  checkpoint "artifacts-ready"
}

export_indexer_security() {
  checkpoint "indexer-security-export-started"
  if /usr/share/wazuh-indexer/bin/indexer-security-init.sh \
    --options "-backup /etc/wazuh-indexer/opensearch-security -icl -nhnv"; then
    pass "Indexer security configuration exported"
    checkpoint "indexer-security-export-complete"
  else
    fail "Indexer security configuration export failed"
    return 1
  fi
}

create_backup() {
  local timestamp backup_dir archive path package version
  local relative_paths=()
  local mandatory_paths=(
    /var/ossec/etc/ossec.conf
    /var/ossec/etc/local_internal_options.conf
    /var/ossec/etc/rules
    /var/ossec/etc/decoders
    /etc/filebeat/filebeat.yml
    /etc/wazuh-indexer
    /etc/wazuh-dashboard
  )
  local verify_paths=(
    var/ossec/etc/ossec.conf
    var/ossec/etc/local_internal_options.conf
    etc/filebeat/filebeat.yml
    etc/wazuh-indexer
    etc/wazuh-dashboard
  )
  local package_inventory=(wazuh-indexer wazuh-manager wazuh-dashboard filebeat)
  if [[ "$PROFILE" == "homelab" ]]; then
    mandatory_paths+=(/etc/rsyslog.conf /etc/rsyslog.d)
    verify_paths+=(etc/rsyslog.conf etc/rsyslog.d)
    package_inventory+=(rsyslog)
  fi
  timestamp=$(date +%Y%m%d-%H%M%S)
  backup_dir="$BACKUP_ROOT/wazuh-backup-${SOURCE_VERSION}-before-${TARGET_VERSION}-${timestamp}"
  checkpoint "backup-started"
  [[ ! -e "$backup_dir" ]] || die "Backup destination already exists: $backup_dir"
  install -d -m 0700 "$backup_dir"
  for path in "${mandatory_paths[@]}"; do
    [[ -e "$path" ]] || die "Mandatory backup source is missing: $path"
  done
  for path in "${PRESERVE_PATHS[@]}"; do
    if [[ -e "$path" ]]; then
      relative_paths+=("${path#/}")
    fi
  done
  if [[ -s "$DASHBOARD_EXPORT_ACK_FILE" ]]; then
    relative_paths+=("${DASHBOARD_EXPORT_ACK_FILE#/}")
  fi
  archive="$backup_dir/config-backup.tar.gz"
  tar --xattrs --acls --numeric-owner -C / -czf "$archive" "${relative_paths[@]}"
  tar -tzf "$archive" > "$backup_dir/archive-contents.txt"
  for path in "${verify_paths[@]}"; do
    grep -qE "^${path}(/|$)" "$backup_dir/archive-contents.txt" \
      || die "Verified archive is missing: /$path"
  done
  dpkg-query -W -f='${binary:Package}\t${Version}\n' \
    > "$backup_dir/all-installed-packages.tsv"
  dpkg-query -W -f='${binary:Package}\t${Version}\n' \
    "${package_inventory[@]}" \
    > "$backup_dir/wazuh-package-versions.tsv"
  : > "$backup_dir/target-package-candidates.tsv"
  for package in "${CENTRAL_PACKAGES[@]}"; do
    version=$(target_package_version "$package")
    printf '%s\t%s\n' "$package" "${version:-unavailable}" \
      >> "$backup_dir/target-package-candidates.tsv"
  done
  version=$(apt-cache policy filebeat 2>/dev/null | awk '/Candidate:/ {print $2}')
  printf 'filebeat\t%s\n' "${version:-unavailable}" \
    >> "$backup_dir/target-package-candidates.tsv"
  systemctl is-enabled "${CORE_SERVICES[@]/%/.service}" > "$backup_dir/service-enabled.txt" 2>&1 || true
  cp "$RUN_DIR/strict-config.before.sha256" "$backup_dir/"
  cp "$RUN_DIR/indexer-plugins.before.txt" "$backup_dir/"
  cp "$RUN_DIR/dashboard-plugins.before.txt" "$backup_dir/"
  [[ ! -f "$RUN_DIR/regression.before.txt" ]] || cp "$RUN_DIR/regression.before.txt" "$backup_dir/"
  [[ ! -f "$RUN_DIR/regression.before.json" ]] || cp "$RUN_DIR/regression.before.json" "$backup_dir/"
  cp "$LOG_FILE" "$backup_dir/preflight.log"
  (cd "$backup_dir" && find . -maxdepth 1 -type f ! -name SHA256SUMS \
    -printf '%P\0' | sort -z | xargs -0 -r sha256sum) \
    > "$backup_dir/SHA256SUMS"
  (cd "$backup_dir" && sha256sum -c SHA256SUMS >/dev/null)
  chmod -R go-rwx "$backup_dir"
  printf '%s\n' "$backup_dir" > "$RUN_DIR/backup-path"
  pass "Root-only configuration backup verified: $backup_dir"
  checkpoint "backup-verified"
}

make_snapshot_name() {
  printf 'wazuh-aio-pre-%s-%s\n' \
    "${TARGET_VERSION//./-}" "$(date -u +%Y%m%dt%H%M%Sz)"
}

create_index_snapshot() {
  if [[ -z "$SNAPSHOT_REPOSITORY" ]]; then
    bool_true "$ALLOW_NO_INDEX_SNAPSHOT" || die "Indexer snapshot repository is required"
    checkpoint "index-snapshot-explicitly-skipped"
    return
  fi
  local name response state failed
  name=$(make_snapshot_name)
  checkpoint "index-snapshot-started"
  log "Creating Indexer snapshot: $SNAPSHOT_REPOSITORY/$name"
  response=$(indexer_curl -X PUT \
    "$INDEXER_URL/_snapshot/$SNAPSHOT_REPOSITORY/$name?wait_for_completion=true" \
    -H 'Content-Type: application/json' \
    -d '{"indices":"*","include_global_state":true}')
  state=$(json_field "d.get('snapshot', {}).get('state', 'unknown')" <<<"$response")
  failed=$(json_field "d.get('snapshot', {}).get('shards', {}).get('failed', -1)" <<<"$response")
  [[ "$state" == "SUCCESS" && "$failed" == "0" ]] || die "Indexer snapshot failed: state=$state failed_shards=$failed"
  printf '%s/%s\n' "$SNAPSHOT_REPOSITORY" "$name" > "$RUN_DIR/index-snapshot"
  checkpoint "index-snapshot-complete"
}

record_snapshot_receipt() {
  local backup_dir
  backup_dir=$(<"$RUN_DIR/backup-path")
  cp "$RUN_DIR/index-snapshot" "$backup_dir/index-snapshot"
  (cd "$backup_dir" && sha256sum index-snapshot >> SHA256SUMS)
  (cd "$backup_dir" && sha256sum -c SHA256SUMS >/dev/null)
  chmod 0600 "$backup_dir/index-snapshot" "$backup_dir/SHA256SUMS"
  pass "Indexer snapshot receipt recorded in configuration backup"
}

install_policy_rcd() {
  if [[ -e /usr/sbin/policy-rc.d ]]; then
    POLICY_RCD_BACKUP="$RUN_DIR/policy-rc.d.original"
    cp -a /usr/sbin/policy-rc.d "$POLICY_RCD_BACKUP"
  fi
  cat > /usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
  chmod 0755 /usr/sbin/policy-rc.d
  POLICY_RCD_CREATED="true"
}

restore_policy_rcd() {
  bool_true "$POLICY_RCD_CREATED" || return 0
  if [[ -n "$POLICY_RCD_BACKUP" && -e "$POLICY_RCD_BACKUP" ]]; then
    cp -a "$POLICY_RCD_BACKUP" /usr/sbin/policy-rc.d
  else
    rm -f /usr/sbin/policy-rc.d
  fi
  POLICY_RCD_CREATED="false"
}

apt_install_exact() {
  local package="$1" version="$2" conffile_policy="$3"
  local candidate deb=""
  local -a candidates=()
  shopt -s nullglob
  candidates=("$RUN_DIR"/debs/*.deb)
  shopt -u nullglob
  for candidate in "${candidates[@]}"; do
    if [[ "$(dpkg-deb -f "$candidate" Package)" == "$package" \
      && "$(dpkg-deb -f "$candidate" Version)" == "$version" ]]; then
      deb="$candidate"
      break
    fi
  done
  [[ -n "$deb" ]] || die "Downloaded package artifact is missing: $package=$version"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-download \
    -o "Dpkg::Options::=--force-${conffile_policy}" "$deb"
}

set_allocation() {
  local value="$1"
  indexer_curl -X PUT "$INDEXER_URL/_cluster/settings" \
    -H 'Content-Type: application/json' \
    -d "{\"persistent\":{\"cluster.routing.allocation.enable\":\"$value\"}}" \
    | python3 -c 'import json,sys; assert json.load(sys.stdin).get("acknowledged") is True'
}

wait_for_indexer() {
  local attempt
  for attempt in {1..60}; do
    if indexer_curl "$INDEXER_URL/_cluster/health" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}

wait_for_green() {
  local response status unassigned relocating initializing
  for _ in {1..90}; do
    response=$(indexer_curl "$INDEXER_URL/_cluster/health" 2>/dev/null || true)
    if [[ -n "$response" ]]; then
      status=$(json_field "d.get('status', 'unknown')" <<<"$response")
      unassigned=$(json_field "d.get('unassigned_shards', -1)" <<<"$response")
      relocating=$(json_field "d.get('relocating_shards', -1)" <<<"$response")
      initializing=$(json_field "d.get('initializing_shards', -1)" <<<"$response")
      [[ "$status" == "green" && "$unassigned" == "0" \
        && "$relocating" == "0" && "$initializing" == "0" ]] && return 0
    fi
    sleep 2
  done
  return 1
}

wait_for_core_services() {
  local service deadline all_active
  deadline=$((SECONDS + SERVICE_WAIT_SECONDS))
  while ((SECONDS < deadline)); do
    all_active="true"
    for service in "${CORE_SERVICES[@]}"; do
      systemctl is-active --quiet "$service" || all_active="false"
    done
    bool_true "$all_active" && break
    sleep 5
  done
  for service in "${CORE_SERVICES[@]}"; do
    if systemctl is-active --quiet "$service"; then
      pass "$service is active"
    else
      fail "$service did not become active within ${SERVICE_WAIT_SECONDS}s"
    fi
  done
}

check_loaded_snapshot_path() {
  local response
  response=$(indexer_curl \
    "$INDEXER_URL/_nodes/settings?filter_path=nodes.*.settings.path.repo") \
    || { fail "Cannot query loaded Indexer path.repo"; return; }
  if python3 -c '
import json
import sys

expected = sys.argv[1]
data = json.load(sys.stdin)
loaded = []
for node in data.get("nodes", {}).values():
    value = node.get("settings", {}).get("path", {}).get("repo", [])
    if isinstance(value, str):
        value = [value]
    loaded.extend(value)
print("Loaded path.repo: " + (", ".join(sorted(set(loaded))) if loaded else "none"))
raise SystemExit(0 if expected in loaded else 1)
' "$SNAPSHOT_PATH" <<<"$response"; then
    pass "Expected Indexer snapshot path is loaded"
  else
    fail "Expected Indexer snapshot path is not loaded: $SNAPSHOT_PATH"
  fi
}

check_post_reboot_indexer_health() {
  local health shards summary status nodes primaries unassigned primary_unassigned replica_unassigned
  health=$(indexer_curl "$INDEXER_URL/_cluster/health") \
    || { fail "Indexer health request failed"; return; }
  shards=$(indexer_curl "$INDEXER_URL/_cat/shards?format=json&h=prirep,state") \
    || { fail "Indexer shard request failed"; return; }
  summary=$(python3 -c '
import json
import sys

health = json.loads(sys.argv[1])
shards = json.load(sys.stdin)
primary_unassigned = sum(
    row.get("prirep") == "p" and row.get("state") == "UNASSIGNED"
    for row in shards
)
replica_unassigned = sum(
    row.get("prirep") == "r" and row.get("state") == "UNASSIGNED"
    for row in shards
)
print("|".join(str(value) for value in (
    health.get("status", "unknown"),
    health.get("number_of_nodes", 0),
    health.get("active_primary_shards", 0),
    health.get("unassigned_shards", 0),
    primary_unassigned,
    replica_unassigned,
)))
' "$health" <<<"$shards")
  IFS='|' read -r status nodes primaries unassigned primary_unassigned replica_unassigned <<<"$summary"
  if ((primary_unassigned > 0)); then
    fail "Indexer has $primary_unassigned unassigned primary shards"
  elif [[ "$status" == "green" && "$unassigned" == "0" ]]; then
    pass "Indexer is green: nodes=$nodes active_primaries=$primaries"
  elif [[ "$status" == "yellow" && "$unassigned" == "$replica_unassigned" ]]; then
    warn "Indexer is yellow only because $replica_unassigned replicas are unassigned; primaries=$primaries"
  else
    fail "Indexer health is status=$status unassigned=$unassigned primary_unassigned=$primary_unassigned replica_unassigned=$replica_unassigned"
  fi
}

check_required_wazuh_daemons() {
  local daemon rc output="$RUN_DIR/wazuh-control-status.txt"
  local missing=()
  local required=(
    wazuh-modulesd
    wazuh-monitord
    wazuh-logcollector
    wazuh-remoted
    wazuh-syscheckd
    wazuh-analysisd
    wazuh-execd
    wazuh-db
    wazuh-authd
    wazuh-apid
  )
  if /var/ossec/bin/wazuh-control status > "$output" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  for daemon in "${required[@]}"; do
    grep -Fqx "$daemon is running..." "$output" || missing+=("$daemon")
  done
  if ((${#missing[@]})); then
    fail "Required Wazuh daemons are not running: ${missing[*]}"
  else
    pass "All required Wazuh daemons are running"
    ((rc == 0)) || log "wazuh-control exit $rc reflects disabled optional daemons"
  fi
}

post_reboot() {
  checkpoint "post-reboot-started"
  PREFLIGHT_FAILURES=0
  PREFLIGHT_WARNINGS=0
  pass "Running kernel: $(uname -r)"
  if [[ -e /var/run/reboot-required ]]; then
    fail "System reboot marker is still present"
  else
    pass "System reboot marker is cleared"
  fi
  wait_for_core_services
  if systemctl is-active --quiet wazuh-indexer; then
    check_loaded_snapshot_path
    check_post_reboot_indexer_health
  fi
  if systemctl is-active --quiet wazuh-manager; then
    check_required_wazuh_daemons
  fi
  filebeat test output -e >/dev/null 2>&1 \
    && pass "Filebeat output is reachable" \
    || fail "Filebeat output is unavailable"
  verify_dashboard
  if [[ "$PROFILE" == "homelab" ]]; then
    rsyslogd -N1 >/dev/null 2>&1 \
      && pass "rsyslog configuration test" \
      || fail "rsyslog configuration test"
  fi
  checkpoint "post-reboot-finished"
  log "Post-reboot result: failures=$PREFLIGHT_FAILURES warnings=$PREFLIGHT_WARNINGS"
  ((PREFLIGHT_FAILURES == 0)) || return 1
}

upgrade_components() {
  local indexer_pkg manager_pkg dashboard_pkg filebeat_pkg
  indexer_pkg=$(awk -F= '$1=="wazuh-indexer" {print $2}' "$RUN_DIR/package-targets")
  manager_pkg=$(awk -F= '$1=="wazuh-manager" {print $2}' "$RUN_DIR/package-targets")
  dashboard_pkg=$(awk -F= '$1=="wazuh-dashboard" {print $2}' "$RUN_DIR/package-targets")
  filebeat_pkg=$(awk -F= '$1=="filebeat" {print $2}' "$RUN_DIR/package-targets")

  checkpoint "maintenance-started"
  systemctl stop filebeat wazuh-dashboard
  /usr/share/wazuh-indexer/bin/indexer-security-init.sh \
    --options "-backup /etc/wazuh-indexer/opensearch-security -icl -nhnv"
  checkpoint "indexer-security-config-backed-up"
  set_allocation primaries
  indexer_curl -X POST "$INDEXER_URL/_flush" >/dev/null
  systemctl stop wazuh-manager
  systemctl stop wazuh-indexer
  checkpoint "central-services-stopped"

  install_policy_rcd
  apt_install_exact wazuh-indexer "$indexer_pkg" confold
  install -o root -g wazuh-indexer -m 0660 \
    "$RUN_DIR/merged-config/jvm.options" /etc/wazuh-indexer/jvm.options
  systemctl daemon-reload
  systemctl enable wazuh-indexer
  systemctl start wazuh-indexer
  wait_for_indexer || die "Indexer did not become reachable"
  /usr/share/wazuh-indexer/bin/indexer-security-init.sh
  set_allocation all
  wait_for_green || die "Indexer did not return to green"
  checkpoint "indexer-upgraded-green"

  apt_install_exact wazuh-manager "$manager_pkg" confold
  run_config_checks_after_manager
  systemctl daemon-reload
  systemctl enable wazuh-manager
  systemctl start wazuh-manager
  checkpoint "manager-upgraded"

  cp -a /etc/filebeat/filebeat.yml "$RUN_DIR/filebeat.yml.before-package"
  tar -xzf "$RUN_DIR/artifacts/wazuh-filebeat-0.5.tar.gz" -C /usr/share/filebeat/module
  install -o root -g root -m 0644 "$RUN_DIR/artifacts/wazuh-template.json" /etc/filebeat/wazuh-template.json
  apt_install_exact filebeat "$filebeat_pkg" confold
  cp -a "$RUN_DIR/filebeat.yml.before-package" /etc/filebeat/filebeat.yml
  systemctl daemon-reload
  systemctl enable filebeat
  systemctl start filebeat
  filebeat setup --pipelines
  filebeat setup --index-management -E output.logstash.enabled=false
  checkpoint "filebeat-upgraded-configured"

  apt_install_exact wazuh-dashboard "$dashboard_pkg" confold
  install -o root -g wazuh-dashboard -m 0660 \
    "$RUN_DIR/merged-config/opensearch_dashboards.yml" \
    /etc/wazuh-dashboard/opensearch_dashboards.yml
  systemctl daemon-reload
  systemctl enable wazuh-dashboard
  systemctl start wazuh-dashboard
  checkpoint "dashboard-upgraded"
  restore_policy_rcd
}

run_config_checks_after_manager() {
  /var/ossec/bin/wazuh-analysisd -t
  /var/ossec/bin/wazuh-modulesd -t
  [[ ! -x /var/ossec/bin/wazuh-logcollector ]] || /var/ossec/bin/wazuh-logcollector -t
}

disable_wazuh_repository() {
  local repo found="false" backup_dir="$RUN_DIR/apt-sources.before-disable"
  install -d -m 0700 "$backup_dir"
  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    found="true"
    cp -a "$repo" "$backup_dir/$(basename "$repo")"
    sed -i -E \
      '/packages\.wazuh\.com\/4\.x\/apt/ s/^([[:space:]]*)(deb )/\1#\2/' "$repo"
  done < <(grep -lE '^[[:space:]]*deb .*packages\.wazuh\.com/4\.x/apt' \
    /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true)
  if bool_true "$found"; then
    pass "Official Wazuh APT source disabled after upgrade"
  else
    pass "Official Wazuh APT source was already disabled"
  fi
  if apt-get update; then
    pass "APT metadata refreshed after disabling the Wazuh repository"
  else
    warn "APT metadata refresh failed after repository disable; continuing to verification"
  fi
  checkpoint "wazuh-repository-disabled"
}

verify_versions() {
  local package installed filebeat_target
  for package in "${CENTRAL_PACKAGES[@]}"; do
    installed=$(package_version "$package")
    [[ "$(base_version "$installed")" == "$TARGET_VERSION" ]] \
      && pass "$package is $installed" \
      || fail "$package is $installed; expected $TARGET_VERSION"
  done
  installed=$(package_version filebeat)
  if [[ -f "$RUN_DIR/package-targets" ]]; then
    filebeat_target=$(awk -F= '$1=="filebeat" {print $2}' "$RUN_DIR/package-targets")
    [[ -n "$filebeat_target" && "$installed" == "$filebeat_target" ]] \
      && pass "filebeat is $installed" \
      || fail "filebeat is $installed; expected ${filebeat_target:-unknown}"
  else
    warn "Filebeat target manifest is unavailable; installed version is $installed"
  fi
}

verify_services() {
  local service
  for service in "${CORE_SERVICES[@]}"; do
    systemctl is-active --quiet "$service" && pass "$service is active" || fail "$service is not active"
  done
  check_required_wazuh_daemons
}

verify_dashboard() {
  local code="000" deadline
  deadline=$((SECONDS + DASHBOARD_WAIT_SECONDS))
  while ((SECONDS < deadline)); do
    code=$(curl -k -s -o /dev/null -w '%{http_code}' \
      --connect-timeout 5 --max-time 15 "$DASHBOARD_URL" || true)
    if [[ "$code" =~ ^(200|302)$ ]]; then
      pass "Dashboard HTTP status is $code"
      return
    fi
    sleep 5
  done
  fail "Dashboard HTTP endpoint did not become ready within ${DASHBOARD_WAIT_SECONDS}s (last status: $code)"
}

verify_strict_manifest() {
  local before="$RUN_DIR/strict-config.before.sha256" after="$RUN_DIR/strict-config.after.sha256"
  write_strict_manifest "$after"
  if [[ -f "$before" ]]; then
    diff -u "$before" "$after" > "$RUN_DIR/strict-config.diff" \
      && pass "Protected configuration is unchanged" \
      || fail "Protected configuration changed; see $RUN_DIR/strict-config.diff"
  else
    warn "No pre-upgrade strict manifest is available for comparison"
  fi
}

verify_ingest_counts() {
  local name payload response count
  while IFS='|' read -r name payload; do
    response=$(indexer_curl -X POST "$INDEXER_URL/wazuh-alerts-*/_count" \
      -H 'Content-Type: application/json' -d "$payload" 2>/dev/null || true)
    if [[ -z "$response" ]]; then
      warn "Cannot query recent $name ingest"
      continue
    fi
    count=$(json_field "d.get('count', 0)" <<<"$response")
    ((count > 0)) && pass "$name has $count indexed events in $INGEST_LOOKBACK" \
      || warn "$name has no indexed events in $INGEST_LOOKBACK"
  done <<EOF
UniFi|{"query":{"bool":{"filter":[{"range":{"@timestamp":{"gte":"now-$INGEST_LOOKBACK"}}},{"match_phrase":{"rule.groups":"unifi"}}]}}}
Home Assistant|{"query":{"bool":{"filter":[{"range":{"@timestamp":{"gte":"now-$INGEST_LOOKBACK"}}},{"match_phrase":{"rule.groups":"homeassistant"}}]}}}
SafeLine|{"query":{"bool":{"filter":[{"range":{"@timestamp":{"gte":"now-$INGEST_LOOKBACK"}}},{"match_phrase":{"rule.groups":"safeline_waf_event"}}]}}}
UGREEN|{"query":{"bool":{"filter":[{"range":{"@timestamp":{"gte":"now-$INGEST_LOOKBACK"}}},{"match_phrase":{"rule.groups":"ugreen"}}]}}}
EOF
}

verify() {
  checkpoint "verify-started"
  PREFLIGHT_FAILURES=0
  PREFLIGHT_WARNINGS=0
  wait_for_core_services
  verify_versions
  verify_services
  run_config_checks
  check_indexer_health after
  filebeat test config -e >/dev/null 2>&1 && pass "Filebeat config remains valid" || fail "Filebeat config invalid"
  filebeat test output -e >/dev/null 2>&1 && pass "Filebeat output is reachable" || fail "Filebeat output unavailable"
  verify_dashboard
  [[ "$PROFILE" != "homelab" ]] || check_ingest_contracts
  check_agents after
  compare_agent_counts
  verify_strict_manifest
  if [[ "$PROFILE" == "homelab" ]]; then
    run_repository_regression after
    compare_regression_results
    verify_ingest_counts
  fi
  checkpoint "verify-finished"
  log "Verify result: failures=$PREFLIGHT_FAILURES warnings=$PREFLIGHT_WARNINGS"
  ((PREFLIGHT_FAILURES == 0)) || return 1
}

apply_upgrade() {
  bool_true "$CONFIRM_UPGRADE" || die "apply requires --confirm-upgrade"
  REFRESH_APT="true"
  preflight
  prepare_artifacts
  upgrade_components
  disable_wazuh_repository
  checkpoint "apply-finished"
  verify
}

main() {
  local argument
  for argument in "$@"; do
    if [[ "$argument" == "-h" || "$argument" == "--help" ]]; then
      usage
      exit 0
    fi
  done
  preload_config_path "$@"
  load_config
  parse_args "$@"
  configure_profile
  initialize_run
  case "$MODE" in
    preflight) preflight ;;
    post-reboot) post_reboot ;;
    apply) apply_upgrade ;;
    verify) verify ;;
  esac
  log "$MODE completed successfully."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
