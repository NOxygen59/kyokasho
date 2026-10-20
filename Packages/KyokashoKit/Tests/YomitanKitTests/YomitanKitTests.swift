// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 NOxygen59
// Cas de test inspirés des tests de Yomitan (test/language/japanese-transforms.test.js).

import XCTest
@testable import YomitanKit

final class TransformerTests: XCTestCase {
    let t = LanguageTransformer.japanese

    /// La forme `inflected` doit pouvoir redonner `base`, dont l'entrée a la partie du discours `pos`.
    func assertDeinflects(_ inflected: String, to base: String, pos: [String], file: StaticString = #filePath, line: UInt = #line) {
        let flags = t.conditionFlags(partsOfSpeech: pos)
        let ok = t.transform(inflected).contains { $0.text == base && LanguageTransformer.conditionsMatch($0.conditions, flags) }
        XCTAssertTrue(ok, "\(inflected) → \(base) [\(pos.joined(separator: ","))]", file: file, line: line)
    }

    func testRulesLoaded() {
        XCTAssertGreaterThan(t.transforms.count, 50)
        XCTAssertGreaterThan(t.transforms.reduce(0) { $0 + $1.rules.count }, 900)
    }

    func testVerbs() {
        assertDeinflects("食べた", to: "食べる", pos: ["v1"])
        assertDeinflects("食べない", to: "食べる", pos: ["v1"])
        assertDeinflects("食べさせられなかった", to: "食べる", pos: ["v1"])
        assertDeinflects("書いて", to: "書く", pos: ["v5"])
        assertDeinflects("読みました", to: "読む", pos: ["v5"])
        assertDeinflects("行った", to: "行く", pos: ["v5"])
        assertDeinflects("来なかった", to: "来る", pos: ["vk"])
        assertDeinflects("勉強しています", to: "勉強する", pos: ["vs"])
        assertDeinflects("考えられる", to: "考える", pos: ["v1"])
        assertDeinflects("感じさせ", to: "感じる", pos: ["v1"])
    }

    func testAdjectives() {
        assertDeinflects("高くない", to: "高い", pos: ["adj-i"])
        assertDeinflects("明るかった", to: "明るい", pos: ["adj-i"])
        assertDeinflects("広く", to: "広い", pos: ["adj-i"])
    }

    func testWrongPartOfSpeechRejected() {
        // « 食べた » ne doit pas redonner un godan « 食ぶ ».
        let flags = t.conditionFlags(partsOfSpeech: ["v5"])
        XCTAssertFalse(t.transform("食べた").contains { $0.text == "食べる" && $0.conditions != 0 && LanguageTransformer.conditionsMatch($0.conditions, flags) })
    }

    func testInflectionChain() {
        let hit = t.transform("食べなかった").first { $0.text == "食べる" }
        XCTAssertNotNil(hit)
        XCTAssertFalse(hit!.inflectionRules.isEmpty)
    }

    func testPerformance() {
        measure { _ = t.transform("食べさせられなかったでしょう") }
    }
}

final class JapaneseTextTests: XCTestCase {
    func testKana() {
        XCTAssertEqual(JapaneseText.katakanaToHiragana("ヨミチャン"), "よみちゃん")
        XCTAssertEqual(JapaneseText.katakanaToHiragana("カー"), "かあ")
        XCTAssertEqual(JapaneseText.katakanaToHiragana("カー", keepProlongedSoundMarks: true), "かー")
        XCTAssertEqual(JapaneseText.hiraganaToKatakana("よみちゃん"), "ヨミチャン")
        XCTAssertEqual(JapaneseText.halfWidthKanaToFullWidth("ﾖﾐﾁｬﾝ"), "ヨミチャン")
        XCTAssertEqual(JapaneseText.halfWidthKanaToFullWidth("ｶﾞｯｺｳ"), "ガッコウ")
        XCTAssertEqual(JapaneseText.fullWidthAlphanumericToNormal("ｙｏｍｉ１２"), "yomi12")
        XCTAssertEqual(JapaneseText.alphanumericToFullWidth("ab1"), "ａｂ１")
        XCTAssertEqual(JapaneseText.normalizeCombiningCharacters("ト\u{3099}"), "ド")
        XCTAssertEqual(JapaneseText.normalizeCJKCompatibilityCharacters("㌀"), "アパート")
        XCTAssertEqual(JapaneseText.collapseEmphaticSequences("すっっごーーい", full: false), "すっごーい")
        XCTAssertEqual(JapaneseText.collapseEmphaticSequences("すっっごーーい", full: true), "すごい")
    }

    func testCharacterClasses() {
        XCTAssertTrue(JapaneseText.isKanji("照"))
        XCTAssertFalse(JapaneseText.isKanji("あ"))
        XCTAssertTrue(JapaneseText.isKana("カ"))
        XCTAssertTrue(JapaneseText.isEntirelyKana("たべもの"))
        XCTAssertFalse(JapaneseText.isEntirelyKana("食べ物"))
    }

    func testMorae() {
        XCTAssertEqual(JapaneseText.morae("きょうと"), ["きょ", "う", "と"])
        XCTAssertEqual(JapaneseText.moraCount("しゃしん"), 3)
        XCTAssertEqual(JapaneseText.pitchCategory("はし", downstep: 1, isVerbOrAdjective: false), .atamadaka)
        XCTAssertEqual(JapaneseText.pitchCategory("はし", downstep: 2, isVerbOrAdjective: false), .odaka)
        XCTAssertEqual(JapaneseText.pitchCategory("はし", downstep: 0, isVerbOrAdjective: false), .heiban)
        XCTAssertTrue(JapaneseText.isMoraPitchHigh(1, downstep: 0))
        XCTAssertFalse(JapaneseText.isMoraPitchHigh(0, downstep: 0))
    }

    func testFurigana() {
        typealias S = JapaneseText.FuriganaSegment
        XCTAssertEqual(JapaneseText.distributeFurigana("食べ物", "たべもの"), [S("食", "た"), S("べ", ""), S("物", "もの")])
        XCTAssertEqual(JapaneseText.distributeFurigana("照明", "しょうめい"), [S("照明", "しょうめい")])
        XCTAssertEqual(JapaneseText.distributeFurigana("お茶", "おちゃ"), [S("お", ""), S("茶", "ちゃ")])
        XCTAssertEqual(JapaneseText.distributeFurigana("かな", "かな"), [S("かな", "")])
        XCTAssertEqual(JapaneseText.distributeFuriganaInflected("食べる", "たべる", source: "食べた"), [S("食", "た"), S("べた", "")])
    }
}
