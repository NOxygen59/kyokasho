// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import XCTest

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

    func testBoundedTypedFormatAndTopThree() throws {
        let threads: [DiagnosticCPULog.ThreadLoad] = [
            .init(id: 4, percent: 8), .init(id: 0x12345678abcdef01, percent: 91, role: .main),
            .init(id: 3, percent: 10), .init(id: 2, percent: 10), .init(id: 9, percent: .nan), .init(id: 7, percent: 0),
        ]
        XCTAssertEqual(DiagnosticCPULog.topThreads(threads).map(\.id), [0x12345678abcdef01, 2, 3])
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
        XCTAssertTrue(line.contains("total=125.0% fils=[main#abcdef01:91.0%,fil#2:10.0%,fil#3:10.0%]"))
        XCTAssertTrue(line.contains("actifs_omis=1 onglets=6 chargés=1 page=12 zoom=1.25 geste=ocrResize ocr=floating"))
        XCTAssertTrue(line.contains("pageRender:500.0ms@visible:12"))
        XCTAssertTrue(line.contains("longs_omis=4"))
        XCTAssertFalse(line.contains("12345678"))
        XCTAssertFalse(line.contains("\n"))
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
            XCTAssertLessThanOrEqual(value.threads.count, 3)
            XCTAssertGreaterThanOrEqual(value.cost.cpu, 0)
            wall += value.cost.wall
            peak = max(peak, value.cost.wall)
            cpu += value.cost.cpu
        }
        print(String(format: "SONDE MACH Mac n=%d moyenne=%.3f ms max=%.3f ms CPU moyen=%.3f ms", runs, wall * 1000 / Double(runs), peak * 1000, cpu * 1000 / Double(runs)))
    }
}
