// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import DictionaryKit

final class CardFieldsTests: XCTestCase {
    func definition(_ glossary: String, title: String = "JMdict") -> TermResult.Definition {
        TermResult.Definition(dictionaryId: 1, dictionaryTitle: title, tags: [], termTags: [], rules: [],
                              glossaryJSON: glossary, score: 0, sequence: 0)
    }

    func testItems() {
        let json = #"["manger", {"type":"structured-content","content":[{"tag":"div","content":"avaler"},{"tag":"img","path":"x.png"}]}, ""]"#
        XCTAssertEqual(GlossaryText.items(json), ["manger", "avaler"])
        XCTAssertEqual(GlossaryText.items("pas du json"), [])
    }

    func testMake() {
        let term = TermResult(
            expression: "食べる", reading: "たべる", matchedText: "食べた", inflectionRules: ["past"],
            definitions: [definition(#"["manger", "<consommer>"]"#), definition(#"["manger", "vivre de"]"#, title: "Autre")],
            frequencies: [.init(dictionaryTitle: "JPDB", display: "1234", value: 1234)],
            pitches: [.init(dictionaryTitle: "NHK", downstep: 2, pattern: nil, tags: []),
                      .init(dictionaryTitle: "Autre", downstep: 2, pattern: nil, tags: [])],
            ipa: [])
        let f = CardFields.make(term: term, sentence: "パンを食べた。", source: "Manuel · p. 12")
        XCTAssertEqual(f["Mot"], "食べる")
        XCTAssertEqual(f["Lecture"], "たべる")
        XCTAssertEqual(f["Furigana"], "食[た]べる")
        XCTAssertEqual(f["Sens"], "<ol><li>manger</li><li>&lt;consommer&gt;</li><li>vivre de</li></ol>")
        XCTAssertEqual(f["Accent"], "[2]")
        XCTAssertEqual(f["Fréquence"], "1234 · JPDB")
        XCTAssertEqual(f["Phrase"], "パンを<b>食べた</b>。")
        XCTAssertEqual(f["Source"], "Manuel · p. 12")
    }

    func testFurigana() {
        XCTAssertEqual(CardFields.furigana("日本語", "にほんご"), "日本語[にほんご]")
        XCTAssertEqual(CardFields.furigana("お茶", "おちゃ"), "お 茶[ちゃ]")
        XCTAssertEqual(CardFields.furigana("ねこ", "ねこ"), "ねこ")
    }
}
