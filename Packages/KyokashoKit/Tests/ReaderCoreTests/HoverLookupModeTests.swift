// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-021 (#24) : sur la page PDF, Maj tenue active le survol même bouton éteint.
final class HoverLookupModeTests: XCTestCase {
    func testToggleOffNeedsShift() {
        XCTAssertFalse(HoverLookupMode.isActive(toggleOn: false, shiftHeld: false, drawing: false))
        XCTAssertTrue(HoverLookupMode.isActive(toggleOn: false, shiftHeld: true, drawing: false))
    }

    func testToggleOnWorksWithoutShiftAsBefore() {
        XCTAssertTrue(HoverLookupMode.isActive(toggleOn: true, shiftHeld: false, drawing: false))
    }

    func testDrawingModeNeverLooksUp() {
        XCTAssertFalse(HoverLookupMode.isActive(toggleOn: true, shiftHeld: true, drawing: true))
    }

    func testReleasingShiftClosesOnlyShiftOpenedBubble() {
        XCTAssertTrue(HoverLookupMode.opensWithShiftOnly(toggleOn: false, shiftHeld: true))
        XCTAssertFalse(HoverLookupMode.opensWithShiftOnly(toggleOn: true, shiftHeld: true))
        XCTAssertTrue(HoverLookupMode.closesOnShiftRelease(toggleOn: false, openedByShiftOnly: true, bubbleOpen: true))
        XCTAssertFalse(HoverLookupMode.closesOnShiftRelease(toggleOn: true, openedByShiftOnly: true, bubbleOpen: true))
        XCTAssertFalse(HoverLookupMode.closesOnShiftRelease(toggleOn: false, openedByShiftOnly: false, bubbleOpen: true))
        XCTAssertFalse(HoverLookupMode.closesOnShiftRelease(toggleOn: false, openedByShiftOnly: true, bubbleOpen: false))
    }
}
