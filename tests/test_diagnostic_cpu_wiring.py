# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

from pathlib import Path
import re
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
        self.assertNotRegex(mach, r"\.dispatch_qaddr\b")
        self.assertIn("pthread_threadid_np(nil, &thread)", start)
        self.assertIn("diagnosticThreads.pop(token, thread: segment.thread)", end)
        self.assertIn("segment.restoreName?()", end)

    def test_g1_joins_the_same_mach_identity_and_uses_a_closed_event_history(self):
        cpu = source("App/Settings/DiagnosticCPU.swift")
        tick = cpu.split("private func tick", 1)[1]
        self.assertLess(tick.index("sampler.sample("), tick.index("threadHistory.observe("))
        self.assertLess(tick.index("let cutoff = Date()"), tick.index("sampler.sample("))
        self.assertIn("DiagnosticThreads.recentCategories(Diagnostics.tail().lines, before: cutoff)", tick)
        self.assertIn("shown + persistent.map { $0.load.id }", tick)
        self.assertIn('"cpu-persistant")', tick)
        mach = source("Packages/KyokashoKit/Sources/ReaderCore/DiagnosticMachCPU.swift")
        self.assertIn(".init(id: info.thread_id,", mach)

    def test_g1_wires_packages_and_names_only_synchronous_segments(self):
        center = source("App/Reader/ActivityCenter.swift")
        self.assertIn("DiagnosticThreadHook.install(on ? hook : nil)", center)
        self.assertIn("DiagnosticThreadHook.restoreNameAfterSetting(observed.kind)", center)
        hook = source("Packages/KyokashoKit/Sources/ReaderCore/DiagnosticThreadHook.swift")
        measure = hook.split("public static func measure", 1)[1].split("public static func withContext", 1)[0]
        self.assertIn("defer { end?() }", measure)
        self.assertNotRegex(measure, r"\b(?:await|async)\b")
        for path, marker in (
            ("App/Library/DocumentScan.swift", "renderKind: .ovisRender"),
            ("App/Reader/ReaderController.swift", "measureDiagnostic(.readerBuild"),
            ("App/Reader/ReaderController+PageLayout.swift", "measureDiagnostic(.autoCrop"),
            ("App/Reader/ReaderController+OCR.swift", "measureDiagnostic(.readerClose"),
            ("App/Study/StudyPanel.swift", "measureDiagnostic(.neuralLayout"),
            ("Packages/KyokashoKit/Sources/OCRKit/OCRService.swift", "withContext(documentID: documentId, page: pageIndex)"),
            ("Packages/KyokashoKit/Sources/OCRKit/OCREngines.swift", "measure(.pdfRelease"),
            ("Packages/KyokashoKit/Sources/OCRKit/OCREngines.swift", "measure(.pdfProbe"),
            ("Packages/KyokashoKit/Sources/OCRKit/OCREngines.swift", "measure(.vision"),
            ("Packages/KyokashoKit/Sources/ONNXOCRKit/ONNXEngines.swift", "measure(.onnxSession"),
            ("Packages/KyokashoKit/Sources/ONNXOCRKit/ONNXEngines.swift", "measure(.onnxRun"),
        ):
            with self.subTest(path=path, marker=marker):
                self.assertIn(marker, source(path))

    def test_progress_updates_only_the_diagnostic_registry(self):
        center = source("App/Reader/ActivityCenter.swift")
        update = center.split("func updateDiagnostic", 1)[1].split("func endDiagnostic", 1)[0]
        self.assertIn("progress: Progress", update)
        self.assertIn("if diagnosticsOn { diagnosticRunning[id]?.progress = progress }", update)
        self.assertNotIn("ledger", update)

    def test_ai_scan_uses_the_job_diagnostic_and_closes_it_on_exit(self):
        center = source("App/Reader/AITaskCenter.swift")
        run = center.split("    func run(", 1)[1].split("    func setProgress(", 1)[0]
        self.assertIn("diagnosticKind: ActivityCenter.Kind? = nil", run)
        self.assertRegex(run, r"else \{ return false \}\s+let diagnosticID = diagnosticKind\.flatMap")
        self.assertLess(run.index("beginDiagnostic("), run.index("jobs.append(job)"))
        self.assertIn("diagnosticID: diagnosticID)", run)
        self.assertRegex(run, r"Task \{ \[weak self\] in\s+defer \{ ActivityCenter.shared.endDiagnostic\(job.diagnosticID\) \}")
        scan = source("App/Library/DocumentScan.swift")
        self.assertIn("diagnosticKind: .aiReading", scan)
        self.assertIn("let cpuID = center.jobs.first { $0.id == job }?.diagnosticID", scan)
        for page, stage, work in (("", "waiting", "while center.jobs.contains"),
                                  ("page: page, ", "aiReading", "let budget = await"),
                                  ("page: page, ", "saving", "try ActivityCenter.shared.measure(activity: cpuID)")):
            update = f"updateDiagnostic(cpuID, progress: .init({page}total: document.pageCount, stage: .{stage}))"
            self.assertLess(scan.index(update), scan.index(work))

    def test_analysis_tasks_publish_source_page_and_close_on_exit(self):
        analysis = source("App/Library/DocumentAnalysisService.swift")
        for function, initial, stages in (
            ("start", "ocr", (("p", "ocr"), ("p", "aiReading"), ("p", "voting"))),
            ("translateAll", "translation", (("p", "translation"),)),
            ("applyOvisToDocument", "corrections", (("source", "corrections"),)),
        ):
            with self.subTest(function=function):
                body = analysis.split(f"    func {function}(", 1)[1].split("\n    }", 1)[0]
                opening = (f"let cpuID = ActivityCenter.shared.beginDiagnostic(.analysis, "
                           f"progress: .init(total: document.pageCount, stage: .{initial}))")
                self.assertRegex(body, r"Task \{ \[weak self\] in\s+" + re.escape(opening)
                                 + r"\s+defer \{ ActivityCenter\.shared\.endDiagnostic\(cpuID\) \}")
                for page, stage in stages:
                    update = (f"updateDiagnostic(cpuID, progress: .init(page: {page}, "
                              f"total: document.pageCount, stage: .{stage}))")
                    self.assertRegex(body, r"guard !Task\.isCancelled[^\n]*\n\s+ActivityCenter\.shared\."
                                     + re.escape(update))

    def test_reader_ocr_scopes_only_the_service_calls(self):
        ocr = source("App/Reader/ReaderController+OCR.swift")
        selected = ocr.split("    func selectedOCR(", 1)[1].split("\n    }", 1)[0]
        run = ocr.split("    func runOCR(", 1)[1].split("\n    }", 1)[0]
        for body, owner, service, count in ((selected, "", "model.ocr", 1), (run, "reader.", "service", 2)):
            opening = (f"let cpuID = ActivityCenter.shared.beginDiagnostic(.ocr, "
                       f"progress: .init(page: source, total: {owner}document.pageCount, stage: .ocr))")
            scoped_call = (re.escape(opening) + r"\s+defer \{ ActivityCenter\.shared\.endDiagnostic\(cpuID\) \}"
                           + r"\s+let page = try await " + re.escape(f"{service}.page("))
            self.assertEqual(body.count("beginDiagnostic("), count)
            self.assertEqual(len(re.findall(scoped_call, body)), count)
        self.assertIn("progress: .init(page: source, total: total, stage: .pdfText)", ocr)
        display = source("App/Reader/ReaderController+Display.swift")
        self.assertEqual(len(re.findall(r"measure\(\.\w+, page: (page|source), progress: \.init\(total: total\)", display)), 5)

    def test_cpu_measures_do_not_enclose_await(self):
        for path, count in (("Library/DocumentScan", 1), ("Library/DocumentAnalysisService", 3),
                            ("Reader/ReaderController+OCR", 1), ("Reader/ReaderController+Display", 5)):
            with self.subTest(path=path):
                swift = source(f"App/{path}.swift")
                calls = list(re.finditer(r"ActivityCenter\.shared\.measure\s*\(", swift))
                self.assertEqual(len(calls), count)
                for call in calls:
                    # Accolades imbriquées, que la fermeture soit passée en argument ou en suffixe.
                    opening = swift.index("{", call.end())
                    depth = 1
                    for brace in re.finditer(r"[{}]", swift[opening + 1:]):
                        depth += 1 if brace[0] == "{" else -1
                        if depth == 0:
                            self.assertNotRegex(swift[call.end():opening + 1 + brace.start()], r"\bawait\b")
                            break
                    self.assertEqual(depth, 0, "Fermeture de mesure introuvable")

    def test_only_expected_sync_work_is_measured_for_long_tasks(self):
        scan = source("App/Library/DocumentScan.swift")
        analysis = source("App/Library/DocumentAnalysisService.swift")
        self.assertRegex(scan, r"try ActivityCenter\.shared\.measure\(activity: cpuID\) \{\s+try DocumentAITextStore\.write\(text,")
        for value in ("text", "translated"):
            self.assertRegex(analysis, r"try\? ActivityCenter\.shared\.measure\(activity: cpuID\) \{\s+"
                             + re.escape(f"try DocumentAITextStore.write({value},"))
        self.assertRegex(analysis, r"await Task\.detached\(priority: \.userInitiated\) \{\s+"
                         r"ActivityCenter\.shared\.measure\(activity: cpuID\) \{\s+OCRReferenceDiff\.suggestions\(")
