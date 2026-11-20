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
        self.assertIn("if diagnosticsOn { register(", center)
        self.assertIn("if diagnosticsOn { finishDiagnostic(id) }", center)
        active = center.split("func diagnosticActive()", 1)[1].split("func ", 1)[0]
        self.assertNotIn("ledger.snapshot", active)
        self.assertNotIn("detail", active)

    def test_clock_access_is_guarded_and_never_suspends_threads(self):
        center = source("App/Reader/ActivityCenter.swift")
        start = center.split("private func startSegment", 1)[1].split("private func endSegment", 1)[0]
        self.assertLess(start.index("guard diagnosticsOn"), start.index("mach_thread_self()"))
        end = center.split("private func endSegment", 1)[1].split("func snapshot", 1)[0]
        self.assertIn("defer { mach_port_deallocate", end)
        mach = source("Packages/KyokashoKit/Sources/ReaderCore/DiagnosticMachCPU.swift")
        for text in (center, mach, source("App/Settings/DiagnosticCPU.swift")):
            self.assertNotIn("thread_suspend(", text)

    def test_progress_updates_only_the_diagnostic_registry(self):
        center = source("App/Reader/ActivityCenter.swift")
        update = center.split("func updateDiagnostic", 1)[1].split("func endDiagnostic", 1)[0]
        self.assertIn("progress: Progress", update)
        self.assertIn("if diagnosticsOn { diagnosticRunning[id]?.progress = progress }", update)
        self.assertNotIn("ledger", update)
