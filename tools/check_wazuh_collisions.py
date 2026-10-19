#!/usr/bin/env python3

"""Check repository rule IDs and decoder names against a Wazuh installation."""

from __future__ import annotations

import argparse
import html
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SOURCE_FILES = {
    "unifi": {
        "rules": ("wazuh/rules/0100-unifi-rules.xml",),
        "decoders": ("wazuh/decoders/0100-unifi-decoders.xml",),
    },
    "synology": {
        "rules": ("wazuh/rules/0200-synology-rules.xml",),
        "decoders": ("wazuh/decoders/0200-synology-decoders.xml",),
    },
    "homeassistant": {
        "rules": ("wazuh/rules/0300-homeassistant-rules.xml",),
        "decoders": ("wazuh/decoders/0300-homeassistant-decoders.xml",),
    },
    "safeline": {
        "rules": ("wazuh/rules/0480-safeline-rules.xml",),
        "decoders": (),
    },
    "ugreen": {
        "rules": ("wazuh/rules/0500-ugreen-rules.xml",),
        "decoders": ("wazuh/decoders/0500-ugreen-decoders.xml",),
    },
    "minecraft": {
        "rules": ("wazuh/rules/0600-minecraft-rules.xml",),
        "decoders": ("wazuh/decoders/0600-minecraft-decoders.xml",),
    },
}
COMMENT_PATTERN = re.compile(r"<!--.*?-->", re.DOTALL)
IDENTIFIER_PATTERNS = {
    "rules": re.compile(r"<rule\b[^>]*\bid\s*=\s*['\"](\d+)['\"]", re.IGNORECASE),
    "decoders": re.compile(
        r"<decoder\b[^>]*\bname\s*=\s*['\"]([^'\"]+)['\"]",
        re.IGNORECASE,
    ),
}


@dataclass(frozen=True)
class Definition:
    kind: str
    identifier: str
    path: Path
    scope: str


@dataclass(frozen=True)
class Match:
    candidate: Definition
    installed: Definition


@dataclass
class Report:
    candidates: list[Definition]
    collisions: list[Match]
    allowed_same_file: list[Match]
    errors: list[str]

    @property
    def passed(self) -> bool:
        return not self.collisions and not self.errors


def extract_definitions(path: Path, kind: str, scope: str) -> list[Definition]:
    """Extract identifiers without requiring one top-level XML element."""

    text = path.read_text(encoding="utf-8")
    uncommented = COMMENT_PATTERN.sub("", text)
    return [
        Definition(kind, html.unescape(value).strip(), path, scope)
        for value in IDENTIFIER_PATTERNS[kind].findall(uncommented)
    ]


def selected_sources(source: str) -> tuple[str, ...]:
    if source == "all":
        return tuple(SOURCE_FILES)
    return (source,)


def load_candidates(
    repository_root: Path, source: str
) -> tuple[list[Definition], list[str]]:
    definitions: list[Definition] = []
    errors: list[str] = []

    for source_name in selected_sources(source):
        for kind, relative_paths in SOURCE_FILES[source_name].items():
            for relative_path in relative_paths:
                path = repository_root / relative_path
                if not path.is_file():
                    errors.append(f"candidate file is missing: {path}")
                    continue
                try:
                    extracted = extract_definitions(path, kind, "candidate")
                except (OSError, UnicodeError) as exc:
                    errors.append(f"cannot read candidate file {path}: {exc}")
                    continue
                if not extracted:
                    errors.append(f"candidate file contains no {kind}: {path}")
                definitions.extend(extracted)

    keys = [(definition.kind, definition.identifier) for definition in definitions]
    for key, count in Counter(keys).items():
        if count > 1:
            errors.append(
                f"candidate selection repeats {key[0][:-1]} {key[1]} {count} times"
            )

    return definitions, errors


def load_installed(wazuh_root: Path) -> tuple[list[Definition], list[str]]:
    definitions: list[Definition] = []
    errors: list[str] = []
    trees = (
        ("rules", "custom", wazuh_root / "etc" / "rules"),
        ("decoders", "custom", wazuh_root / "etc" / "decoders"),
        ("rules", "builtin", wazuh_root / "ruleset" / "rules"),
        ("decoders", "builtin", wazuh_root / "ruleset" / "decoders"),
    )

    for kind, scope, directory in trees:
        if not directory.is_dir():
            errors.append(f"required Wazuh directory is missing: {directory}")
            continue
        try:
            paths = sorted(path for path in directory.rglob("*.xml") if path.is_file())
        except OSError as exc:
            errors.append(f"cannot list Wazuh directory {directory}: {exc}")
            continue
        for path in paths:
            try:
                definitions.extend(extract_definitions(path, kind, scope))
            except (OSError, UnicodeError) as exc:
                errors.append(f"cannot read installed file {path}: {exc}")

    return definitions, errors


def check_collisions(
    repository_root: Path,
    wazuh_root: Path,
    source: str,
    allow_same_file: bool = False,
) -> Report:
    candidates, candidate_errors = load_candidates(repository_root, source)
    installed, installed_errors = load_installed(wazuh_root)
    installed_by_key: dict[tuple[str, str], list[Definition]] = {}
    for definition in installed:
        installed_by_key.setdefault(
            (definition.kind, definition.identifier), []
        ).append(definition)

    candidate_keys = {
        (definition.kind, definition.identifier) for definition in candidates
    }
    installed_occurrences = Counter(
        (definition.kind, definition.identifier, definition.path)
        for definition in installed
        if (definition.kind, definition.identifier) in candidate_keys
    )
    duplicate_errors = [
        f"installed file repeats {kind[:-1]} {identifier} {count} times: {path}"
        for (kind, identifier, path), count in installed_occurrences.items()
        if count > 1
    ]

    collisions: list[Match] = []
    allowed: list[Match] = []
    for candidate in candidates:
        for existing in installed_by_key.get(
            (candidate.kind, candidate.identifier), []
        ):
            match = Match(candidate, existing)
            same_custom_filename = (
                existing.scope == "custom"
                and existing.path.parent == wazuh_root / "etc" / candidate.kind
                and existing.path.name == candidate.path.name
            )
            if allow_same_file and same_custom_filename:
                allowed.append(match)
            else:
                collisions.append(match)

    return Report(
        candidates=candidates,
        collisions=collisions,
        allowed_same_file=allowed,
        errors=candidate_errors + installed_errors + duplicate_errors,
    )


def display_path(path: Path, base: Path | None = None) -> str:
    if base is not None:
        try:
            return path.relative_to(base).as_posix()
        except ValueError:
            pass
    return str(path)


def print_report(report: Report, repository_root: Path, source: str) -> None:
    print(f"Source selection: {source}")
    print(f"Candidate identifiers: {len(report.candidates)}")

    for error in report.errors:
        print(f"ERROR: {error}", file=sys.stderr)

    for match in report.allowed_same_file:
        label = "rule ID" if match.candidate.kind == "rules" else "decoder name"
        print(
            "REVIEWED SAME-FILE: "
            f"{label} {match.candidate.identifier} in "
            f"{display_path(match.installed.path)}"
        )

    for match in report.collisions:
        label = "rule ID" if match.candidate.kind == "rules" else "decoder name"
        print(
            "COLLISION: "
            f"{label} {match.candidate.identifier}; candidate "
            f"{display_path(match.candidate.path, repository_root)}; installed "
            f"{display_path(match.installed.path)}",
            file=sys.stderr,
        )

    if report.passed:
        print(
            "Collision check passed: no unapproved rule-ID or decoder-name "
            "matches found."
        )
    else:
        print("Collision check failed; do not install or restart.", file=sys.stderr)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compare repository rule IDs and decoder names with a Wazuh tree. "
            "The check is read-only."
        )
    )
    parser.add_argument(
        "--source",
        required=True,
        choices=tuple(SOURCE_FILES) + ("all",),
        help="repository source content to check",
    )
    parser.add_argument(
        "--wazuh-root",
        type=Path,
        default=Path("/var/ossec"),
        help="Wazuh root to inspect (default: /var/ossec)",
    )
    parser.add_argument(
        "--repository-root",
        type=Path,
        default=REPOSITORY_ROOT,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--allow-same-file",
        action="store_true",
        help=(
            "allow identifiers already present only in a custom file with the "
            "same basename; use only after reviewing an intended replacement"
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repository_root = args.repository_root.resolve()
    wazuh_root = args.wazuh_root.resolve()
    report = check_collisions(
        repository_root=repository_root,
        wazuh_root=wazuh_root,
        source=args.source,
        allow_same_file=args.allow_same_file,
    )
    print_report(report, repository_root, args.source)
    return 0 if report.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
