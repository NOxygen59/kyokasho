# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class DiagnosticCPUWiringTests(unittest.TestCase):
    def test_timer_and_sampling_require_diagnostic_mode(self):
        cpu = source("App/Settings/DiagnosticCPU.swift")
        self.assertIn("running: enabled && UIApplication", cpu)
        self.assertIn("if running, Diagnostics.enabled {", cpu)
        self.assertIn("didEnterBackgroundNotification", cpu)
        tick = cpu.split("private func tick", 1)[1]
        self.assertLess(tick.index("guard Diagnostics.enabled else { return }"), tick.index("sampler.sample("))
        self.assertLess(tick.index("policy.admit"), tick.index("sampler.sample("))
        self.assertLess(tick.index("policy.decide"), tick.index("Diagnostics.logCPU("))

    def test_cpu_writes_use_the_guarded_journal(self):
        journal = source("App/Settings/Diagnostics.swift")
        self.assertIn('write(message, area: "cpu", diagnosticOnly: true)', journal)
        self.assertIn("guard !diagnosticOnly || enabled else { return }", journal)
        self.assertIn(".onChange(of: enabled) { _ in DiagnosticCPU.updateActivation() }", journal)
        self.assertIn("DiagnosticCPU.updateActivation()", source("App/Settings/EnergyMeter.swift"))

    def test_activity_snapshot_does_not_consume_monitor_ledger_or_details(self):
        center = source("App/Reader/ActivityCenter.swift")
        self.assertIn("if Diagnostics.enabled { diagnosticRunning", center)
        self.assertIn("if let observed = diagnosticRunning.removeValue(forKey: id), Diagnostics.enabled", center)
        active = center.split("func diagnosticActive()", 1)[1].split("func ", 1)[0]
        self.assertNotIn("ledger.snapshot", active)
        self.assertNotIn("detail", active)
