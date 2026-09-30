#!/usr/bin/env python3
"""Run repository samples through Wazuh and compare them with expected.json."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


FIELD_NAMES = (
    "srcip",
    "dstip",
    "srcport",
    "dstport",
    "protocol",
    "action",
    "dstuser",
    "srcuser",
    "storage_device",
)


@dataclass
class EventResult:
    raw: str
    decoder: str | None
    fields: dict[str, str]
    rule: int | None


def parse_args() -> argparse.Namespace:
    repository = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Run Wazuh sample scenarios and compare output with expected.json."
    )
    parser.add_argument(
        "--samples",
        type=Path,
        default=repository / "samples",
        help="Samples directory (default: repository samples/).",
    )
    parser.add_argument(
        "--logtest-bin",
        type=Path,
        default=Path("/var/ossec/bin/wazuh-logtest-legacy"),
        help="Path to the Wazuh 4.14.8 wazuh-logtest-legacy binary.",
    )
    parser.add_argument(
        "--wazuh-root",
        type=Path,
        default=Path("/var/ossec"),
        help="Wazuh root passed to logtest with -D.",
    )
    parser.add_argument(
        "--config",
        default="etc/ossec.conf",
        help="Configuration path passed to logtest with -c.",
    )
    parser.add_argument(
        "--json-report",
        type=Path,
        help="Optionally write the complete result summary as JSON.",
    )
    return parser.parse_args()


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def parse_logtest_output(output: str) -> list[EventResult]:
    events: list[EventResult] = []
    for block in output.split("**Phase 1: Completed pre-decoding.")[1:]:
        raw_match = re.search(r"full event: '([^']*)'", block)
        decoder_match = re.search(r"decoder: '([^']*)'", block)
        phase_two = block.split("**Phase 3:", 1)[0]
        decoder = decoder_match.group(1) if decoder_match else None
        if "No decoder matched." in phase_two:
            decoder = None

        field_pattern = (
            r"^       (" + "|".join(FIELD_NAMES) + r"): '([^']*)'"
        )
        fields = dict(re.findall(field_pattern, block, flags=re.MULTILINE))
        rule_match = re.search(r"Rule id: '(\d+)'", block)
        events.append(
            EventResult(
                raw=raw_match.group(1) if raw_match else "",
                decoder=decoder,
                fields=fields,
                rule=int(rule_match.group(1)) if rule_match else None,
            )
        )
    return events


def normalized_fields(fields: dict[str, Any]) -> dict[str, str]:
    return {key.rsplit(".", 1)[-1]: str(value) for key, value in fields.items()}


def event_matches(event: EventResult, expected: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    decoder = expected.get("decoder")
    if decoder and event.decoder != decoder:
        errors.append(f"decoder expected {decoder!r}, got {event.decoder!r}")

    for key, value in normalized_fields(expected.get("fields", {})).items():
        actual = event.fields.get(key)
        if actual != value:
            errors.append(f"field {key} expected {value!r}, got {actual!r}")

    expected_rules = expected.get("rules", [])
    if expected_rules and event.rule not in expected_rules:
        errors.append(f"rule expected one of {expected_rules}, got {event.rule!r}")
    return errors


def compare_array(events: list[EventResult], expected: list[dict[str, Any]]) -> list[str]:
    failures: list[str] = []
    for index, item in enumerate(expected, start=1):
        contains = item.get("contains", "")
        candidates = [event for event in events if contains in event.raw]
        if not candidates:
            failures.append(f"expectation {index}: no event contains {contains!r}")
            continue

        candidate_errors = [event_matches(event, item) for event in candidates]
        if not any(not errors for errors in candidate_errors):
            detail = "; ".join(candidate_errors[0])
            failures.append(f"expectation {index} ({contains!r}): {detail}")
    return failures


def compare_object(events: list[EventResult], expected: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    decoder = expected.get("decoder")
    if decoder:
        wrong = [event.decoder for event in events if event.decoder != decoder]
        if wrong:
            failures.append(f"decoder expected {decoder!r} for all events, got {wrong!r}")

    fields = normalized_fields(expected.get("fields", {}))
    for key, value in fields.items():
        if not events or any(event.fields.get(key) != value for event in events):
            actual = sorted(
                {event.fields.get(key) for event in events},
                key=lambda item: "" if item is None else str(item),
            )
            failures.append(f"field {key} expected {value!r}, got {actual!r}")

    actual_rules = {event.rule for event in events if event.rule is not None}
    for rule in expected.get("rules_expected", []):
        if rule not in actual_rules:
            failures.append(
                f"expected rule {rule} was not generated; actual rules: {sorted(actual_rules)}"
            )
    return failures


def scenario_metadata(directory: Path) -> dict[str, Any]:
    metadata_path = directory / "scenario.json"
    if metadata_path.exists():
        return load_json(metadata_path)
    return {"classification": "pass"}


def run_scenario(
    expected_path: Path, args: argparse.Namespace
) -> dict[str, Any]:
    directory = expected_path.parent
    name = str(directory.relative_to(args.samples)) or "."
    metadata = scenario_metadata(directory)
    classification = metadata.get("classification", "pass")
    raw_path = directory / "raw.log"

    result: dict[str, Any] = {
        "scenario": name,
        "classification": classification,
        "summary": metadata.get("summary", ""),
    }

    if classification == "pending":
        result.update(status="PENDING", details=[metadata.get("reason", "missing input")])
        return result

    if not raw_path.exists():
        result.update(status="PENDING", details=["raw.log is missing"])
        return result

    command = [
        str(args.logtest_bin),
        "-D",
        str(args.wazuh_root),
        "-c",
        args.config,
    ]
    completed = subprocess.run(
        command,
        input=raw_path.read_text(encoding="utf-8"),
        text=True,
        capture_output=True,
        check=False,
    )
    output = completed.stdout + completed.stderr
    events = parse_logtest_output(output)
    expected = load_json(expected_path)

    failures = (
        compare_array(events, expected)
        if isinstance(expected, list)
        else compare_object(events, expected)
    )
    if completed.returncode != 0:
        failures.insert(0, f"logtest exited with status {completed.returncode}")
    if not events:
        failures.append("logtest returned no parsed events")

    if failures:
        status = "FAIL"
    elif classification == "known_fail":
        status = "XPASS"
        failures = ["known failure now passes; review production fix and scenario metadata"]
    else:
        status = "PASS"

    result.update(
        status=status,
        details=failures,
        actual_rules=[event.rule for event in events],
        actual_decoders=[event.decoder for event in events],
    )
    return result


def main() -> int:
    args = parse_args()
    if not args.logtest_bin.is_file():
        print(f"ERROR: logtest binary not found: {args.logtest_bin}", file=sys.stderr)
        return 2
    if not args.samples.is_dir():
        print(f"ERROR: samples directory not found: {args.samples}", file=sys.stderr)
        return 2

    results = [
        run_scenario(path, args)
        for path in sorted(args.samples.rglob("expected.json"))
    ]

    for result in results:
        annotation = " [KNOWN PRODUCTION BUG]" if result["classification"] == "known_fail" else ""
        print(f"{result['status']:7} {result['scenario']}{annotation}")
        for detail in result.get("details", []):
            print(f"        - {detail}")

    counts = {
        status: sum(result["status"] == status for result in results)
        for status in ("PASS", "FAIL", "PENDING", "XPASS")
    }
    print(
        "\nSummary: "
        + ", ".join(f"{key}={value}" for key, value in counts.items())
    )

    if args.json_report:
        args.json_report.write_text(
            json.dumps(results, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    return 1 if counts["FAIL"] or counts["XPASS"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
