// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Recette iPad 1.4.7 : les barres cachées ne pouvaient plus revenir.
final class ReaderBarsPolicyTests: XCTestCase {
    private func hides(changed: Bool = true, rebuilding: Bool = false, setting: Bool = true, visible: Bool = true,
                       elapsed: TimeInterval = 10) -> Bool {
        ReaderBarsPolicy.hidesOnPageChange(pageChanged: changed, rebuilding: rebuilding, hideOnTurn: setting,
                                           barsVisible: visible, secondsSinceBarsChanged: elapsed)
    }

    func testPageTurnHidesBars() {
        XCTAssertTrue(hides())
    }

    /// Le redimensionnement dû à la barre d'état ne doit pas recacher les barres qu'un toucher vient de montrer.
    func testPageChangeRightAfterShowingBarsKeepsThem() {
        XCTAssertFalse(hides(elapsed: 0.1))
        XCTAssertFalse(hides(elapsed: ReaderBarsPolicy.settleDelay - 0.01))
        XCTAssertTrue(hides(elapsed: ReaderBarsPolicy.settleDelay))
    }

    func testOtherCasesNeverHide() {
        XCTAssertFalse(hides(changed: false))
        XCTAssertFalse(hides(rebuilding: true))
        XCTAssertFalse(hides(setting: false))
        XCTAssertFalse(hides(visible: false))
    }

    /// Une sélection périmée ou vide ne doit pas avaler le toucher.
    func testEmptySelectionDoesNotCountAsSelection() {
        XCTAssertFalse(ReaderBarsPolicy.isVisibleSelection(nil))
        XCTAssertFalse(ReaderBarsPolicy.isVisibleSelection(""))
        XCTAssertFalse(ReaderBarsPolicy.isVisibleSelection(" \n\t"))
        XCTAssertTrue(ReaderBarsPolicy.isVisibleSelection("天井"))
    }

    /// Mode dictionnaire : seul un toucher sans mot, sans fenêtre ouverte, change les barres.
    func testLookupModeTapOnBlankTogglesBars() {
        XCTAssertFalse(ReaderBarsPolicy.togglesAfterLookup(isStale: true, popupWasOpen: false, popupIsOpen: false),
                       "OCR lent : page tournée ou flèche touchée pendant l'attente")
        XCTAssertTrue(ReaderBarsPolicy.togglesAfterLookup(popupWasOpen: false, popupIsOpen: false))
        XCTAssertFalse(ReaderBarsPolicy.togglesAfterLookup(popupWasOpen: false, popupIsOpen: true))
        XCTAssertFalse(ReaderBarsPolicy.togglesAfterLookup(popupWasOpen: true, popupIsOpen: true))
        XCTAssertFalse(ReaderBarsPolicy.togglesAfterLookup(popupWasOpen: true, popupIsOpen: false))
    }
}
