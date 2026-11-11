// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-013 (#16) : onglets des documents ouverts.
final class DocumentTabsTests: XCTestCase {
    func testOpenAddsOnceInOrder() {
        var tabs = DocumentTabs()
        tabs.open("a"); tabs.open("b"); tabs.open("a")
        XCTAssertEqual(tabs.ids, ["a", "b"])
    }

    func testCloseCurrentShowsNeighbour() {
        var tabs = DocumentTabs(ids: ["a", "b", "c"])
        XCTAssertEqual(tabs.close("b", current: "b"), "c")
        XCTAssertEqual(tabs.close("c", current: "c"), "a")
        XCTAssertEqual(tabs.close("a", current: "a"), nil)
        XCTAssertTrue(tabs.ids.isEmpty)
    }

    func testCloseOtherKeepsCurrent() {
        var tabs = DocumentTabs(ids: ["a", "b"])
        XCTAssertEqual(tabs.close("a", current: "b"), "b")
        XCTAssertEqual(tabs.close("zz", current: "b"), "b")
    }

    func testMemoryWarningFromFourTabsAndDeletedDocumentsLeave() {
        var tabs = DocumentTabs(ids: ["a", "b", "c"])
        XCTAssertFalse(tabs.showsMemoryWarning)
        tabs.open("d")
        XCTAssertTrue(tabs.showsMemoryWarning)
        tabs.keep(only: ["a", "d"])
        XCTAssertEqual(tabs.ids, ["a", "d"])
    }
}
