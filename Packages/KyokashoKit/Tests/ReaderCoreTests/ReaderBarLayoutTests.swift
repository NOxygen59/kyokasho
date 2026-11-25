// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// PLAN-FENETRES-001 : la barre du haut du lecteur tient dans la fenêtre, de l'écran entier à Split View ⅓.
final class ReaderBarLayoutTests: XCTestCase {
    /// Largeur réellement occupée par la variante choisie (mêmes mesures que `ReaderBarLayout`).
    private func used(_ t: ReaderBarLayout.Top, openTabs: Int) -> CGFloat {
        let base = t.slim ? ReaderBarLayout.slimFixed + ReaderBarLayout.slimCapsule : ReaderBarLayout.fixed + ReaderBarLayout.capsule
        let tabs = CGFloat(t.visibleTabs - 1) * ReaderBarLayout.pill + (t.currentTitle ? ReaderBarLayout.titled : ReaderBarLayout.pill)
        let more = openTabs > t.visibleTabs ? ReaderBarLayout.pill : 0
        return base + tabs + more + (t.newTabButton ? ReaderBarLayout.pill : 0)
    }

    func testFullScreenKeepsEverything() {
        // Paysage plein écran, panneau ancré : ≈ 876 pt pour la barre.
        let t = ReaderBarLayout.top(width: 876, openTabs: 1, pillsOnlyFrom: 4)
        XCTAssertEqual(t, .init(visibleTabs: 1, currentTitle: true, newTabButton: true, slim: false))
        XCTAssertEqual(ReaderBarLayout.top(width: 876, openTabs: 9, pillsOnlyFrom: 4).visibleTabs, 6)
    }

    func testSplitHalfShowsTitleWithOneBookThenPills() {
        // Split View ½ paysage : fenêtre 678, barre 650.
        XCTAssertTrue(ReaderBarLayout.top(width: 650, openTabs: 1, pillsOnlyFrom: 4).currentTitle)
        let three = ReaderBarLayout.top(width: 650, openTabs: 3, pillsOnlyFrom: 4)
        XCTAssertFalse(three.currentTitle)
        XCTAssertFalse(three.slim)
    }

    func testSplitThirdIsSlim() {
        // Split View ⅓ : fenêtre 375, barre 347.
        let t = ReaderBarLayout.top(width: 347, openTabs: 3, pillsOnlyFrom: 4)
        XCTAssertEqual(t, .init(visibleTabs: 1, currentTitle: false, newTabButton: false, slim: true))
    }

    func testNeverWiderThanOffered() {
        // Plancher : Bibliothèque, livre affiché, « +N » et capsule resserrée = 343 pt (Split View ⅓ = 347).
        for width in stride(from: CGFloat(343), through: 1400, by: 7) {
            for tabs in 1...9 {
                let t = ReaderBarLayout.top(width: width, openTabs: tabs, pillsOnlyFrom: 4)
                XCTAssertLessThanOrEqual(used(t, openTabs: tabs), width, "largeur \(width), \(tabs) onglets")
                XCTAssertGreaterThanOrEqual(t.visibleTabs, 1)
            }
        }
    }
}
