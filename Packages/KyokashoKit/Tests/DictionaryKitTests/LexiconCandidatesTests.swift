// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import DictionaryKit
import XCTest

/// #50, D4 : termes proposés pour le lexique (relevé de l'IA, import de glossaire).
final class LexiconCandidatesTests: XCTestCase {
    func testParsesAIListWithBulletsAndHeaders() {
        let text = """
        terme | lecture | sens
        - 框 | かまち | cadre (montants et traverses)
        2. 鴨居 | かもい | linteau rainuré
        Voici la liste :
        - 框 | かまち | doublon
        """
        let list = LexiconCandidates.parse(text, page: 12)
        XCTAssertEqual(list.map(\.term), ["框", "鴨居"])
        XCTAssertEqual(list[0].reading, "かまち")
        XCTAssertEqual(list[1].meaning, "linteau rainuré")
        XCTAssertEqual(list[0].page, 12)
    }

    func testParsesCsvVariants() {
        let csv = "用語;読み;意味\n敷居;しきい;seuil rainuré\n巾木\tはばき\tplinthe\n欄間,imposte ajourée"
        let list = LexiconCandidates.parse(csv)
        XCTAssertEqual(list.map(\.term), ["敷居", "巾木", "欄間"])
        XCTAssertEqual(list[2].reading, "")
        XCTAssertEqual(list[2].meaning, "imposte ajourée")
    }

    func testOnlyNewTerms() {
        let list = [LexiconCandidate(term: "框", reading: "", meaning: ""), LexiconCandidate(term: "敷居", reading: "", meaning: "")]
        XCTAssertEqual(LexiconCandidates.new(list, known: ["框"]).map(\.term), ["敷居"])
    }
}
