// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// PLAN-MODLOC-001, E1 (DEC-01 = A) : trois touchers rapides basculent le mode propriétaire, un seul ouvre le tableau de
/// bord, et rien n'est décidé avant la fin de la pause.
final class TapBurstTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testOneTapOpensTheDashboardAfterThePause() {
        var burst = TapBurst()
        burst.tap(at: t0)
        XCTAssertNil(burst.outcome(at: t0.addingTimeInterval(0.2)), "la rafale peut encore continuer")
        XCTAssertEqual(burst.outcome(at: t0.addingTimeInterval(0.4)), .single)
    }

    func testThreeQuickTapsToggleTheOwnerMode() {
        var burst = TapBurst()
        for i in 0..<3 { burst.tap(at: t0.addingTimeInterval(Double(i) * 0.25)) }
        XCTAssertEqual(burst.outcome(at: t0.addingTimeInterval(0.5 + 0.4)), .toggleOwnerMode)
    }

    func testTwoTapsStayASingleAndASlowThirdTapStartsANewBurst() {
        var burst = TapBurst()
        burst.tap(at: t0)
        burst.tap(at: t0.addingTimeInterval(0.3))
        XCTAssertEqual(burst.outcome(at: t0.addingTimeInterval(0.7)), .single)
        burst.tap(at: t0.addingTimeInterval(1.5))
        XCTAssertEqual(burst.taps.count, 1)
        XCTAssertEqual(burst.outcome(at: t0.addingTimeInterval(1.9)), .single)
    }

    func testNoTapNoOutcome() {
        XCTAssertNil(TapBurst().outcome(at: t0))
    }
}
