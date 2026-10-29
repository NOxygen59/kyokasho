// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Corbeille des documents.
final class DocumentTrashTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testPutKeepsFirstDateAndRestoreRemoves() {
        var trash = DocumentTrash()
        trash.put("a", at: t0)
        trash.put("a", at: t0.addingTimeInterval(500))
        XCTAssertEqual(trash.entries["a"], t0)
        trash.remove("a")
        XCTAssertFalse(trash.contains("a"))
    }

    func testExpiryAfterThirtyDaysAndDaysLeft() {
        var trash = DocumentTrash()
        trash.put("old", at: t0)
        trash.put("new", at: t0.addingTimeInterval(20 * 86_400))
        let now = t0.addingTimeInterval(30 * 86_400)
        XCTAssertEqual(trash.expired(at: now), ["old"])
        XCTAssertEqual(trash.daysLeft("new", at: now), 20)
        XCTAssertEqual(trash.daysLeft("old", at: now), 0)
        XCTAssertNil(trash.daysLeft("absent", at: now))
    }

    func testForgetsMissingDocumentsAndRoundTrips() {
        var trash = DocumentTrash()
        trash.put("a", at: t0)
        trash.put("gone", at: t0)
        trash.keep(only: ["a"])
        XCTAssertEqual(Array(trash.entries.keys), ["a"])
        XCTAssertEqual(DocumentTrash.decode(trash.encoded()), trash)
        XCTAssertEqual(DocumentTrash.decode(Data("x".utf8)), DocumentTrash())
    }
}
