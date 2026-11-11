// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// T1 (retours terrain du 10/11/2026) : en page seule + Glissement, le Pencil dessine au lieu de tourner la page.
final class PencilPageTurnGuardTests: XCTestCase {
    func testBlocksOnlyWhileDrawingWithPageController() {
        XCTAssertTrue(PencilPageTurnGuard.blocksPencil(drawing: true, pageController: true))
        XCTAssertFalse(PencilPageTurnGuard.blocksPencil(drawing: true, pageController: false))
        XCTAssertFalse(PencilPageTurnGuard.blocksPencil(drawing: false, pageController: true))
    }

    func testDrawingRemovesPencilAndKeepsFingerAndTrackpad() {
        let all = PencilPageTurnGuard.allTouchTypes
        XCTAssertEqual(PencilPageTurnGuard.touchTypes(current: all, drawing: true, pageController: true), [0, 1, 3])
        // Déjà posé : rien à refaire.
        XCTAssertNil(PencilPageTurnGuard.touchTypes(current: [0, 1, 3], drawing: true, pageController: true))
    }

    func testLeavingDrawingRestoresOnlyOwnValue() {
        XCTAssertEqual(PencilPageTurnGuard.touchTypes(current: [0, 1, 3], drawing: false, pageController: true), [0, 1, 2, 3])
        XCTAssertEqual(PencilPageTurnGuard.touchTypes(current: [3, 0, 1], drawing: true, pageController: false), [0, 1, 2, 3])
        // Valeur posée par un autre réglage (doigt seul) : intacte.
        XCTAssertNil(PencilPageTurnGuard.touchTypes(current: [0], drawing: false, pageController: true))
        XCTAssertNil(PencilPageTurnGuard.touchTypes(current: [0, 1, 2, 3], drawing: false, pageController: false))
    }
}
