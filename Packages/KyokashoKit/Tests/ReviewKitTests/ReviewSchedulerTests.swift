// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReviewKit

final class ReviewSchedulerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    var settings: ReviewSettings {
        var s = ReviewSettings()
        s.fuzz = false
        return s
    }

    func card() -> StudyCard {
        StudyCard(id: 1, deckId: 1, templateId: 1, key: "猫|ねこ", fields: ["Mot": "猫"], now: now)
    }

    func testGoodIsLaterThanAgain() throws {
        let scheduler = ReviewScheduler(settings: settings)
        let (good, log) = try scheduler.review(card(), grade: .good, now: now, duration: 3)
        let (again, _) = try scheduler.review(card(), grade: .again, now: now)
        XCTAssertGreaterThan(good.due, again.due)
        XCTAssertNotEqual(good.state, .new)
        XCTAssertEqual(good.reps, 1)
        XCTAssertEqual(log.state, .new)
        XCTAssertEqual(log.grade, .good)
        XCTAssertEqual(log.duration, 3)
    }

    func testPreviewOrder() throws {
        let scheduler = ReviewScheduler(settings: settings)
        for c in [card(), try scheduler.review(card(), grade: .good, now: now).0] {
            let p = scheduler.preview(c, now: now.addingTimeInterval(86400 * 3))
            XCTAssertEqual(p.count, 4)
            XCTAssertLessThanOrEqual(p[.again]!, p[.hard]!)
            XCTAssertLessThanOrEqual(p[.hard]!, p[.good]!)
            XCTAssertLessThanOrEqual(p[.good]!, p[.easy]!)
        }
    }

    func testIntervalLabel() {
        XCTAssertEqual(ReviewScheduler.intervalLabel(from: now, to: now.addingTimeInterval(30)), "< 1 min")
        XCTAssertEqual(ReviewScheduler.intervalLabel(from: now, to: now.addingTimeInterval(600)), "10 min")
        XCTAssertEqual(ReviewScheduler.intervalLabel(from: now, to: now.addingTimeInterval(86400 * 4)), "4 j")
    }

    func testSettingsDecodingIsBounded() throws {
        let json = #"{"retention": 2, "newCardsPerDay": -5, "maximumReviewsPerDay": 0, "dayStartHour": 30, "fuzz": "oui"}"#
        let s = try JSONDecoder().decode(ReviewSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.retention, 0.99)
        XCTAssertEqual(s.newCardsPerDay, 0)
        XCTAssertEqual(s.maximumReviewsPerDay, 1)
        XCTAssertEqual(s.dayStartHour, 23)
        XCTAssertTrue(s.fuzz)
        let empty = try JSONDecoder().decode(ReviewSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, ReviewSettings())
        let back = try JSONDecoder().decode(ReviewSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back, settings)
    }

    func testDayStartAtFour() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let s = ReviewSettings()
        let threeAM = cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 3))!
        let fiveAM = cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 5))!
        XCTAssertEqual(s.dayStart(for: threeAM, calendar: cal), cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 4)))
        XCTAssertEqual(s.dayStart(for: fiveAM, calendar: cal), cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 4)))
    }
}
