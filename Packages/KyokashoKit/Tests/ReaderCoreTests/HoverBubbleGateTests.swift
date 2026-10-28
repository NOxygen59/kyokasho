// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-042 (#61) : survol avec Maj fiable quand le curseur passe vite d'un mot à l'autre.
final class HoverBubbleGateTests: XCTestCase {
    func testLeavingWordThenReachingAnotherKeepsNewBubble() {
        var gate = HoverBubbleGate()
        gate.opened()                      // mot A
        let pending = gate.token           // pointeur sorti de A : fermeture différée
        gate.opened()                      // mot B atteint pendant le délai
        XCTAssertFalse(gate.shouldClose(token: pending), "la fermeture prévue pour A ne doit pas fermer B")
    }

    func testReturningToSameWordDuringDelayKeepsBubble() {
        var gate = HoverBubbleGate()
        gate.opened()
        let pending = gate.token           // espace entre deux mots
        gate.opened()                      // retour sur le même mot
        XCTAssertFalse(gate.shouldClose(token: pending))
    }

    func testLeavingTextForGoodClosesBubble() {
        var gate = HoverBubbleGate()
        gate.opened()
        let pending = gate.token
        XCTAssertTrue(gate.shouldClose(token: pending))
    }

    func testHoverToHoverReusesBubbleButClickOpensNewOne() {
        XCTAssertTrue(HoverBubbleGate.reusesBubble(currentIsHover: true, incomingIsHover: true))
        XCTAssertFalse(HoverBubbleGate.reusesBubble(currentIsHover: nil, incomingIsHover: true))
        XCTAssertFalse(HoverBubbleGate.reusesBubble(currentIsHover: false, incomingIsHover: true))
        XCTAssertFalse(HoverBubbleGate.reusesBubble(currentIsHover: true, incomingIsHover: false))
    }
}
