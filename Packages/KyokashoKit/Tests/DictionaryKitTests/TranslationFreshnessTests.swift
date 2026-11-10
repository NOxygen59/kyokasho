// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import DictionaryKit

/// C1.2 (audit du 09/11/2026) : même mot, définition changée par une mise à jour du dictionnaire.
final class TranslationFreshnessTests: XCTestCase {
    func testChangedDefinitionHidesMachineTranslation() {
        XCTAssertFalse(TranslationFreshness.isCurrent(edited: false, storedSource: "to eat", currentSource: "to eat; to consume"))
        XCTAssertTrue(TranslationFreshness.isCurrent(edited: false, storedSource: "to eat", currentSource: "to eat"))
    }

    func testManualCorrectionAlwaysKept() {
        XCTAssertTrue(TranslationFreshness.isCurrent(edited: true, storedSource: "to eat", currentSource: "other"))
    }

    func testOldEntriesWithoutSourceAreKept() {
        XCTAssertTrue(TranslationFreshness.isCurrent(edited: false, storedSource: nil, currentSource: "anything"))
    }

    /// Revue DeepSeek #3 : une mise à jour du dictionnaire rend la traduction périmée ; la retraduire ne doit pas
    /// effacer en silence l'avis 👍/👎 donné par l'utilisateur.
    func testLikedAndDislikedReviewsSurviveRetranslation() {
        XCTAssertEqual(TranslationReview.liked.keptWhenRetranslated, .liked)
        XCTAssertEqual(TranslationReview.disliked.keptWhenRetranslated, .disliked)
    }

    func testNeutralTranslationStaysNeutralAfterRetranslation() {
        XCTAssertEqual(TranslationReview.machine.keptWhenRetranslated, .machine)
        // `.edited` n'est jamais retraduit (`isCurrent` le garde courant) ; s'il l'était, rien ne serait figé.
        XCTAssertEqual(TranslationReview.edited.keptWhenRetranslated, .machine)
    }
}
