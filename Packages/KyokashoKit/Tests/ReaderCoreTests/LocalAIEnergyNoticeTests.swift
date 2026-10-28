// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-018 (#21) : avertissement de l'accueil sur la consommation de l'IA locale.
final class LocalAIEnergyNoticeTests: XCTestCase {
    func testNothingWithoutLocalModel() {
        XCTAssertEqual(LocalAIEnergyNotice.state(modelInstalled: false, acknowledged: false, aiActive: true, onBattery: true), .hidden)
    }

    func testGeneralNoticeUntilAcknowledged() {
        XCTAssertEqual(LocalAIEnergyNotice.state(modelInstalled: true, acknowledged: false, aiActive: false, onBattery: true), .general)
        XCTAssertEqual(LocalAIEnergyNotice.state(modelInstalled: true, acknowledged: true, aiActive: false, onBattery: true), .hidden)
    }

    func testReminderOnlyWhileWorkingOnBattery() {
        XCTAssertEqual(LocalAIEnergyNotice.state(modelInstalled: true, acknowledged: true, aiActive: true, onBattery: true), .activeOnBattery)
        XCTAssertEqual(LocalAIEnergyNotice.state(modelInstalled: true, acknowledged: false, aiActive: true, onBattery: true), .activeOnBattery)
        XCTAssertEqual(LocalAIEnergyNotice.state(modelInstalled: true, acknowledged: true, aiActive: true, onBattery: false), .hidden)
    }
}
