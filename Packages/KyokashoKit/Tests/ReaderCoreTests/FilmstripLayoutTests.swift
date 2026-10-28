// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Recette 1.3.2 (59), A2 et A11 (RET-049, #79).
final class FilmstripLayoutTests: XCTestCase {
    func testSinglePageHighlightsOnlyCurrentPageEvenWithNeighbourVisible() {
        XCTAssertEqual(FilmstripLayout.highlightedPages(current: 7, shown: [7, 8], isDouble: false), [7])
        XCTAssertEqual(FilmstripLayout.highlightedPages(current: 7, shown: [], isDouble: false), [7])
    }

    func testDoublePageHighlightsBothPagesOfSpread() {
        XCTAssertEqual(FilmstripLayout.highlightedPages(current: 4, shown: [4, 5], isDouble: true), [4, 5])
    }

    func testDoublePageCoverOrLastOddPageHighlightsSinglePage() {
        XCTAssertEqual(FilmstripLayout.highlightedPages(current: 0, shown: [0], isDouble: true), [0])
        XCTAssertEqual(FilmstripLayout.highlightedPages(current: 120, shown: [120], isDouble: true), [120])
    }

    func testDoublePageStaleSpreadFallsBackToCurrentPage() {
        // Page tournée, liste pas encore mise à jour : l'ancienne planche n'est plus surlignée.
        XCTAssertEqual(FilmstripLayout.highlightedPages(current: 6, shown: [4, 5], isDouble: true), [6])
    }

    func testTrailingInsetStopsAtPortraitPanelEdge() {
        XCTAssertEqual(FilmstripLayout.trailingInset(portraitPanelShown: true, panelWidth: 372, gap: 14), 386)
        XCTAssertEqual(FilmstripLayout.trailingInset(portraitPanelShown: false, panelWidth: 372, gap: 14), 0)
    }
}
