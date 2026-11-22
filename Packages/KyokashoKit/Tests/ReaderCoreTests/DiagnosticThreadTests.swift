// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Darwin
import Foundation
import XCTest
@testable import ReaderCore

final class DiagnosticThreadTests: XCTestCase {
    func testFilteredNamesAndThreadCeiling() throws {
        typealias Load = DiagnosticCPULog.ThreadLoad
        let loads = (1...14).reversed().map { Load(id: UInt64($0), percent: 5, name: "titre privé\n", queue: "a/b") }
            + [Load(id: 90, percent: 4.99), Load(id: 91, percent: .infinity)]
        XCTAssertEqual(DiagnosticCPULog.topThreads(loads).map(\.id), Array(1...12).map(UInt64.init))
        XCTAssertEqual(DiagnosticThreads.safeName("A-b_1.c"), "A-b_1.c")
        let long = String(repeating: "a", count: 41)
        XCTAssertEqual(DiagnosticThreads.safeName(long)?.count, 40)
        for name in ["", "/path", "two words", "[zone]", "日本", "safe\0suffix", long + "\n"] {
            XCTAssertNil(DiagnosticThreads.safeName(name))
        }
        let alias = DiagnosticThreads.Alias()
        let segment = DiagnosticThreads.Segment(kind: .pdfProbe, document: alias, page: 4, start: 7)
        XCTAssertNotEqual(alias.label, DiagnosticThreads.Alias().label)
        let cost = DiagnosticCPULog.Cost(wall: 0.001, cpu: 0.0005)
        var history = DiagnosticThreads.History()
        let observed = history.observe(loads, at: 8) { [] }
        var policy = DiagnosticCPULog.Policy()
        XCTAssertTrue(policy.admit(at: 8))
        let decision = try XCTUnwrap(policy.decide(at: 8, percent: 125, cost: cost, hasLongWork: false))
        let line = DiagnosticCPULog.line(percent: 125, threads: loads, active: [], context: .init(), long: .init(),
                                         cost: cost, decision: decision, observations: observed, segments: [1: segment],
                                         at: 8, previousTick: cost)
        XCTAssertTrue(line.contains("fil#1:5.0%/nom:sans-nom/file:?/fonction:pdfProbe/doc:\(alias.label)/page:4/segment_s:1.0/âge_s:0.0/moy10s:?%"))
        XCTAssertTrue(line.contains("fils_omis=2"))
        XCTAssertTrue(line.contains("tick_préc_ms=1.000 tick_préc_cpu_ms=0.500"))
        XCTAssertFalse(line.contains("titre privé"))
        XCTAssertFalse(line.contains("a/b"))
        XCTAssertFalse(line.contains("fil#d:"))
    }

    func testAgeFromColdSampleAndTenSecondCPUWindow() throws {
        var history = DiagnosticThreads.History()
        for t in 0...11 {
            let value = history.observe([.init(id: 7, percent: t == 0 ? 0 : 5,
                                               cpuSeconds: Double(max(0, t - 1)) / 4)], at: Double(t)) { [] }
            if t == 0 { XCTAssertTrue(value.isEmpty) }
            if t == 11 {
                let thread = try XCTUnwrap(value.first)
                XCTAssertEqual(thread.age, 11)
                XCTAssertEqual(try XCTUnwrap(thread.average), 25, accuracy: 0.00001)
            }
        }
        let partial = history.observe([.init(id: 7, percent: 5, cpuSeconds: 3)], at: 12.5) { [] }
        XCTAssertEqual(try XCTUnwrap(partial.first?.average), 26.25, accuracy: 0.00001)
        _ = history.observe([], at: 13.5) { [] }
        let new = try XCTUnwrap(history.observe([.init(id: 7, percent: 5)], at: 14.5) { [] }.first)
        XCTAssertEqual(new.age, 0)
        XCTAssertNil(new.average)
    }

    func testPersistentThresholdContinuityThrottleAndOmittedThreads() throws {
        var history = DiagnosticThreads.History()
        var reads = 0
        let ids = 1...13
        for t in 0...85 {
            if t == 5 { history.interrupt() }
            let loads = ids.map { DiagnosticCPULog.ThreadLoad(id: UInt64($0), percent: t == 5 || t == 17 ? 79.99 : 80) }
            let observations = history.observe(loads, at: Double(t)) {
                reads += 1
                return [.app, .lecteur, .ocr, .scan]
            }
            let reports = observations.filter { $0.events != nil }
            // Chaleur continue à t=6, premier signal à t=17 exclu car le fil refroidit alors.
            if t == 29 {
                XCTAssertEqual(reports.count, ids.count)
                let last = try XCTUnwrap(reports.last)
                XCTAssertEqual(last.events, [.lecteur, .ocr, .scan])
                XCTAssertTrue(DiagnosticCPULog.persistentLine(last, segment: nil, at: Double(t))
                    .contains("/fonction:inconnue/âge_s:29.0 événements=[lecteur,ocr,scan]"))
            } else { XCTAssertTrue(reports.isEmpty, "t=\(t)") }
        }
        XCTAssertEqual(reads, 1)
        for t in 86...89 {
            let observations = history.observe([.init(id: 1, percent: 80)], at: Double(t)) { [] }
            XCTAssertEqual(observations.first?.events != nil, t == 89)
        }
    }

    func testJournalUsesPriorCategoriesNotPayloadsOrCPUSamples() {
        let start = Date(timeIntervalSince1970: 100)
        func line(_ zone: String, _ offset: TimeInterval) -> String {
            DiagnosticFiles.journalLine(.info, area: zone, message: "texte /chemin [ocr]", at: start + offset,
                                        timeZone: TimeZone(secondsFromGMT: 0)!)
        }
        let lines = [line("app", 0), line("ocr", 4), line("lecteur", 2), line("zone privée", 3),
                     line("cpu", 4.2), line("cpu-persistant", 4.3), line("analyse", 5), "ligne coupée"]
        XCTAssertEqual(DiagnosticThreads.recentCategories(lines, before: start + 5), [.lecteur, .autre, .ocr])
    }

    func testNestedScopeRestoresNameAndRegistryEvenOnError() throws {
        enum Fault: Error { case expected }
        let key: UInt64 = 42
        var registry = DiagnosticThreads.Registry()
        func name() -> String {
            var buffer = [CChar](repeating: 0, count: 64)
            XCTAssertEqual(pthread_getname_np(pthread_self(), &buffer, buffer.count), 0)
            return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        }
        func measure(_ kind: DiagnosticCPULog.Kind, _ work: () throws -> Void) throws {
            let restore = try XCTUnwrap(DiagnosticThreadHook.restoreNameAfterSetting(kind))
            let token = registry.push(.init(kind: kind, document: nil, page: nil, start: 0), thread: key)
            defer { registry.pop(token, thread: key); restore() }
            try work()
        }
        let original = name()
        try measure(.readerBuild) {
            XCTAssertThrowsError(try measure(.pdfProbe) {
                XCTAssertEqual(name(), "kyo.pdfProbe")
                XCTAssertEqual(registry.current(thread: key)?.kind, .pdfProbe)
                XCTAssertNil(registry.current(thread: key + 1))
                throw Fault.expected
            })
            XCTAssertEqual(name(), "kyo.readerBuild")
            XCTAssertEqual(registry.current(thread: key)?.kind, .readerBuild)
        }
        XCTAssertEqual(name(), original)
        XCTAssertNil(registry.current(thread: key))
    }

    func testMeasureHostTickCoreCost() throws {
        var sampler = DiagnosticMachCPU()
        var history = DiagnosticThreads.History()
        var policy = DiagnosticCPULog.Policy()
        var wall = 0.0, cpu = 0.0, maxWall = 0.0
        let runs = 100
        for index in 0..<runs {
            let start = ProcessInfo.processInfo.systemUptime
            let startCPU = ThreadCPU.seconds()
            let tick = Double(index)
            XCTAssertTrue(policy.admit(at: tick))
            let sample = sampler.sample(mainID: 0)
            XCTAssertTrue(sample.complete)
            let observations = history.observe(sample.threads, at: tick) { [.lecteur] }
            let decision = try XCTUnwrap(policy.decide(at: tick, percent: sample.percent, cost: sample.cost, hasLongWork: true))
            let line = DiagnosticCPULog.line(percent: sample.percent, threads: sample.threads, active: [], context: .init(),
                                             long: .init(), cost: sample.cost, decision: decision, observations: observations, at: tick)
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            cpu += max(0, ThreadCPU.seconds() - startCPU)
            wall += elapsed
            maxWall = max(maxWall, elapsed)
            XCTAssertTrue(line.contains("fils_omis="))
        }
        print(String(format: "G1 Mac noyau tick n=%d mur_moy_ms=%.3f mur_max_ms=%.3f cpu_moy_ms=%.3f",
                     runs, wall * 1000 / Double(runs), maxWall * 1000, cpu * 1000 / Double(runs)))
    }
}
