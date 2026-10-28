// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// #47 : journal des IA lisible.
final class AIActivityTextTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(AIActivityText.duration(44.6), "45 s")
        XCTAssertEqual(AIActivityText.duration(125), "2 min 05 s")
        XCTAssertEqual(AIActivityText.duration(3780), "1 h 03 min")
        XCTAssertEqual(AIActivityText.duration(-3), "0 s")
    }

    func testOutcome() {
        XCTAssertEqual(AIActivityText.outcome(seconds: 30, cancelled: false, error: nil), "Terminée en 30 s")
        XCTAssertEqual(AIActivityText.outcome(seconds: 30, cancelled: true, error: "x"), "Arrêtée après 30 s")
        XCTAssertEqual(AIActivityText.outcome(seconds: 30, cancelled: false, error: "mémoire"), "Erreur après 30 s : mémoire")
    }

    func testExplainKnownAndUnknown() {
        XCTAssertTrue(AIActivityText.explain("chargement").contains("mémoire"))
        XCTAssertEqual(AIActivityText.explain("3 tâches"), "enchaîne plusieurs tâches, une à la fois")
        XCTAssertEqual(AIActivityText.explain("autre chose"), "autre chose")
    }
}
