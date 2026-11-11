// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Rappel de luminosité : montré seulement sur batterie, au-dessus de 90 %, une fois par séance, et si l'option est allumée.
final class BrightnessReminderTests: XCTestCase {
    func testShownOnlyAboveTheThresholdOnBattery() {
        XCTAssertTrue(BrightnessReminder.shouldShow(brightness: 0.95, onBattery: true, enabled: true, dismissed: false))
        XCTAssertTrue(BrightnessReminder.shouldShow(brightness: 1, onBattery: true, enabled: true, dismissed: false))
        // 90 % pile reste dans la tranche d'en dessous, comme `EnergyLog.BrightnessBand`.
        XCTAssertFalse(BrightnessReminder.shouldShow(brightness: 0.90, onBattery: true, enabled: true, dismissed: false))
        XCTAssertFalse(BrightnessReminder.shouldShow(brightness: 0.60, onBattery: true, enabled: true, dismissed: false))
        XCTAssertFalse(BrightnessReminder.shouldShow(brightness: -1, onBattery: true, enabled: true, dismissed: false))
    }

    func testNeverShownWhenPluggedDismissedOrTurnedOff() {
        XCTAssertFalse(BrightnessReminder.shouldShow(brightness: 1, onBattery: false, enabled: true, dismissed: false))
        XCTAssertFalse(BrightnessReminder.shouldShow(brightness: 1, onBattery: true, enabled: true, dismissed: true))
        XCTAssertFalse(BrightnessReminder.shouldShow(brightness: 1, onBattery: true, enabled: false, dismissed: false))
    }

    func testThresholdIsTheHighBandOfTheEnergyLog() {
        // Même frontière que le résumé « Par luminosité » : le rappel et le relevé parlent de la même tranche.
        XCTAssertEqual(EnergyLog.BrightnessBand.of(BrightnessReminder.threshold), .mid)
        XCTAssertEqual(EnergyLog.BrightnessBand.of(BrightnessReminder.threshold + 0.01), .high)
        XCTAssertEqual(BrightnessReminder.percent(0.949), 95)
        XCTAssertEqual(BrightnessReminder.percent(7), 100)
        XCTAssertEqual(BrightnessReminder.percent(-1), 0)
    }

    /// Garde de source : la bannière est bien posée dans le lecteur et le réglage existe dans les Réglages.
    func testBannerAndSettingAreWired() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App").standardizedFileURL
        func read(_ path: String) throws -> String { try String(contentsOf: app.appendingPathComponent(path), encoding: .utf8) }
        XCTAssertTrue(try read("Reader/DocumentTabsBar.swift").contains("BrightnessReminderBanner()"))
        XCTAssertTrue(try read("Settings/SettingsView.swift").contains("@AppStorage(BrightnessReminder.enabledKey)"))
        XCTAssertTrue(try read("Reader/BrightnessReminderBanner.swift").contains("BrightnessReminder.shouldShow("))
    }
}
