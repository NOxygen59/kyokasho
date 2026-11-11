// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-027 (#42) : le fond « Sombre intelligent » retiré ne laisse pas un réglage inconnu (qui retomberait sur Blanc).
final class PageToneMigrationTests: XCTestCase {
    func testRemovedSmartDarkBecomesDark() {
        XCTAssertEqual(PageToneMigration.migrated("smartDark"), "dark")
    }

    func testOtherTonesAreKept() {
        for tone in ["normal", "cream", "dim", "dark", "sepiaNight"] {
            XCTAssertNil(PageToneMigration.migrated(tone), tone)
        }
        XCTAssertNil(PageToneMigration.migrated(nil))
    }
}
