// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReviewKit

final class CardTemplateTests: XCTestCase {
    func render(_ source: String, _ fields: [String: String], extra: [String: String] = [:]) throws -> String {
        try CardTemplate(source).render(fields, extra: extra)
    }

    func testVariablesAndFilters() throws {
        XCTAssertEqual(try render("<b>{{Mot}}</b>{{{Mot}}}{{Absent}}", ["Mot": "猫"]), "<b>猫</b>猫")
        let f = ["F": "食[た]べる"]
        XCTAssertEqual(try render("{{furigana:F}}", f), "<ruby>食<rt>た</rt></ruby>べる")
        XCTAssertEqual(try render("{{kana:F}}", f), "たべる")
        XCTAssertEqual(try render("{{kanji:F}}", f), "食べる")
        XCTAssertEqual(try render("{{text:S}}", ["S": "<i>chat</i> noir"]), "chat noir")
        XCTAssertEqual(try render("a{{! commentaire }}b", [:]), "ab")
    }

    func testConditions() throws {
        let t = "{{#if A}}oui{{else}}non{{/if}}"
        XCTAssertEqual(try render(t, ["A": "x"]), "oui")
        XCTAssertEqual(try render(t, ["A": " <br> "]), "non")
        XCTAssertEqual(try render(t, ["A": "<img src=\"a.jpg\">"]), "oui")
        XCTAssertEqual(try render("{{#unless A}}vide{{/unless}}", [:]), "vide")
        XCTAssertEqual(try render("{{#unless A}}vide{{/unless}}", ["A": "x"]), "")
    }

    func testEach() throws {
        let t = "{{#each L}}[{{@index}}:{{this}}]{{/each}}"
        XCTAssertEqual(try render(t, ["L": "un\n\ndeux\n  \ntrois"]), "[0:un][1:deux][2:trois]")
    }

    func testAnkiBlocksAndFrontSide() throws {
        XCTAssertEqual(try render("{{#A}}a{{/A}}{{^B}}pas b{{/B}}", ["A": "1"]), "apas b")
        XCTAssertEqual(try render("{{FrontSide}}<hr>{{Sens}}", ["Sens": "chat"], extra: ["FrontSide": "猫"]), "猫<hr>chat")
        let template = NoteTemplate(name: "T", fieldNames: ["Mot", "Sens"], front: "{{Mot}}",
                                    back: "{{FrontSide}}|{{Sens}}", css: "")
        let r = template.render(["Mot": "猫", "Sens": "chat"])
        XCTAssertEqual(r.front, "猫")
        XCTAssertEqual(r.back, "猫|chat")
    }

    func testErrors() {
        XCTAssertThrowsError(try CardTemplate("{{#if A}}x")) { XCTAssertEqual($0 as? CardTemplate.ParseError, .unclosed("if")) }
        XCTAssertThrowsError(try CardTemplate("x{{/if}}")) { XCTAssertEqual($0 as? CardTemplate.ParseError, .unexpectedClose("if")) }
        XCTAssertThrowsError(try CardTemplate("{{Mot")) { XCTAssertEqual($0 as? CardTemplate.ParseError, .unterminatedTag) }
        let bad = NoteTemplate(name: "T", fieldNames: [], front: "{{#if A}}", back: "", css: "")
        XCTAssertNotNil(bad.validationError)
        XCTAssertEqual(bad.render([:]).front, "{{#if A}}")
        XCTAssertNil(NoteTemplate.japaneseWord.validationError)
    }

    func testAnkiSource() throws {
        let t = try CardTemplate("{{furigana:F}}{{#if A}}x{{else}}y{{/if}}{{#each L}}{{this}}{{/each}}{{^B}}z{{/B}}")
        XCTAssertEqual(t.ankiSource, "{{furigana:F}}{{#A}}x{{/A}}{{^A}}y{{/A}}{{L}}{{^B}}z{{/B}}")
        XCTAssertEqual(t.referencedFields, ["F", "A", "L", "B"])
    }

    func testFuriganaRoundTrip() {
        let anki = Furigana.anki([("私", "わたし"), ("は", ""), ("日本", "にほん"), ("語", "ご")])
        XCTAssertEqual(anki, "私[わたし]は 日本[にほん] 語[ご]")
        XCTAssertEqual(Furigana.ruby(anki),
                       "<ruby>私<rt>わたし</rt></ruby>は<ruby>日本<rt>にほん</rt></ruby><ruby>語<rt>ご</rt></ruby>")
        XCTAssertEqual(Furigana.kana(anki), "わたしはにほんご")
        XCTAssertEqual(Furigana.kanji(anki), "私は日本語")
        XCTAssertEqual(Furigana.ruby("ひらがな"), "ひらがな")
    }

    func testAnkiGUIDStable() {
        XCTAssertEqual(AnkiGUID.make("猫|ねこ"), AnkiGUID.make("猫|ねこ"))
        XCTAssertNotEqual(AnkiGUID.make("猫|ねこ"), AnkiGUID.make("犬|いぬ"))
        XCTAssertFalse(AnkiGUID.make("").isEmpty)
    }
}
