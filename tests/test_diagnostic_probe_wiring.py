# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""PLAN-DIAG-001 E2e : câblage de la sonde du fil principal (la logique est testée dans DiagnosticKitTests)."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class DiagnosticProbeWiringTests(unittest.TestCase):
    def setUp(self):
        self.monitor = source("App/Settings/DiagnosticMainThreadMonitor.swift")

    def test_probe_runs_only_in_diagnostic_mode_and_while_active(self):
        # Réglage manuel seulement : jamais la fenêtre de détail automatique E2b seule (contrat E2e).
        self.assertIn("let enabled = Diagnostics.enabled\n", self.monitor)
        self.assertNotIn("detailEnabled", self.monitor)
        self.assertIn("shared.configure(running: enabled && UIApplication.shared.applicationState == .active)", self.monitor)
        self.assertIn("guard running, Diagnostics.enabled else {", self.monitor)
        self.assertIn("UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification", self.monitor)
        self.assertIn("didBecomeActiveNotification", self.monitor)
        self.assertIn("DiagnosticMainThreadMonitor.updateActivation()", source("App/KyokashoApp.swift"))
        self.assertIn("DiagnosticMainThreadMonitor.updateActivation()", source("App/Settings/Diagnostics.swift"))

    def test_one_request_in_flight_and_stale_answers_dropped(self):
        beat = self.monitor.split("private func beat()", 1)[1]
        self.assertLess(beat.index("probe.tick(at: now)"), beat.index("guard !inFlight, Diagnostics.enabled else { return }"))
        self.assertLess(beat.index("guard !inFlight, Diagnostics.enabled else { return }"), beat.index("DispatchQueue.main.async"))
        # Seule la réponse libère la place, quelle que soit sa génération ; une réponse ancienne n'est pas mesurée.
        self.assertLess(beat.index("inFlight = false"), beat.index("guard current == generation, timer != nil, Diagnostics.enabled else { return }"))
        configure = self.monitor.split("private func configure", 1)[1].split("private func beat", 1)[0]
        self.assertIn("generation &+= 1", configure)
        self.assertIn("probe.rearm()", configure)
        self.assertNotIn("inFlight", configure)

    def test_manual_mode_checked_at_send_and_at_write_and_no_injection(self):
        beat = self.monitor.split("private func beat()", 1)[1]
        self.assertIn("guard !inFlight, Diagnostics.enabled else { return }", beat)
        self.assertIn("guard current == generation, timer != nil, Diagnostics.enabled else { return }", beat)
        self.assertIn("Diagnostics.manualOnly(event)", beat)
        self.assertNotIn("DiagnosticCenter.shared.emit", self.monitor)
        manual = source("App/Settings/Diagnostics.swift").split("static func manualOnly", 1)[1].split("}", 1)[0]
        self.assertIn("diagnosticOnly: true", manual)
        for forbidden in ("usleep", "debug.diag", "asyncAfter"):
            self.assertNotIn(forbidden, self.monitor)

    def test_main_thread_only_reads_clocks_no_sync_write_or_uikit_capture(self):
        main_block = self.monitor.split("private func beat()", 1)[1].split("DispatchQueue.main.async { [self] in", 1)[1].split("queue.async", 1)[0]
        self.assertEqual(main_block.strip(), "let answered = DiagnosticMainThreadProbe.Instant.now()")
        for forbidden in ("sync: true", "DispatchQueue.main.sync", "snapshotView", "drawHierarchy", "Thread.callStackSymbols"):
            self.assertNotIn(forbidden, self.monitor)


if __name__ == "__main__":
    unittest.main()
