// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-037 (#52) : temps de lecture active.
final class ReadingTimeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testSessionAddsElapsedTimeOnce() {
        var clock = ReadingClock(total: 60)
        clock.start(at: t0)
        clock.start(at: t0.addingTimeInterval(100))        // deuxième départ ignoré
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(30)), 90)
        clock.stop(at: t0.addingTimeInterval(120))
        clock.stop(at: t0.addingTimeInterval(500))         // arrêt sans séance : rien
        XCTAssertEqual(clock.total, 180)
        XCTAssertNil(clock.startedAt)
    }

    func testMissedStopIsCapped() {
        var clock = ReadingClock()
        clock.start(at: t0)
        clock.stop(at: t0.addingTimeInterval(3 * 86_400))   // app tuée en arrière-plan puis rouverte des jours après
        XCTAssertEqual(clock.total, ReadingClock.maxSession)
    }

    func testClockGoingBackwardsAddsNothing() {
        var clock = ReadingClock(total: 10)
        clock.start(at: t0)
        clock.stop(at: t0.addingTimeInterval(-50))
        XCTAssertEqual(clock.total, 10)
    }

    func testFormat() {
        XCTAssertEqual(ReadingClock.format(0), "0 min")
        XCTAssertEqual(ReadingClock.format(35 * 60 + 20), "35 min")
        XCTAssertEqual(ReadingClock.format(4 * 3600 + 7 * 60), "4 h 07")
        XCTAssertEqual(ReadingClock.format(2 * 86_400 + 5 * 3600), "2 j 5 h")
        XCTAssertEqual(ReadingClock.format(3 * 86_400), "3 j")
        XCTAssertEqual(ReadingClock.format(33 * 86_400), "1 mois 3 j")
    }
}
