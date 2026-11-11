// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import XCTest
@testable import MorphologyKit

/// PLAN-CARTES-001, étape E2 : mots de la page proposés en cartes (filtre grammatical, ordre, doublons).
final class PageWordCandidatesTests: XCTestCase {
    private func token(_ surface: String, lemma: String, reading: String = "", _ pos: String...) -> MeCab.Token {
        MeCab.Token(surface: surface, range: NSRange(location: 0, length: 0), reading: reading, lemma: lemma, pos: pos)
    }

    func testGrammarWordsAreRemovedAndOrderIsTheOrderOfThePage() {
        // 木材の強度を測る。2つの試験。
        let tokens = [
            token("木材", lemma: "木材", reading: "もくざい", "名詞", "普通名詞", "一般"),
            token("の", lemma: "の", "助詞", "格助詞"),
            token("強度", lemma: "強度", reading: "きょうど", "名詞", "普通名詞", "一般"),
            token("を", lemma: "を", "助詞", "格助詞"),
            token("測る", lemma: "測る", reading: "はかる", "動詞", "一般"),
            token("。", lemma: "。", "補助記号", "句点"),
            token("2", lemma: "2", "名詞", "数詞"),
            token("つ", lemma: "つ", "接尾辞", "名詞的", "助数詞"),
            token("試験", lemma: "試験", reading: "しけん", "名詞", "普通名詞", "サ変可能"),
            token("し", lemma: "為る", "動詞", "非自立可能"),
            token("た", lemma: "た", "助動詞"),
            token("これ", lemma: "此れ", "代名詞"),
            token("ね", lemma: "ね", "感動詞"),
        ]
        XCTAssertEqual(PageWordCandidates.words(tokens).map(\.expression), ["木材", "強度", "測る", "試験"])
    }

    func testDuplicatesAndLexiconTermsAreSkippedAndInflectedFormsUseTheLemma() {
        let tokens = [
            token("強度", lemma: "強度", reading: "きょうど", "名詞", "普通名詞"),
            token("測っ", lemma: "測る", reading: "はかっ", "動詞", "一般"),
            token("測る", lemma: "測る", reading: "はかる", "動詞", "一般"),
            token("木材", lemma: "木材", reading: "もくざい", "名詞", "普通名詞"),
        ]
        let words = PageWordCandidates.words(tokens, excluding: ["木材"])
        XCTAssertEqual(words.map(\.expression), ["強度", "測る"])
        // Forme conjuguée : la lecture de la page ne vaut pas pour la forme de dictionnaire.
        XCTAssertEqual(words[1], .init(expression: "測る", surface: "測っ", readingHint: ""))
        XCTAssertEqual(words[0].readingHint, "きょうど")
    }

    func testLoanwordSuffixSingleKanaAndLatinAreHandled() {
        let tokens = [
            token("コンピューター", lemma: "コンピューター-computer", "名詞", "普通名詞"),
            token("え", lemma: "絵", "名詞", "普通名詞"),
            token("CAD", lemma: "", "名詞", "普通名詞"),
            token("ア-ル", lemma: "ア-ル", "名詞", "普通名詞"),
        ]
        XCTAssertEqual(PageWordCandidates.words(tokens).map(\.expression), ["コンピューター", "ア-ル"])
    }

    func testEmptyPageGivesNoWord() {
        XCTAssertEqual(PageWordCandidates.words([]), [])
    }
}
