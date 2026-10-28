// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-023 (#38) : plus de panneau « réduit en pastille » après le retrait du bouton « − ».
final class StudyPanelModeMigrationTests: XCTestCase {
    func testMinimizedPanelReturnsToLastPosition() {
        XCTAssertEqual(StudyPanelModeMigration.migrated(mode: "minimized", restore: "floating"), "floating")
        XCTAssertEqual(StudyPanelModeMigration.migrated(mode: "minimized", restore: "full"), "full")
    }

    func testMinimizedWithoutUsableRestoreGoesDocked() {
        XCTAssertEqual(StudyPanelModeMigration.migrated(mode: "minimized", restore: nil), "docked")
        XCTAssertEqual(StudyPanelModeMigration.migrated(mode: "minimized", restore: "minimized"), "docked")
    }

    func testOtherModesUnchanged() {
        for mode in ["docked", "floating", "full", nil] {
            XCTAssertNil(StudyPanelModeMigration.migrated(mode: mode, restore: "floating"))
        }
    }
}
