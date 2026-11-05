// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Tableau de bord : chiffres de lecture et historique des mesures.
final class ReadingStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func session(_ when: Date, _ seconds: Int, _ id: String = "a", scope: ReadingScope = .textbook,
                         pages: Int? = nil, lookups: Int? = nil) -> ReadingSession {
        ReadingSession(start: when, seconds: seconds, documentId: id, scope: scope, pages: pages, lookups: lookups)
    }

    private func stats(_ sessions: [ReadingSession], _ period: ReadingStats.Period = .week,
                       _ filter: ReadingStats.Filter = .everything) -> ReadingStats {
        ReadingStats(sessions: sessions, period: period, filter: filter, now: date(10, 20), calendar: calendar)
    }

    func testEmptyLogStartsAtZero() {
        let result = stats([])
        XCTAssertEqual(result.total, 0)
        XCTAssertEqual(result.buckets.count, 7)
        XCTAssertEqual(result.averageSession, 0)
        XCTAssertEqual(result.currentStreak, 0)
        XCTAssertEqual(result.documents, [])
    }

    func testTotalsAndAverages() {
        let result = stats([session(date(10), 600, pages: 5, lookups: 2), session(date(10, 8), 300), session(date(9), 900, "b", pages: 1)])
        XCTAssertEqual(result.total, 1800)
        XCTAssertEqual(result.sessionCount, 3)
        XCTAssertEqual(result.activeDays, 2)
        XCTAssertEqual(result.averagePerActiveDay, 900)
        XCTAssertEqual(result.averageSession, 600)
        XCTAssertEqual(result.longestSession, 900)
        XCTAssertEqual(result.pages, 6)
        XCTAssertEqual(result.lookups, 2)
        XCTAssertEqual(result.documents.map(\.documentId), ["a", "b"])
        XCTAssertEqual(result.hours[12], 1500)
        XCTAssertEqual(result.hours[8], 300)
    }

    func testPeriodExcludesOlderSessions() {
        let old = session(date(1), 1000), recent = session(date(10), 100)
        XCTAssertEqual(stats([old, recent], .week).total, 100)
        XCTAssertEqual(stats([old, recent], .month).total, 1100)
        XCTAssertEqual(stats([old, recent], .month).buckets.count, 30)
    }

    func testMonthBucketsForLongPeriods() {
        let result = stats([session(date(10), 100), session(date(15, month: 10), 200)], .year)
        XCTAssertTrue(result.bucketsAreMonths)
        XCTAssertEqual(result.buckets.count, 12)
        XCTAssertEqual(result.buckets.last?.total, 100)
        XCTAssertEqual(result.buckets[10].total, 200)
    }

    func testAllStartsAtOldestSessionMonth() {
        let result = stats([session(date(15, month: 9), 200), session(date(10), 100)], .all)
        XCTAssertEqual(result.buckets.count, 3)
        XCTAssertEqual(result.total, 300)
    }

    func testFilterSeparatesSpaces() {
        let sessions = [session(date(10), 100, scope: .manga), session(date(10), 200, scope: .book), session(date(10), 50, scope: .unclassified)]
        XCTAssertEqual(stats(sessions, .week, .manga).total, 100)
        XCTAssertEqual(stats(sessions, .week, .study).total, 250)
        let last = stats(sessions).buckets.last
        XCTAssertEqual(last?.manga, 100)
        XCTAssertEqual(last?.study, 250)
    }

    func testStreaks() {
        let sessions = [1, 2, 3, 7, 9, 10].map { session(date($0), 60) }
        let result = stats(sessions)
        XCTAssertEqual(result.bestStreak, 3)
        XCTAssertEqual(result.currentStreak, 2)
    }

    func testStreakSurvivesUntilTodayIsRead() {
        XCTAssertEqual(stats([session(date(8), 60), session(date(9), 60)]).currentStreak, 2, "hier compte encore")
        XCTAssertEqual(stats([session(date(8), 60)]).currentStreak, 0, "avant-hier non")
    }

    func testJournalAloneGivesTotal() {
        var log = ReadingSessionLog()
        log.record(documentId: "a", start: date(1), end: date(1).addingTimeInterval(100), scope: .book, pages: 3, lookups: 1)
        log.record(documentId: "a", start: date(2), end: date(2).addingTimeInterval(2), scope: .book)
        XCTAssertEqual(log.totalSeconds, 100, "une séance trop courte n'entre pas")
        let read = ReadingSessionLog.decode(log.encoded()).sessions.first
        XCTAssertEqual(read?.pages, 3)
        XCTAssertEqual(read?.lookups, 1)
    }

    // MARK: Mesures

    private func sample(_ second: Int, cpu: Double, parts: [String: Double] = [:], ram: Double = 500, fps: Double = 60) -> PerformanceSample {
        PerformanceSample(date: date(10).addingTimeInterval(TimeInterval(second)), cpu: cpu, mainThreadCPU: cpu / 3, ramMB: ram,
                          fps: fps, inReader: true, activitySeconds: parts)
    }

    func testPeakKeepsTotalsAndWorkSeparately() throws {
        var log = PerformanceLog()
        XCTAssertFalse(log.add(sample(0, cpu: 40), calendar: calendar))
        XCTAssertFalse(log.add(sample(1, cpu: 200, parts: ["tone": 0.3]), calendar: calendar))
        XCTAssertFalse(log.add(sample(2, cpu: 340, parts: ["pageRender": 1.2], fps: 20), calendar: calendar))
        XCTAssertFalse(log.add(sample(3, cpu: 180, parts: ["tone": 0.9]), calendar: calendar))
        XCTAssertEqual(log.peaks.count, 0, "pas enregistré tant qu'il dure")
        XCTAssertTrue(log.add(sample(4, cpu: 30), calendar: calendar))
        let peak = try XCTUnwrap(log.peaks.first)
        XCTAssertEqual(peak.maxCPU, 340)
        XCTAssertEqual(peak.averageCPU, 240, accuracy: 0.01)
        XCTAssertEqual(peak.seconds, 3)
        XCTAssertEqual(peak.lowestFPS, 20)
        XCTAssertEqual(peak.activitySeconds["tone"] ?? 0, 1.2, accuracy: 0.01)
        XCTAssertEqual(peak.activitySeconds["pageRender"] ?? 0, 1.2, accuracy: 0.01)
    }

    /// Contre-revue : un dessin qui se termine au premier relevé redescendu appartient au pic.
    func testWorkFinishingAsThePeakEndsIsCounted() throws {
        var log = PerformanceLog()
        log.add(sample(0, cpu: 151), calendar: calendar)
        log.add(sample(1, cpu: 40, parts: ["pageRender": 2]), calendar: calendar)
        XCTAssertEqual(log.peaks.first?.activitySeconds["pageRender"], 2)
        XCTAssertEqual(log.peaks.first?.averageCPU, 151, "le total ne prend pas le relevé redescendu")
    }

    /// Seconde contre-revue : un relevé en retard ne change pas les secondes de travail.
    func testLateSnapshotKeepsRawSeconds() throws {
        var ledger = ActivityLedger()
        let t0 = date(1)
        _ = ledger.snapshot(at: t0)
        ledger.addCPU(kind: "tone", seconds: 2)
        let row = try XCTUnwrap(ledger.snapshot(at: t0.addingTimeInterval(4)).first)
        XCTAssertEqual(row.cpuSeconds, 2)
    }

    /// Revue Codex : le contexte suit le relevé le plus haut.
    func testPeakContextFollowsHighestSample() {
        var log = PerformanceLog()
        var outside = sample(0, cpu: 160)
        outside.inReader = false
        log.add(outside, calendar: calendar)
        log.add(sample(1, cpu: 300), calendar: calendar)
        log.finishPeak()
        XCTAssertEqual(log.peaks.first?.inReader, true)
    }

    func testStoppingMonitorClosesPeak() {
        var log = PerformanceLog()
        log.add(sample(0, cpu: 200), calendar: calendar)
        XCTAssertTrue(log.finishPeak())
        XCTAssertFalse(log.finishPeak())
        XCTAssertEqual(log.peaks.count, 1)
    }

    func testDaySummaryAndBounds() {
        var log = PerformanceLog()
        log.add(sample(0, cpu: 100, ram: 400, fps: 60), calendar: calendar)
        log.add(sample(1, cpu: 50, ram: 700, fps: 30), calendar: calendar)
        XCTAssertEqual(log.days.count, 1)
        XCTAssertEqual(log.days[0].maxCPU, 100)
        XCTAssertEqual(log.days[0].maxRAM, 700)
        XCTAssertEqual(log.days[0].lowestFPS, 30)
        XCTAssertEqual(log.days[0].averageCPU, 75)
        for index in 0..<(PerformanceLog.maxPeaks + 5) {
            log.add(sample(100 + index * 2, cpu: 200), calendar: calendar)
            log.add(sample(101 + index * 2, cpu: 10), calendar: calendar)
        }
        XCTAssertEqual(log.peaks.count, PerformanceLog.maxPeaks)
        XCTAssertEqual(PerformanceLog.decode(log.encoded()), log)
        XCTAssertEqual(PerformanceLog.decode(Data("?".utf8)), PerformanceLog())
    }

    // MARK: Temps processeur

    func testThreadCPUCountsWorkNotWaiting() {
        let start = ThreadCPU.seconds()
        Thread.sleep(forTimeInterval: 0.2)
        let slept = ThreadCPU.seconds() - start
        XCTAssertLessThan(slept, 0.1, "attendre ne coûte pas de processeur")
        let before = ThreadCPU.seconds()
        var value = 0.0
        let end = Date().addingTimeInterval(0.1)
        while Date() < end { value += sin(value + 1) }
        XCTAssertGreaterThan(ThreadCPU.seconds() - before, 0.03, "valeur \(value)")
    }

    func testLedgerReportsMeasuredCPUOnlyForMeasuredKinds() {
        var ledger = ActivityLedger()
        let t0 = date(1)
        _ = ledger.snapshot(at: t0)
        let id = UUID()
        ledger.begin(id, kind: "backup", detail: nil, at: t0)
        ledger.addCPU(kind: "tone", seconds: 0.5)
        let rows = ledger.snapshot(at: t0.addingTimeInterval(1))
        XCTAssertEqual(rows.first?.kind, "tone")
        XCTAssertEqual(rows.first?.cpuSeconds, 0.5)
        XCTAssertNil(rows.first { $0.kind == "backup" }?.cpuSeconds)
        XCTAssertTrue(ledger.snapshot(at: t0.addingTimeInterval(2)).allSatisfy { $0.kind != "tone" }, "rien de neuf, ligne retirée")
    }
}
