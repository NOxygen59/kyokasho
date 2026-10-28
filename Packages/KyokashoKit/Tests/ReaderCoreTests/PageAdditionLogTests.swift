// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-033 (#48) : historique des ajouts de pages.
final class PageAdditionLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testSummary() {
        XCTAssertEqual(PageAddition(date: t0, added: 12, insertedBefore: 0, totalAfter: 112, sources: []).summary,
                       "12 pages ajoutées à la fin")
        XCTAssertEqual(PageAddition(date: t0, added: 1, insertedBefore: 1, totalAfter: 101, sources: []).summary,
                       "1 page ajoutée au début")
        XCTAssertEqual(PageAddition(date: t0, added: 15, insertedBefore: 12, totalAfter: 115, sources: []).summary,
                       "12 pages ajoutées au début · 3 pages à la fin")
    }

    func testRecordSkipsEmptyAndKeepsLatest() {
        var log = PageAdditionLog()
        log.record(PageAddition(date: t0, added: 0, insertedBefore: 0, totalAfter: 100, sources: []))
        XCTAssertTrue(log.entries.isEmpty)
        for i in 0..<(PageAdditionLog.maxEntries + 2) {
            log.record(PageAddition(date: t0, added: 1, insertedBefore: 0, totalAfter: 100 + i, sources: ["\(i).pdf"]))
        }
        XCTAssertEqual(log.entries.count, PageAdditionLog.maxEntries)
        XCTAssertEqual(log.entries.first?.sources, ["2.pdf"])
    }

    func testRoundTripAndUnreadableData() {
        var log = PageAdditionLog()
        log.record(PageAddition(date: t0, added: 3, insertedBefore: 0, totalAfter: 103, sources: ["suite.pdf"]))
        XCTAssertEqual(PageAdditionLog.decode(log.encoded()), log)
        XCTAssertEqual(PageAdditionLog.decode(Data("?".utf8)), PageAdditionLog())
    }
}
