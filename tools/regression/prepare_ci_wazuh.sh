#!/usr/bin/env bash

set -euo pipefail

readonly WAZUH_MANAGER_VERSION="4.14.9-1"
readonly WAZUH_MANAGER_ARCHITECTURE="amd64"
readonly WAZUH_MANAGER_FILENAME="wazuh-manager_${WAZUH_MANAGER_VERSION}_${WAZUH_MANAGER_ARCHITECTURE}.deb"
readonly WAZUH_MANAGER_URL="https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-manager/${WAZUH_MANAGER_FILENAME}"
readonly WAZUH_MANAGER_SHA256="8b6f615f84c93a51c6023e7e542b9519945684434b117396ae61517bcdcba5f8"

usage() {
  cat <<'EOF'
Usage: prepare_ci_wazuh.sh PACKAGE_CACHE DESTINATION

Download and verify the pinned Wazuh Manager package when it is not cached,
extract it into a new isolated tree, and install this repository's custom
decoders, rules, and audited internal options into that tree.
EOF
}

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 2
fi

readonly PACKAGE_CACHE="$1"
readonly DESTINATION="$2"
readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

verify_checksum() {
  printf '%s  %s\n' "$WAZUH_MANAGER_SHA256" "$PACKAGE_CACHE" | sha256sum --check --status
}

mkdir -p "$(dirname "$PACKAGE_CACHE")"

if [[ -f "$PACKAGE_CACHE" ]] && ! verify_checksum; then
  echo "Cached Wazuh package failed SHA-256 verification; downloading a clean copy." >&2
  rm -f "$PACKAGE_CACHE"
fi

if [[ ! -f "$PACKAGE_CACHE" ]]; then
  temporary_package="${PACKAGE_CACHE}.download"
  rm -f "$temporary_package"
  curl \
    --fail \
    --location \
    --proto '=https' \
    --retry 3 \
    --show-error \
    --silent \
    --tlsv1.2 \
    --output "$temporary_package" \
    "$WAZUH_MANAGER_URL"
  mv "$temporary_package" "$PACKAGE_CACHE"
fi

verify_checksum || {
  echo "Wazuh package SHA-256 verification failed." >&2
  exit 1
}

package_name="$(dpkg-deb --field "$PACKAGE_CACHE" Package)"
package_version="$(dpkg-deb --field "$PACKAGE_CACHE" Version)"
package_architecture="$(dpkg-deb --field "$PACKAGE_CACHE" Architecture)"

[[ "$package_name" == "wazuh-manager" ]] || {
  echo "Unexpected package name: $package_name" >&2
  exit 1
}
[[ "$package_version" == "$WAZUH_MANAGER_VERSION" ]] || {
  echo "Unexpected package version: $package_version" >&2
  exit 1
}
[[ "$package_architecture" == "$WAZUH_MANAGER_ARCHITECTURE" ]] || {
  echo "Unexpected package architecture: $package_architecture" >&2
  exit 1
}

if [[ -e "$DESTINATION" ]]; then
  echo "Destination already exists: $DESTINATION" >&2
  exit 1
fi

mkdir -p "$DESTINATION"
dpkg-deb --extract "$PACKAGE_CACHE" "$DESTINATION"

readonly WAZUH_ROOT="$DESTINATION/var/ossec"
[[ -x "$WAZUH_ROOT/bin/wazuh-logtest-legacy" ]] || {
  echo "Extracted package does not contain wazuh-logtest-legacy." >&2
  exit 1
}

install -m 0644 "$REPOSITORY_ROOT"/wazuh/decoders/*.xml "$WAZUH_ROOT/etc/decoders/"
install -m 0644 "$REPOSITORY_ROOT"/wazuh/rules/*.xml "$WAZUH_ROOT/etc/rules/"
install -m 0644 \
  "$REPOSITORY_ROOT/wazuh/manager/local_internal_options.conf" \
  "$WAZUH_ROOT/etc/local_internal_options.conf"

echo "Prepared isolated Wazuh Manager $WAZUH_MANAGER_VERSION tree at $WAZUH_ROOT"
