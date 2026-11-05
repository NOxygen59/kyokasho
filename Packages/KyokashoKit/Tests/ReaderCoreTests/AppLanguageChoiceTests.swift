// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Le bouton de relance ne s'affiche que si la langue choisie n'est pas déjà celle de l'interface.
final class AppLanguageChoiceTests: XCTestCase {
    func testSameLanguageNeedsNoRelaunch() {
        XCTAssertFalse(AppLanguageChoice.needsRelaunch(selected: "fr", running: "fr", system: "en"))
        XCTAssertFalse(AppLanguageChoice.needsRelaunch(selected: "en", running: "en-US", system: "fr"))
    }

    func testOtherLanguageNeedsRelaunch() {
        XCTAssertTrue(AppLanguageChoice.needsRelaunch(selected: "en", running: "fr", system: "fr"))
        XCTAssertTrue(AppLanguageChoice.needsRelaunch(selected: "zh-Hans", running: "zh-Hant", system: "fr"))
    }

    func testSystemChoiceComparesTheSystemLanguage() {
        XCTAssertFalse(AppLanguageChoice.needsRelaunch(selected: "", running: "fr", system: "fr"))
        XCTAssertTrue(AppLanguageChoice.needsRelaunch(selected: "", running: "en", system: "fr"))
    }

    /// Choisir une autre langue puis revenir à la première fait disparaître le bouton : c'est un calcul, pas une mémoire.
    func testComingBackToTheRunningLanguageNeedsNoRelaunch() {
        XCTAssertTrue(AppLanguageChoice.needsRelaunch(selected: "en", running: "fr", system: "fr"))
        XCTAssertFalse(AppLanguageChoice.needsRelaunch(selected: "fr", running: "fr", system: "fr"))
    }
}
