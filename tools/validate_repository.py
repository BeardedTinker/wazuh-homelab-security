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
ADAPTER_UNIQUE_IDS = {
    "siem_security_score",
    "wazuh_critical_24h",
    "wazuh_high_24h",
    "wazuh_indexer_last_successful_poll",
    "wazuh_low_24h",
    "wazuh_medium_24h",
    "wazuh_safeline_alerts_24h",
    "wazuh_safeline_blocked_attacks_24h",
    "wazuh_safeline_last_attack",
    "wazuh_safeline_multi_vector_24h",
    "wazuh_safeline_repeated_attacks_24h",
    "wazuh_safeline_sqli_24h",
    "wazuh_safeline_top_source_ip_24h",
    "wazuh_safeline_xss_24h",
    "wazuh_security_last_5",
    "wazuh_source_home_assistant_24h",
    "wazuh_source_safeline_24h",
    "wazuh_source_synology_24h",
    "wazuh_source_ugreen_24h",
    "wazuh_source_unifi_24h",
    "wazuh_top_rule_24h",
    "wazuh_top_wan_local_dpt_24h",
    "wazuh_top_wan_local_srcip_24h",
    "wazuh_ugreen_account_changes_24h",
    "wazuh_ugreen_events_24h",
    "wazuh_ugreen_last_event",
    "wazuh_ugreen_ssh_success_24h",
    "wazuh_ugreen_storage_alerts_24h",
    "wazuh_ugreen_top_source_ip_24h",
    "wazuh_ugreen_web_failures_24h",
    "wazuh_ugreen_web_success_24h",
    "wazuh_wan_local_drops_24h",
}
ADAPTER_RECORDER_EXCLUSIONS = {
    "sensor.wazuh_safeline_last_attack",
    "sensor.wazuh_security_last_5",
    "sensor.wazuh_source_home_assistant_24h",
    "sensor.wazuh_source_safeline_24h",
    "sensor.wazuh_source_synology_24h",
    "sensor.wazuh_source_ugreen_24h",
    "sensor.wazuh_source_unifi_24h",
    "sensor.wazuh_ugreen_last_event",
}


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

    def validate_home_assistant_adapter(self) -> None:
        package = ROOT / "homeassistant" / "adapter" / "wazuh_adapter.yaml"
        secrets = ROOT / "homeassistant" / "adapter" / "secrets.example.yaml"

        try:
            package_text = package.read_text(encoding="utf-8")
            secrets_text = secrets.read_text(encoding="utf-8")
        except OSError as exc:
            self.error("homeassistant/adapter", f"cannot read adapter files: {exc}")
            return

        resources = re.findall(
            r"^\s+- resource: !secret wazuh_indexer_search_url$",
            package_text,
            flags=re.MULTILINE,
        )
        if len(resources) != 2:
            self.error(package, f"expected 2 shared REST resources, found {len(resources)}")

        if package_text.count("verify_ssl: true") != 2:
            self.error(package, "both REST resources must enable TLS verification")
        if "verify_ssl: false" in package_text:
            self.error(package, "must not disable TLS verification")
        if package_text.count("timeout: 30") != 2:
            self.error(package, "both REST resources must use the bounded timeout")
        if package_text.count("scan_interval: 120") != 1:
            self.error(package, "expected one 120-second fast resource")
        if package_text.count("scan_interval: 300") != 1:
            self.error(package, "expected one 300-second summary resource")

        unique_ids = set(
            re.findall(r"^\s+unique_id: ([a-z0-9_]+)$", package_text, flags=re.MULTILINE)
        )
        missing_ids = sorted(ADAPTER_UNIQUE_IDS - unique_ids)
        unexpected_ids = sorted(unique_ids - ADAPTER_UNIQUE_IDS)
        if missing_ids:
            self.error(package, f"missing contracted unique IDs: {', '.join(missing_ids)}")
        if unexpected_ids:
            self.error(package, f"unexpected unique IDs: {', '.join(unexpected_ids)}")

        for entity_id in sorted(ADAPTER_RECORDER_EXCLUSIONS):
            if package_text.count(f"- {entity_id}") != 1:
                self.error(package, f"Recorder exclusion must occur once: {entity_id}")

        secret_keys = set(
            re.findall(r"^([a-z0-9_]+):", secrets_text, flags=re.MULTILINE)
        )
        expected_secrets = {
            "wazuh_indexer_password",
            "wazuh_indexer_search_url",
            "wazuh_indexer_username",
        }
        if secret_keys != expected_secrets:
            self.error(secrets, "must define exactly the three documented secret keys")

    def run(self) -> int:
        self.validate_xml()
        self.validate_json_and_scenarios()
        self.validate_python_and_shell()
        self.validate_markdown_links()
        self.validate_collector_checksum()
        self.validate_home_assistant_adapter()

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
