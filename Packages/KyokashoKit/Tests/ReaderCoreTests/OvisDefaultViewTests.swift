// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-024 (#39) : OvisOCR2 par défaut, une seule fois.
final class OvisDefaultViewTests: XCTestCase {
    func testSwitchesOnceWhenOvisInstalled() {
        XCTAssertTrue(OvisDefaultView.shouldSwitch(ovisInstalled: true, alreadyApplied: false))
        XCTAssertFalse(OvisDefaultView.shouldSwitch(ovisInstalled: true, alreadyApplied: true))
    }

    func testWaitsForModelDownload() {
        XCTAssertFalse(OvisDefaultView.shouldSwitch(ovisInstalled: false, alreadyApplied: false))
    }
}
