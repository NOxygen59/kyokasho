// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Darwin
import XCTest
@testable import ReaderCore

final class DiagnosticCPUTests: XCTestCase {
    private let cost = DiagnosticCPULog.Cost(wall: 0.002, cpu: 0.001)

    func testThresholdAndRelativeSpike() {
        var policy = DiagnosticCPULog.Policy()
        XCTAssertTrue(policy.admit(at: 0))
        XCTAssertNil(policy.decide(at: 0, percent: 60, cost: cost, hasLongWork: false))
        XCTAssertTrue(policy.admit(at: 1))
        XCTAssertEqual(policy.decide(at: 1, percent: 61, cost: cost, hasLongWork: false)?.hot, true)
        XCTAssertTrue(policy.admit(at: 2))
        XCTAssertNil(policy.decide(at: 2, percent: 20, cost: cost, hasLongWork: false))
        XCTAssertTrue(policy.admit(at: 3))
        XCTAssertEqual(policy.decide(at: 3, percent: 45, cost: cost, hasLongWork: false)?.spike, true)
    }

    func testFrequencySurvivesRestartAndCombinesSummaryWithAlert() throws {
        var policy = DiagnosticCPULog.Policy()
        for second in 0...30 {
            let time = Double(second)
            XCTAssertTrue(policy.admit(at: time))
            let decision = try XCTUnwrap(policy.decide(at: time, percent: 95, cost: cost, hasLongWork: true))
            XCTAssertEqual(decision.summary != nil, second == 30)
            XCTAssertNil(policy.decide(at: time, percent: 99, cost: cost, hasLongWork: true))
            XCTAssertNil(policy.decide(at: time + 0.125, percent: 95, cost: cost, hasLongWork: true))
            XCTAssertFalse(policy.admit(at: time + 0.125))
        }
        policy.resetWindow()
        XCTAssertFalse(policy.admit(at: 30.5))
        XCTAssertTrue(policy.admit(at: 31))
        XCTAssertNil(policy.decide(at: 31, percent: nil, cost: cost, hasLongWork: false))
    }

    func testQuietSummaryStillReportsCost() throws {
        var policy = DiagnosticCPULog.Policy()
        for second in 0..<30 {
            XCTAssertTrue(policy.admit(at: Double(second)))
            XCTAssertNil(policy.decide(at: Double(second), percent: 12, cost: cost, hasLongWork: false))
        }
        XCTAssertTrue(policy.admit(at: 30))
        let decision = try XCTUnwrap(policy.decide(at: 30, percent: 12, cost: cost, hasLongWork: false))
        let line = DiagnosticCPULog.line(percent: 12, threads: [], active: [], context: .init(), long: .init(), cost: cost, decision: decision)
        XCTAssertTrue(line.contains("résumé n=31 total_moy=12.0% total_max=12.0%"))
        XCTAssertTrue(line.contains("sonde_moy_ms=2.000 sonde_max_ms=2.000 sonde_cpu_moy_ms=1.000"))
    }

    func testBoundedTypedFormatAndHotThreads() throws {
        let threads: [DiagnosticCPULog.ThreadLoad] = [
            .init(id: 4, percent: 8), .init(id: 0x12345678abcdef01, percent: 91, role: .main),
            .init(id: 3, percent: 10), .init(id: 2, percent: 10), .init(id: 9, percent: .nan), .init(id: 7, percent: 0),
        ]
        XCTAssertEqual(DiagnosticCPULog.topThreads(threads).map(\.id), [0x12345678abcdef01, 2, 3, 4])
        var long = DiagnosticCPULog.LongWork()
        long.add(.init(kind: .tone, seconds: 0.100, page: 1))
        XCTAssertTrue(long.entries.isEmpty)
        for page in 0..<12 { long.add(.init(kind: .pageText, seconds: Double(page + 200) / 1000, page: page)) }
        XCTAssertEqual(long.entries.count, 8)
        XCTAssertEqual(long.omitted, 4)
        XCTAssertEqual(long.entries.first?.page, 11)
        var context = DiagnosticCPULog.Context()
        context.tabs = 6; context.loaded = 1; context.page = 12; context.zoom = 1.25; context.gesture = .ocrResize; context.panel = .floating
        var policy = DiagnosticCPULog.Policy()
        XCTAssertTrue(policy.admit(at: 0))
        let decision = try XCTUnwrap(policy.decide(at: 0, percent: 125, cost: cost, hasLongWork: true))
        let active = Array(repeating: DiagnosticCPULog.Work(kind: .pageRender, seconds: 0.5, visiblePage: 12), count: 9)
        let line = DiagnosticCPULog.line(percent: 125, threads: threads, active: active, context: context, long: long, cost: cost, decision: decision)
        XCTAssertTrue(line.contains("total=125.0% fils=[main#12345678abcdef01:91.0%/nom:sans-nom"))
        XCTAssertTrue(line.contains("fil#4:8.0%"))
        XCTAssertTrue(line.contains("actifs_omis=1 onglets=6 chargés=1 page=12 zoom=1.25 geste=ocrResize ocr=floating"))
        XCTAssertTrue(line.contains("pageRender:500.0ms@visible:12"))
        XCTAssertTrue(line.contains("longs_omis=4"))

        XCTAssertFalse(line.contains("\n"))
    }

    func testCPUTimeCombinesActiveAndCompletedSegmentsWithoutDoubleCounting() {
        var cpu = DiagnosticCPULog.CPUTime()
        XCTAssertNil(cpu.seconds { _ in nil })
        XCTAssertTrue(cpu.begin(thread: 11, at: 10))
        XCTAssertFalse(cpu.begin(thread: 11, at: 10.125))
        XCTAssertEqual(cpu.seconds { _ in 10.25 }, 0.25)
        cpu.end(thread: 11, at: 10.5)
        XCTAssertTrue(cpu.begin(thread: 11, at: 20)) // L'attente entre deux segments ne compte pas.
        XCTAssertTrue(cpu.begin(thread: 12, at: 4))
        XCTAssertEqual(cpu.seconds { $0 == 11 ? 20.25 : 4.125 }, 0.875)
        cpu.end(thread: 12, at: nil)
        cpu.end(thread: 11, at: 20.25)
        XCTAssertEqual(cpu.seconds { _ in XCTFail("Aucun segment ouvert"); return nil }, 0.75)
        var idle = DiagnosticCPULog.CPUTime()
        XCTAssertTrue(idle.begin(thread: 11, at: 20))
        XCTAssertNil(idle.seconds { _ in 19 })
        XCTAssertEqual(idle.seconds { _ in 20 }, 0)
    }

    func testProgressFormatDistinguishesUnknownFromZeroCPU() throws {
        let invalid = DiagnosticCPULog.Progress(page: 8, total: 8, stage: .waiting)
        XCTAssertNil(invalid.page)
        var policy = DiagnosticCPULog.Policy()
        XCTAssertTrue(policy.admit(at: 0))
        let decision = try XCTUnwrap(policy.decide(at: 0, percent: 100, cost: cost, hasLongWork: false))
        let active: [DiagnosticCPULog.Work] = [
            .init(kind: .analysis, seconds: 0.5, cpuSeconds: 0.125, progress: .init(page: 0, total: 8, stage: .voting)),
            .init(kind: .aiReading, seconds: 0.375, progress: invalid),
            .init(kind: .ocr, seconds: 0.25, cpuSeconds: 0)
        ]
        let line = DiagnosticCPULog.line(percent: 100, threads: [], active: active, context: .init(), long: .init(), cost: cost, decision: decision)
        XCTAssertTrue(line.contains("analysis:500.0ms@p0/total:8/étape:voting/cpu:125.0ms"))
        XCTAssertTrue(line.contains("aiReading:375.0ms@p?/total:8/étape:waiting/cpu:?"))
        XCTAssertTrue(line.contains("ocr:250.0ms@p?/total:?/étape:?/cpu:0.0ms"))
    }

    func testVLMPhasesUseClosedKindsAndOnlyAnAliasForTheDocument() throws {
        let alias = DiagnosticThreads.Alias()
        let prepare = DiagnosticCPULog.Work(kind: .aiPrepare, seconds: 0.5, document: alias, page: 7)
        let generate = DiagnosticCPULog.Work(kind: .aiGenerate, seconds: 0.25, document: alias, page: 7, cpuSeconds: 0.125)
        var policy = DiagnosticCPULog.Policy()
        XCTAssertTrue(policy.admit(at: 1))
        let decision = try XCTUnwrap(policy.decide(at: 1, percent: 100, cost: cost, hasLongWork: true))
        let segment = DiagnosticThreads.Segment(kind: .aiGenerate, document: alias, page: 7, start: 0)
        var long = DiagnosticCPULog.LongWork()
        long.add(prepare)
        let line = DiagnosticCPULog.line(percent: 100, threads: [.init(id: 1, percent: 100, name: "kyo.aiGenerate")],
                                         active: [generate], context: .init(), long: long, cost: cost, decision: decision,
                                         segments: [1: segment], at: 1)
        XCTAssertTrue(line.contains("actifs=[aiGenerate:250.0ms@p7/total:?/étape:?/cpu:125.0ms/doc:\(alias.label)]"))
        XCTAssertTrue(line.contains("longs=[aiPrepare:500.0ms@p7/total:?/étape:?/cpu:?/doc:\(alias.label)]"))
        XCTAssertTrue(line.contains("/nom:kyo.aiGenerate/file:?/fonction:aiGenerate/doc:\(alias.label)/page:7/"))
        XCTAssertNotNil(alias.label.range(of: "^[0-9a-f]{12}$", options: .regularExpression))
        XCTAssertEqual(DiagnosticCPULog.Kind(rawValue: "aiPrepare"), .aiPrepare)
        XCTAssertEqual(DiagnosticCPULog.Kind(rawValue: "aiGenerate"), .aiGenerate)
        XCTAssertNil(DiagnosticCPULog.Kind(rawValue: "titre privé /chemin"))
    }

    func testMachReadsCPUOnAnotherThreadWithoutSuspendingIt() {
        let started = DispatchSemaphore(value: 0)
        let sampled = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        final class State: @unchecked Sendable {
            // Les sémaphores protègent la publication et l'emprunt du droit.
            var port: thread_t = 0
            var before: TimeInterval?
        }
        let state = State()
        Thread.detachNewThread {
            let port = mach_thread_self()
            defer { mach_port_deallocate(mach_task_self_, port); finished.signal() }
            state.port = port
            state.before = DiagnosticMachCPU.threadCPUSeconds(port)
            let deadline = ProcessInfo.processInfo.systemUptime + 0.02
            while ProcessInfo.processInfo.systemUptime < deadline {}
            started.signal()
            sampled.wait()
        }
        defer { sampled.signal(); XCTAssertEqual(finished.wait(timeout: .now() + 2), .success) }
        guard started.wait(timeout: .now() + 2) == .success else { return XCTFail("Fil de test non prêt") }
        guard let before = state.before, let after = DiagnosticMachCPU.threadCPUSeconds(state.port) else {
            return XCTFail("Compteur Mach indisponible")
        }
        XCTAssertGreaterThan(after, before)
    }

    func testMachProbeAndMeasureHostCost() throws {
        var probe = DiagnosticMachCPU()
        let first = probe.sample(mainID: 0)
        XCTAssertNil(first.percent)
        var wall = 0.0, cpu = 0.0, peak = 0.0
        let runs = 100
        for _ in 0..<runs {
            let value = probe.sample(mainID: 0)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(value.percent), 0)
            XCTAssertLessThanOrEqual(DiagnosticCPULog.topThreads(value.threads).count, DiagnosticThreads.limit)
            XCTAssertGreaterThanOrEqual(value.cost.cpu, 0)
            wall += value.cost.wall
            peak = max(peak, value.cost.wall)
            cpu += value.cost.cpu
        }
        print(String(format: "SONDE MACH Mac n=%d moyenne=%.3f ms max=%.3f ms CPU moyen=%.3f ms", runs, wall * 1000 / Double(runs), peak * 1000, cpu * 1000 / Double(runs)))
    }
}
