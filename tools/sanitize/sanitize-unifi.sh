#!/usr/bin/env bash
set -euo pipefail

in="${1:-/dev/stdin}"

# 1) Remove / anonymize MAC field content
# 2) Replace any public IPv4 with TEST-NET-3-ish tokens (simple approach)
# 3) Replace private RFC1918 blocks to 10.10.x.x (rough mask)

sed -E \
  -e 's/MAC=[^ ]+/MAC=<MAC>/g' \
  -e 's/\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b/10.10.1.10/g' \
  -e 's/\b192\.168\.150\.[0-9]{1,3}\b/10.10.150.10/g' \
  -e 's/\b192\.168\.2\.[0-9]{1,3}\b/10.10.2.10/g' \
  -e 's/\b(?!10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)([0-9]{1,3}\.){3}[0-9]{1,3}\b/203.0.113.99/g' \
  "$in"
