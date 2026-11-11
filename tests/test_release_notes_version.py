# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Recette iPad 1.5.5 : la candidate est partie sans notes de version, la fenêtre « Nouveautés » ne s'est pas
affichée. Les notes en cours (`ReleaseNotes.current`) ne doivent jamais être plus anciennes que la version du projet,
et `build_ipa.sh` refuse un paquet dont la version n'a pas ses notes."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INTRO = ROOT / "Packages/KyokashoKit/Sources/ReaderCore/AppIntro.swift"
HISTORY = ROOT / "Packages/KyokashoKit/Sources/ReaderCore/ReleaseHistory.swift"


def version_tuple(text):
    return tuple(int(part) for part in text.split("."))


class ReleaseNotesVersionTests(unittest.TestCase):
    def setUp(self):
        self.marketing = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', (ROOT / "project.yml").read_text()).group(1)
        self.current = re.search(r'public static let current = ReleaseNotes\("([^"]+)"', INTRO.read_text()).group(1)

    def test_current_notes_are_not_older_than_the_project_version(self):
        self.assertGreaterEqual(version_tuple(self.current), version_tuple(self.marketing),
                                f"ReleaseNotes.current ({self.current}) est plus ancien que la version {self.marketing}")

    def test_installed_version_has_notes(self):
        versions = re.findall(r'ReleaseNotes\("(\d+\.\d+\.\d+)"', INTRO.read_text() + HISTORY.read_text())
        self.assertIn(self.marketing, versions, f"aucune note pour la version {self.marketing}")

    def test_versions_are_not_repeated(self):
        versions = re.findall(r'ReleaseNotes\("(\d+\.\d+\.\d+)"', INTRO.read_text() + HISTORY.read_text())
        self.assertEqual(len(versions), len(set(versions)))

    def test_package_script_refuses_a_version_without_notes(self):
        script = (ROOT / "build_ipa.sh").read_text()
        self.assertIn("public static let current = ReleaseNotes(", script)
        self.assertIn('if [[ "$NOTES" != "$VERSION" ]]', script)


if __name__ == "__main__":
    unittest.main()
