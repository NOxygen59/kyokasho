// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-041 (#60) : la pastille du moteur OCR ne disparaît plus un instant à chaque changement de page.
final class OCRPillHoldTests: XCTestCase {
    func testPageChangeWithCachedOCRKeepsPillVisible() {
        // Nouvelle page : le résultat est d'abord effacé, puis rechargé depuis le cache avec le même moteur.
        XCTAssertEqual(OCRPillHold.step(shown: "vision", incoming: nil), .holdThenClear)
        XCTAssertEqual(OCRPillHold.step(shown: "vision", incoming: "vision"), .show("vision"))
    }

    func testPageWithoutOCRClearsPillAfterHold() {
        XCTAssertEqual(OCRPillHold.step(shown: "vision", incoming: nil), .holdThenClear)
        XCTAssertEqual(OCRPillHold.step(shown: nil, incoming: nil), .keep)
    }

    func testEngineChangeShowsNewEngineImmediately() {
        XCTAssertEqual(OCRPillHold.step(shown: "vision", incoming: "ndlocr"), .show("ndlocr"))
        XCTAssertEqual(OCRPillHold.step(shown: nil, incoming: "vision"), .show("vision"))
    }

    func testHoldIsShortEnoughForPagesWithoutOCR() {
        XCTAssertGreaterThan(OCRPillHold.holdDelay, 0.35, "doit couvrir la pose de la page (0,35 s)")
        XCTAssertLessThanOrEqual(OCRPillHold.holdDelay, 1.5)
    }
}
