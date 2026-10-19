#!/usr/bin/env python3

"""Tests for the read-only Wazuh identifier collision checker."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

import check_wazuh_collisions as checker  # noqa: E402


class CollisionCheckerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repository = self.root / "repository"
        self.wazuh = self.root / "var" / "ossec"
        for directory in (
            self.repository / "wazuh" / "rules",
            self.repository / "wazuh" / "decoders",
            self.wazuh / "etc" / "rules",
            self.wazuh / "etc" / "decoders",
            self.wazuh / "ruleset" / "rules",
            self.wazuh / "ruleset" / "decoders",
        ):
            directory.mkdir(parents=True, exist_ok=True)

        (self.repository / checker.SOURCE_FILES["unifi"]["rules"][0]).write_text(
            '<group name="test,"><rule id="100110" level="3" /></group>\n',
            encoding="utf-8",
        )
        (
            self.repository / checker.SOURCE_FILES["unifi"]["decoders"][0]
        ).write_text(
            '<decoder name="unifi-test"><prematch>test</prematch></decoder>\n',
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def check(self, allow_same_file: bool = False) -> checker.Report:
        return checker.check_collisions(
            repository_root=self.repository,
            wazuh_root=self.wazuh,
            source="unifi",
            allow_same_file=allow_same_file,
        )

    def test_clean_installation_passes(self) -> None:
        report = self.check()
        self.assertTrue(report.passed)
        self.assertEqual(2, len(report.candidates))

    def test_different_file_collisions_fail(self) -> None:
        (self.wazuh / "etc" / "rules" / "local_rules.xml").write_text(
            '<group name="local,"><rule id="100110" level="3" /></group>\n',
            encoding="utf-8",
        )
        (self.wazuh / "etc" / "decoders" / "local_decoder.xml").write_text(
            '<decoder name="unifi-test"><prematch>old</prematch></decoder>\n',
            encoding="utf-8",
        )
        report = self.check()
        self.assertFalse(report.passed)
        self.assertEqual(2, len(report.collisions))

    def test_same_custom_filename_requires_explicit_allowance(self) -> None:
        candidate = self.repository / checker.SOURCE_FILES["unifi"]["rules"][0]
        installed = self.wazuh / "etc" / "rules" / candidate.name
        installed.write_text(candidate.read_text(encoding="utf-8"), encoding="utf-8")

        blocked = self.check()
        allowed = self.check(allow_same_file=True)

        self.assertFalse(blocked.passed)
        self.assertTrue(allowed.passed)
        self.assertEqual(1, len(allowed.allowed_same_file))

    def test_builtin_match_is_never_allowed(self) -> None:
        (self.wazuh / "ruleset" / "rules" / "builtin.xml").write_text(
            '<group name="builtin,"><rule id="100110" level="3" /></group>\n',
            encoding="utf-8",
        )
        report = self.check(allow_same_file=True)
        self.assertFalse(report.passed)
        self.assertEqual("builtin", report.collisions[0].installed.scope)

    def test_duplicate_in_same_custom_file_is_never_allowed(self) -> None:
        candidate = self.repository / checker.SOURCE_FILES["unifi"]["rules"][0]
        installed = self.wazuh / "etc" / "rules" / candidate.name
        installed.write_text(
            '<group name="old,">'
            '<rule id="100110" level="3" />'
            '<rule id="100110" level="4" />'
            '</group>\n',
            encoding="utf-8",
        )
        report = self.check(allow_same_file=True)
        self.assertFalse(report.passed)
        self.assertTrue(any("repeats rule 100110" in error for error in report.errors))

    def test_commented_identifiers_are_ignored(self) -> None:
        (self.wazuh / "etc" / "rules" / "commented.xml").write_text(
            '<!-- <rule id="100110" level="3" /> -->\n', encoding="utf-8"
        )
        report = self.check()
        self.assertTrue(report.passed)

    def test_missing_required_tree_fails_closed(self) -> None:
        (self.wazuh / "ruleset" / "decoders").rmdir()
        report = self.check()
        self.assertFalse(report.passed)
        self.assertTrue(
            any("required Wazuh directory is missing" in error for error in report.errors)
        )


if __name__ == "__main__":
    unittest.main()
