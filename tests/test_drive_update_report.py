# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Recette iPad 1.5.6 (6.1) : la vérification des cours Drive dit ce qu'elle compare (le fichier suivi, pas un nom),
signale un renommage en ligne, et un fichier dans la corbeille de Drive ne remplace ni n'efface jamais la copie locale.
Contrôle de la source (réseau Google non testable sur Mac)."""

import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App/Drive"


class DriveUpdateReportTests(unittest.TestCase):
    def test_trashed_file_is_asked_and_never_replaces(self):
        drive = (APP / "GoogleDrive.swift").read_text(encoding="utf-8")
        self.assertIn("md5Checksum,trashed", drive)
        views = (APP / "DriveViews.swift").read_text(encoding="utf-8")
        check = views[views.index("func checkDriveUpdates()"):]
        trashed = check.index("if file.trashed == true {")
        self.assertLess(trashed, check.index("GoogleDrive.shared.download(file)"))
        self.assertIn("continue", check[trashed:check.index("guard file.revision != document.driveRevision")])

    def test_report_explains_what_is_compared(self):
        views = (APP / "DriveViews.swift").read_text(encoding="utf-8")
        self.assertIn("Chaque cours suit son propre fichier Drive (pas son nom)", views)
        self.assertIn("nommé « \\(onlineName) » sur Drive", views)


if __name__ == "__main__":
    unittest.main()
