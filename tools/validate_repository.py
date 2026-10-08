#!/usr/bin/env python3

"""Dependency-free static validation for repository structure and fixtures."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
VALID_CLASSIFICATIONS = {"pass", "pending", "known_fail"}
BUILTIN_DECODERS = {"json", "kernel"}
MARKDOWN_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")


class Validator:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.rule_ids: list[tuple[str, Path]] = []
        self.decoder_names: list[tuple[str, Path]] = []
        self.expected_rule_ids: list[tuple[int, Path]] = []
        self.expected_decoders: list[tuple[str, Path]] = []
        self.scenario_counts: Counter[str] = Counter()

    def error(self, path: Path | str, message: str) -> None:
        try:
            display = Path(path).relative_to(ROOT)
        except (TypeError, ValueError):
            display = path
        self.errors.append(f"{display}: {message}")

    def validate_xml(self) -> None:
        groups = {
            "rules": ROOT / "wazuh" / "rules",
            "decoders": ROOT / "wazuh" / "decoders",
            "snippets": ROOT / "wazuh" / "ossec.conf.snippets",
        }

        for kind, directory in groups.items():
            paths = sorted(directory.glob("*.xml"))
            if not paths:
                self.error(directory, "contains no XML files")
                continue

            for path in paths:
                try:
                    root = ET.fromstring(
                        f"<repository-fragment>\n{path.read_text(encoding='utf-8')}"
                        "\n</repository-fragment>"
                    )
                except (OSError, ET.ParseError) as exc:
                    self.error(path, f"invalid XML fragment: {exc}")
                    continue

                if kind == "rules":
                    elements = [child for child in root if isinstance(child.tag, str)]
                    if any(child.tag != "group" for child in elements):
                        self.error(path, "rule files may contain only top-level <group> elements")
                    for rule in root.iter("rule"):
                        rule_id = rule.get("id")
                        if not rule_id or not rule_id.isdigit():
                            self.error(path, "every <rule> requires a numeric id")
                            continue
                        self.rule_ids.append((rule_id, path))
                        value = int(rule_id)
                        if not 100000 <= value <= 120000:
                            self.error(path, f"custom rule id {rule_id} is outside 100000-120000")

                elif kind == "decoders":
                    elements = [child for child in root if isinstance(child.tag, str)]
                    if any(child.tag != "decoder" for child in elements):
                        self.error(path, "decoder files may contain only top-level <decoder> elements")
                    for decoder in root.iter("decoder"):
                        name = decoder.get("name")
                        if not name:
                            self.error(path, "every <decoder> requires a name")
                            continue
                        self.decoder_names.append((name, path))

        for value, count in Counter(rule_id for rule_id, _ in self.rule_ids).items():
            if count > 1:
                paths = sorted(
                    str(path.relative_to(ROOT))
                    for rule_id, path in self.rule_ids
                    if rule_id == value
                )
                self.error("wazuh/rules", f"duplicate rule id {value}: {', '.join(paths)}")

        for value, count in Counter(name for name, _ in self.decoder_names).items():
            if count > 1:
                paths = sorted(
                    str(path.relative_to(ROOT))
                    for name, path in self.decoder_names
                    if name == value
                )
                self.error("wazuh/decoders", f"duplicate decoder {value}: {', '.join(paths)}")

    def validate_json_and_scenarios(self) -> None:
        json_documents: dict[Path, object] = {}
        for path in sorted(ROOT.rglob("*.json")):
            if ".git" in path.parts:
                continue
            try:
                json_documents[path] = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                self.error(path, f"invalid JSON: {exc}")

        scenario_paths = sorted((ROOT / "samples").rglob("scenario.json"))
        if not scenario_paths:
            self.error("samples", "contains no scenario.json files")

        for path in scenario_paths:
            value = json_documents.get(path)
            if not isinstance(value, dict):
                self.error(path, "scenario metadata must be a JSON object")
                continue

            classification = value.get("classification")
            if classification not in VALID_CLASSIFICATIONS:
                self.error(
                    path,
                    f"classification must be one of {sorted(VALID_CLASSIFICATIONS)}",
                )
                continue
            self.scenario_counts[classification] += 1

            if not isinstance(value.get("summary"), str) or not value["summary"].strip():
                self.error(path, "scenario requires a non-empty summary")
            if classification == "pending" and (
                not isinstance(value.get("reason"), str) or not value["reason"].strip()
            ):
                self.error(path, "pending scenario requires a non-empty reason")

            expected_path = path.parent / "expected.json"
            expected = json_documents.get(expected_path)
            if expected is None:
                self.error(path, "scenario requires expected.json")
            elif not isinstance(expected, (dict, list)) or not expected:
                self.error(expected_path, "expected result must be a non-empty object or list")
            else:
                self.collect_expected_references(expected, expected_path)

            raw_path = path.parent / "raw.log"
            if classification in {"pass", "known_fail"} and not raw_path.is_file():
                self.error(path, f"{classification} scenario requires raw.log")

        defined_rules = {int(rule_id) for rule_id, _ in self.rule_ids}
        for rule_id, path in self.expected_rule_ids:
            if rule_id not in defined_rules:
                self.error(path, f"expected custom rule {rule_id} is not defined")

        defined_decoders = {name for name, _ in self.decoder_names} | BUILTIN_DECODERS
        for decoder, path in self.expected_decoders:
            if decoder not in defined_decoders:
                self.error(path, f"expected decoder {decoder!r} is not defined or allowlisted")

    def collect_expected_references(self, value: object, path: Path) -> None:
        if isinstance(value, dict):
            decoder = value.get("decoder")
            if isinstance(decoder, str):
                self.expected_decoders.append((decoder, path))

            for key in ("rules", "rules_expected"):
                rules = value.get(key)
                if rules is None:
                    continue
                if not isinstance(rules, list) or not all(
                    isinstance(rule_id, int) for rule_id in rules
                ):
                    self.error(path, f"{key} must be a list of integer rule IDs")
                else:
                    self.expected_rule_ids.extend((rule_id, path) for rule_id in rules)

            for child in value.values():
                self.collect_expected_references(child, path)

        elif isinstance(value, list):
            for child in value:
                self.collect_expected_references(child, path)

    def validate_python_and_shell(self) -> None:
        for path in sorted(ROOT.rglob("*.py")):
            if ".git" in path.parts:
                continue
            try:
                compile(path.read_text(encoding="utf-8"), str(path), "exec")
            except (OSError, SyntaxError) as exc:
                self.error(path, f"Python syntax error: {exc}")

        for path in sorted(ROOT.rglob("*.sh")):
            if ".git" in path.parts:
                continue
            completed = subprocess.run(
                ["bash", "-n", str(path)],
                capture_output=True,
                text=True,
                check=False,
            )
            if completed.returncode != 0:
                detail = (completed.stderr or completed.stdout).strip()
                self.error(path, f"shell syntax error: {detail}")

    def validate_markdown_links(self) -> None:
        for path in sorted(ROOT.rglob("*.md")):
            if ".git" in path.parts:
                continue
            text = path.read_text(encoding="utf-8")
            for raw_target in MARKDOWN_LINK.findall(text):
                target = raw_target.strip().strip("<>")
                if target.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                target = unquote(target.split("#", 1)[0].split("?", 1)[0])
                if target and not (path.parent / target).exists():
                    self.error(path, f"local Markdown link target does not exist: {target}")

    def validate_collector_checksum(self) -> None:
        collector = ROOT / "safeline" / "collector" / "safeline-wazuh-collector.py"
        readme = ROOT / "safeline" / "README.md"
        digest = hashlib.sha256(collector.read_bytes()).hexdigest()
        if digest not in readme.read_text(encoding="utf-8"):
            self.error(readme, f"does not contain collector SHA-256 {digest}")

    def run(self) -> int:
        self.validate_xml()
        self.validate_json_and_scenarios()
        self.validate_python_and_shell()
        self.validate_markdown_links()
        self.validate_collector_checksum()

        if self.errors:
            print("Repository validation failed:", file=sys.stderr)
            for error in self.errors:
                print(f"- {error}", file=sys.stderr)
            return 1

        scenario_summary = ", ".join(
            f"{name.upper()}={self.scenario_counts.get(name, 0)}"
            for name in ("pass", "known_fail", "pending")
        )
        print(
            "Repository validation passed: "
            f"{len(self.rule_ids)} rules, {len(self.decoder_names)} decoders, "
            f"{scenario_summary}."
        )
        print("Runtime Wazuh regression is intentionally not executed by this validator.")
        return 0


if __name__ == "__main__":
    raise SystemExit(Validator().run())
