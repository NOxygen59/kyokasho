// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-019 (#22) : notes groupées par jour, avec une heure discrète.
final class NoteDayGroupsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func note(_ id: String, _ created: Date) -> PageComment {
        PageComment(id: id, documentId: "doc", pageIndex: 0, body: id, createdAt: created, updatedAt: created)
    }

    func testGroupsNewestDayFirstAndKeepsCreationOrderWithinDay() {
        let now = date(2026, 10, 28, 20, 0)
        let notes = [note("b", date(2026, 10, 28, 9, 5)), note("old", date(2025, 3, 2, 8, 0)),
                     note("y", date(2026, 10, 27, 23, 59)), note("a", date(2026, 10, 28, 8, 1)),
                     note("c", date(2026, 10, 3, 12, 0))]
        let groups = NoteDayGroups.group(notes, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.title), ["Aujourd'hui", "Hier", "3 oct.", "2 mars 2025"])
        XCTAssertEqual(groups[0].notes.map(\.id), ["a", "b"])
    }

    func testTimeIsTwentyFourHour() {
        XCTAssertEqual(NoteDayGroups.time(date(2026, 10, 28, 14, 32), calendar: calendar), "14:32")
        XCTAssertEqual(NoteDayGroups.time(date(2026, 10, 28, 9, 5), calendar: calendar), "09:05")
    }

    func testEmptyListHasNoGroup() {
        XCTAssertTrue(NoteDayGroups.group([], calendar: calendar).isEmpty)
    }
}
