// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import GLMOCRKit

/// Traduction anglaise (demande de NOxygen59 du 29/10/2026) : chaque langue a ses propres fichiers de page, et le
/// français reste la langue par défaut (fichiers `fr-<page>.md` déjà faits, inchangés).
final class TranslationLanguageTests: XCTestCase {
    func testEachLanguageHasItsOwnFilesAndFrenchStaysTheDefault() {
        XCTAssertEqual(TranslationLanguage.allCases.map(\.rawValue), ["fr", "en"])
        XCTAssertEqual(Set(TranslationLanguage.allCases.map(\.rawValue)).count, 2)
        XCTAssertEqual(TranslationLanguage.french.englishName, "French")
        XCTAssertEqual(TranslationLanguage.english.englishName, "English")
        XCTAssertEqual(TranslationLanguage(rawValue: "fr"), .french, "clé enregistrée avant l'anglais")
        XCTAssertNil(TranslationLanguage(rawValue: "ja"))
    }
}
