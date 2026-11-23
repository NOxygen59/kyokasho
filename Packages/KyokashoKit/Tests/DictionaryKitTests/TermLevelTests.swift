// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import XCTest

/// Fiche de mot de la refonte : niveau JLPT lu dans les étiquettes, jamais deviné.
final class TermLevelTests: XCTestCase {
    func testReadsCommonTagSpellings() {
        XCTAssertEqual(TermResult.jlptLevel(tagNames: ["jlpt-n3"]), "N3")
        XCTAssertEqual(TermResult.jlptLevel(tagNames: ["JLPT N2"]), "N2")
        XCTAssertEqual(TermResult.jlptLevel(tagNames: ["n5", "common"]), "N5")
    }

    func testEasiestLevelWinsAndNothingIsGuessed() {
        XCTAssertEqual(TermResult.jlptLevel(tagNames: ["jlpt-n1", "jlpt-n4"]), "N4")
        XCTAssertNil(TermResult.jlptLevel(tagNames: ["noun", "n", "n6", "news"]))
        XCTAssertNil(TermResult.jlptLevel(tagNames: []))
    }
}
