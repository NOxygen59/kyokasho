// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// #37 / #45 : réglages du chat par modèle.
final class AIChatSettingsTests: XCTestCase {
    func testDefaultsKeepPreviousBehaviour() {
        let s = AIChatSettings()
        XCTAssertEqual(s.effectiveTemperature(grounded: true), 0)
        XCTAssertEqual(s.effectiveTemperature(grounded: false), 0.3)
        XCTAssertEqual(s.maxTokens, 1024)
        XCTAssertEqual(s.effectiveInstructions(default: "app"), "app")
    }

    func testValuesAreClamped() {
        var s = AIChatSettings()
        s.temperature = 9
        s.topP = 0
        s.topK = -4
        s.maxTokens = 1_000_000
        s.repetitionPenalty = 0.2
        XCTAssertEqual(s.temperature, 1.5)
        XCTAssertEqual(s.topP, 0.05)
        XCTAssertEqual(s.topK, 0)
        XCTAssertEqual(s.maxTokens, 4096)
        XCTAssertEqual(s.repetitionPenalty, 1)
    }

    func testBlankInstructionsFallBackToApp() {
        var s = AIChatSettings()
        s.instructions = "   \n"
        XCTAssertNil(s.instructions)
        s.instructions = String(repeating: "あ", count: 5000)
        XCTAssertEqual(s.instructions?.count, 4000)
    }

    func testDecodingDamagedPreferencesIsBounded() throws {
        let json = #"{"temperature":-3,"maxTokens":5,"topK":999,"instructions":" Résume. "}"#
        let s = try JSONDecoder().decode(AIChatSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.temperature, 0)
        XCTAssertEqual(s.maxTokens, 128)
        XCTAssertEqual(s.topK, 200)
        XCTAssertEqual(s.instructions, "Résume.")
        XCTAssertEqual(try JSONDecoder().decode(AIChatSettings.self, from: Data("{}".utf8)), AIChatSettings())
    }

    func testPresetsSetInstructionsAndKeepOtherChoices() {
        var s = AIChatSettings()
        s.topP = 0.8
        let formulas = AIChatPreset.formulas.applied(to: s)
        XCTAssertTrue(formulas.instructions?.contains("formule") == true)
        XCTAssertEqual(formulas.maxTokens, 2048)
        XCTAssertEqual(formulas.topP, 0.8)
        XCTAssertNil(AIChatPreset.standard.applied(to: formulas).instructions)
        XCTAssertNil(AIChatPreset.standard.applied(to: formulas).temperature)
    }
}
