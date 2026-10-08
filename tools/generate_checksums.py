#!/usr/bin/env python3

"""Generate or verify checksums for shipped operational repository files."""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "SHA256SUMS"
INCLUDE_PATTERNS = (
    "homeassistant/adapter/*.yaml",
    "safeline/collector/*.py",
    "tools/**/*.py",
    "tools/**/*.sh",
    "ugreen/fluent-bit/*.conf",
    "ugreen/fluent-bit/compose.yaml",
    "ugreen/rsyslog/*",
    "wazuh/decoders/*.xml",
    "wazuh/indexer/*.json",
    "wazuh/manager/*.conf",
    "wazuh/ossec.conf.snippets/*.xml",
    "wazuh/rules/*.xml",
)


def selected_files() -> list[Path]:
    selected: set[Path] = set()
    missing_patterns: list[str] = []

    for pattern in INCLUDE_PATTERNS:
        matches = {path for path in ROOT.glob(pattern) if path.is_file()}
        if not matches:
            missing_patterns.append(pattern)
        selected.update(matches)

    if missing_patterns:
        joined = ", ".join(missing_patterns)
        raise RuntimeError(f"checksum patterns matched no files: {joined}")

    return sorted(selected, key=lambda path: path.relative_to(ROOT).as_posix())


def generated_content() -> str:
    lines: list[str] = []
    for path in selected_files():
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        relative = path.relative_to(ROOT).as_posix()
        lines.append(f"{digest}  {relative}")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate or verify SHA256SUMS for operational files."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify that SHA256SUMS matches generated content",
    )
    args = parser.parse_args()

    try:
        content = generated_content()
    except (OSError, RuntimeError) as exc:
        print(f"Checksum generation failed: {exc}", file=sys.stderr)
        return 1

    if args.check:
        if not OUTPUT.is_file():
            print("Checksum verification failed: SHA256SUMS is missing", file=sys.stderr)
            return 1
        if OUTPUT.read_text(encoding="utf-8") != content:
            print(
                "Checksum verification failed: run tools/generate_checksums.py",
                file=sys.stderr,
            )
            return 1
        print(f"Checksum verification passed for {len(selected_files())} files.")
        return 0

    OUTPUT.write_text(content, encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)} for {len(selected_files())} files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
