# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-DIAG-001, E2a : session du processus branchée sur les notifications de l'application, installée une fois
au lancement après le journal, état hors de Documents et exclu des sauvegardes (archives Mac comprises)."""
import os
import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import backup_container as storage  # noqa: E402


class DiagnosticSessionWiringTests(unittest.TestCase):
    def test_controller_follows_the_process_not_scenes(self):
        ctrl = (ROOT / "App/Settings/DiagnosticSessionController.swift").read_text(encoding="utf-8")
        for name in ("willEnterForegroundNotification", "didBecomeActiveNotification", "willResignActiveNotification",
                     "didEnterBackgroundNotification"):
            self.assertIn(f"UIApplication.{name}", ctrl)
        # Jamais la phase d'une vue, ni la fin d'application comme vérité de session.
        self.assertNotIn("scenePhase", ctrl)
        self.assertNotIn("willTerminate", ctrl)
        # Une assertion par clôture, rendue une fois par elle-même (B1).
        close = ctrl.split("private func close() {", 1)[1].split("\n    }", 1)[0]
        self.assertIn("let assertion = BackgroundAssertion()", close)
        self.assertIn("{ assertion.end() }", close)
        self.assertIn("guard id != .invalid else { return }", ctrl)
        # L'automate n'adopte l'état qu'après une écriture réussie (B2).
        self.assertIn("file.write(state) {\n                machine.commit(state)", ctrl)
        # Exclusion de la sauvegarde confirmée avant tout usage du fichier (B4).
        install = ctrl.split("func install() {", 1)[1]
        self.assertLess(install.index("guard Self.excludeFromBackup(folder) else {"), install.index("DiagnosticSessionFile(folder: folder)"))
        self.assertIn(".isExcludedFromBackup == true", ctrl)
        # Hors Documents, exclu de la sauvegarde système.
        self.assertIn("applicationSupportDirectory", ctrl)
        self.assertNotIn("documentDirectory", ctrl)
        self.assertIn("values.isExcludedFromBackup = true", ctrl)
        # Consommation du lancement avant toute transition (même file série).
        install = ctrl.split("func install() {", 1)[1]
        self.assertLess(install.index("file.consumeAtLaunch(now: Date())"), install.index("addObserver"))

    def test_installed_once_after_the_journal_and_before_the_restore(self):
        app = (ROOT / "App/KyokashoApp.swift").read_text(encoding="utf-8")
        start = app.index("Diagnostics.start()")
        install = app.index("DiagnosticSessionController.shared.install()")
        restore = app.index("LibraryBackupService.applyPendingRestoreOnce()")
        self.assertLess(start, install)
        self.assertLess(install, restore)
        self.assertEqual(app.count("DiagnosticSessionController.shared.install()"), 1)

    def test_mac_container_tool_never_copies_the_session_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            state = root / "Library/Application Support/KyokashoDiagnosticState"
            state.mkdir(parents=True)
            (state / "session.json").write_text("{}")
            (root / "Documents").mkdir()
            (root / "Documents/a.txt").write_text("x")
            files, omitted = storage.inventory(root)
            self.assertNotIn("Library/Application Support/KyokashoDiagnosticState/session.json", files)
            self.assertIn("Library/Application Support/KyokashoDiagnosticState", omitted)
            self.assertIn("Documents/a.txt", files)


if __name__ == "__main__":
    unittest.main()
