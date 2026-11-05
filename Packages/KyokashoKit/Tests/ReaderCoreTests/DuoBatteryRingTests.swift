// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Batterie du lecteur, barres cachées : couleurs d'iOS, forme de l'iPhone Duo.
final class DuoBatteryRingTests: XCTestCase {
    private func ring(_ level: Double = 0.6, charging: Bool = false, full: Bool = false, low: Bool = false) -> DuoBatteryRing {
        DuoBatteryRing(level: level, charging: charging, full: full, lowPowerMode: low)
    }

    func testColors() {
        XCTAssertEqual(ring().tint, .normal)
        XCTAssertEqual(ring(charging: true).tint, .charging)
        XCTAssertEqual(ring(low: true).tint, .lowPower)
        XCTAssertEqual(ring(0.1).tint, .low)
        XCTAssertEqual(ring(0.2).tint, .normal)
    }

    func testChargingWinsOverLowPowerAndLowLevel() {
        XCTAssertEqual(ring(0.1, charging: true, low: true).tint, .charging)
        XCTAssertEqual(ring(0.1, low: true).tint, .lowPower)
    }

    func testBoltOnlyWhileCharging() {
        XCTAssertTrue(ring(charging: true).showsBolt)
        XCTAssertFalse(ring().showsBolt)
        XCTAssertFalse(ring(1, full: true).showsBolt)
        XCTAssertEqual(ring(1, full: true).tint, .normal)
    }

    func testArcGoesOverTheTop() {
        XCTAssertEqual(ring(0).filledEndDegrees, DuoBatteryRing.startDegrees)
        XCTAssertEqual(ring(1).filledEndDegrees, DuoBatteryRing.endDegrees)
        XCTAssertEqual(ring(0.5).filledEndDegrees, 270, accuracy: 0.001, "le haut de l'anneau")
    }

    func testUnknownLevelShowsEmptyRingInWhite() {
        XCTAssertEqual(ring(-1).progress, 0)
        XCTAssertEqual(ring(-1).tint, .normal)
    }
}
