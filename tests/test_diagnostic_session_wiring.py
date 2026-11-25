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
        self.assertIn("if let early, early.id != .invalid { assertion = early } else { assertion = BackgroundAssertion.begin() }", close)
        # Demandée tôt, sans clore, à willResignActive (B1).
        resign = ctrl.split("UIApplication.willResignActiveNotification", 1)[1].split("},", 1)[0]
        self.assertIn("BackgroundAssertion.begin()", resign)
        self.assertNotIn(".background", resign)
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

    def test_detail_window_never_touches_the_manual_setting_or_monitors(self):
        # E2b (DEC-02 B) : détail du journal = manuel OU fenêtre ; réglage inchangé ; CPU, relevé, sonde sur le manuel.
        core = (ROOT / "App/Settings/Diagnostics.swift").read_text(encoding="utf-8")
        self.assertIn("let automatic = DiagnosticCenter.shared.autoDetailActive", core)
        self.assertIn("return enabled || automatic", core)
        log = core.split("static func log(", 1)[1].split("\n    }", 1)[0]
        self.assertIn("guard detailEnabled else { return }", log)
        self.assertNotIn("forKey: enabledKey)", core.replace("UserDefaults.standard.bool(forKey: enabledKey)", ""))
        cpu = (ROOT / "App/Settings/DiagnosticCPU.swift").read_text(encoding="utf-8")
        self.assertNotIn("detailEnabled", cpu)
        self.assertNotIn("autoDetail", (ROOT / "App/Settings/EnergyMeter.swift").read_text(encoding="utf-8"))
        # B1 : en automatique, jamais de lecture mémoire (task_info) dans measure.
        measure = core.split("static func measure<T>(", 1)[1].split("\n    }\n", 1)[0]
        for line in measure.splitlines():
            if "footprintMB()" in line and "log(" in line:
                self.assertIn("enabled ?", line)
        # B3 : la navigation ne nourrit que le contexte CPU, réservé au mode manuel.
        nav = (ROOT / "App/Reader/ReaderController+Navigation.swift").read_text(encoding="utf-8")
        self.assertIn("if changed, !rebuilding, Diagnostics.enabled {", nav)
        ctrl = (ROOT / "App/Settings/DiagnosticSessionController.swift").read_text(encoding="utf-8")
        self.assertIn("DiagnosticCenter.shared.setAutoDetail(launch.detail)", ctrl)
        self.assertIn("DiagnosticSessionMachine(lastGeneration: launch.lastGeneration, detail: launch.detail)", ctrl)

    def test_tracked_work_and_single_memory_observer(self):
        # E2c : travaux suivis aux bornes begin/end, publiés hors verrou ; jamais `detail` dans la projection.
        center = (ROOT / "App/Reader/ActivityCenter.swift").read_text(encoding="utf-8")
        begin = center.split("func begin(_ kind: Kind, detail: String?", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("return (projection, tracked.op(for: id))", begin)
        self.assertNotIn("entries.last", begin)
        ctrl0 = (ROOT / "App/Settings/DiagnosticSessionController.swift").read_text(encoding="utf-8")
        update = ctrl0.split("func updateOngoing(", 1)[1].split("\n    private let pendingLock", 1)[0]
        # B3 : adoptée avant (et indépendamment de) l'écriture ; B4 : coalescée.
        self.assertLess(update.index("machine.commit(ongoing: latest)"), update.index("file.write(state)"))
        self.assertIn("return first", update)
        self.assertIn('"travail_connu_alerte_memoire"', ctrl0)
        self.assertLess(begin.index("lock.withLock"), begin.index("DiagnosticSessionController.shared.updateOngoing(published)"))
        end = center.split("    func end(_ id: UUID) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("return tracked.end(id)", end)
        # Un seul observateur mémoire, au niveau du processus, mémoire relevée avant les libérations.
        app = (ROOT / "App/KyokashoApp.swift").read_text(encoding="utf-8")
        self.assertNotIn(".onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification))", app)
        self.assertIn("DiagnosticSessionController.shared.installMemoryObserver { [weak model] in", app)
        ctrl = (ROOT / "App/Settings/DiagnosticSessionController.swift").read_text(encoding="utf-8")
        observer = ctrl.split("func installMemoryObserver(", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("guard memoryObserver == nil else { return }", observer)
        self.assertLess(observer.index("Diagnostics.footprintMB()"), observer.index("release()"))
        self.assertIn("footprint > 0 ? footprint : nil", observer)

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
