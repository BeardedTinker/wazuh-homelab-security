#!/usr/bin/env python3
"""Sanitize UniFi log input with deterministic documentation addresses."""

from __future__ import annotations

import ipaddress
import re
import sys
from pathlib import Path


IPV4_PATTERN = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
MAC_PATTERN = re.compile(r"MAC=\S+")
SAFE_NETWORKS = tuple(
    ipaddress.ip_network(network)
    for network in ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24")
)


def sanitize(text: str) -> str:
    """Replace MAC values and non-documentation IPv4 addresses."""
    mapping: dict[str, str] = {}
    text = MAC_PATTERN.sub("MAC=<MAC>", text)

    def replace_ipv4(match: re.Match[str]) -> str:
        value = match.group(0)
        try:
            address = ipaddress.ip_address(value)
        except ValueError:
            return value
        if any(address in network for network in SAFE_NETWORKS):
            return value
        if value not in mapping:
            host = len(mapping) + 1
            if host > 254:
                raise RuntimeError("too many distinct IPv4 addresses to sanitize")
            mapping[value] = f"198.51.100.{host}"
        return mapping[value]

    return IPV4_PATTERN.sub(replace_ipv4, text)


def main() -> int:
    source = sys.argv[1] if len(sys.argv) > 1 else "/dev/stdin"
    text = sys.stdin.read() if source == "/dev/stdin" else Path(source).read_text(encoding="utf-8")
    sys.stdout.write(sanitize(text))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
