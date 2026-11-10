// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
@testable import DictionaryKit

/// PLAN-LEX-001, étape E1 : lecture paginée du Lexique (tests exigés par le plan, entrées synthétiques).
final class LexiconTests: XCTestCase {
    private var db: DictionaryDatabase!

    override func setUpWithError() throws {
        db = try DictionaryDatabase.inMemory()
    }

    @discardableResult
    private func dictionary(_ title: String, priority: Int = 0, enabled: Bool = true,
                            terms: [(String, String, String)]) throws -> Int64 {
        try db.writer.write { d in
            var info = DictionaryInfo(title: title, revision: "1", format: 3, priority: priority, enabled: enabled,
                                      termCount: terms.count)
            try info.insert(d)
            let id = info.id ?? d.lastInsertedRowID
            for (expression, reading, glossary) in terms {
                try d.execute(sql: """
                    INSERT INTO term (dictionaryId, expression, reading, definitionTags, rules, score, glossary, sequence, termTags)
                    VALUES (?, ?, ?, '', '', 0, ?, 0, '')
                    """, arguments: [id, expression, reading, glossary])
            }
            return id
        }
    }

    private func all(_ ids: Set<Int64>, limit: Int, prefix: String = "") throws -> [LexiconWord] {
        var words: [LexiconWord] = []
        var cursor: LexiconCursor?
        var pages = 0
        repeat {
            let page = try db.lexiconPage(dictionaryIds: ids, after: cursor, prefix: prefix, limit: limit)
            words += page.words
            cursor = page.next
            pages += 1
            XCTAssertLessThan(pages, 10_000, "boucle sans fin")
        } while cursor != nil
        return words
    }

    func testNoDuplicateNorGapOver10000Entries() throws {
        var terms: [(String, String, String)] = []
        for i in 0..<10_000 {
            // Lectures en désordre et quelques mots répétés (deux entrées) pour tester les coupures de page.
            let n = (i * 7_919) % 10_000
            terms.append(("語\(n / 2)", "ご\(String(format: "%05d", n / 2))", "[\"sens \(i)\"]"))
        }
        let id = try dictionary("Synthétique", terms: terms)
        let words = try all([id], limit: 37)
        XCTAssertEqual(words.count, 5_000)
        XCTAssertEqual(Set(words.map(\.id)).count, 5_000, "doublon")
        XCTAssertEqual(words.reduce(0) { $0 + $1.senses.count }, 10_000, "trou ou doublon d'entrée")
        XCTAssertEqual(words.map(\.sortReading), words.map(\.sortReading).sorted(), "ordre par lecture")
    }

    func testWordSpanningPageBoundaryIsNeverCut() throws {
        // 3 mots ; le 2e a 5 entrées : avec 4 entrées par page, il tomberait à cheval.
        let id = try dictionary("D", terms: [("一", "いち", "[\"un\"]")]
            + (0..<5).map { _ in ("二", "に", "[\"deux\"]") } + [("三", "さん", "[\"trois\"]")])
        let words = try all([id], limit: 20)
        XCTAssertEqual(words.map(\.expression), ["一", "三", "二"])
        XCTAssertEqual(words.first { $0.expression == "二" }?.senses.count, 5)
        // Page minimale (20) dépassée par un mot seul : il est relu en entier.
        let big = try dictionary("Gros", terms: (0..<25).map { _ in ("homo", "ほも", "[\"x\"]") })
        let page = try db.lexiconPage(dictionaryIds: [big], limit: 20)
        XCTAssertEqual(page.words.count, 1)
        XCTAssertEqual(page.words[0].senses.count, 25)
    }

    func testHomographsAcrossSourcesAreOneLine() throws {
        // DEC-01 A : 7 entrées d'un même mot dans deux sources → une seule ligne, sens par priorité.
        let fr = try dictionary(BundledLexicon.Language.french.title, priority: 1,
                                terms: (0..<4).map { ("職業訓練指導員", "職業訓練指導員", "[\"sens fr \($0)\"]") })
        let en = try dictionary(BundledLexicon.Language.english.title, priority: 0,
                                terms: (0..<3).map { ("職業訓練指導員", "職業訓練指導員", "[\"sense en \($0)\"]") })
        let words = try all([fr, en], limit: 50)
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words[0].senses.count, 7)
        XCTAssertEqual(words[0].senses.first?.language, .english, "priorité 0 d'abord")
        XCTAssertEqual(words[0].summary(.french), "sens fr 0")
        XCTAssertEqual(words[0].summary(.english), "sense en 0")
        // DEC-04 A : la lecture recopiée par l'importeur n'est pas affichée.
        XCTAssertNil(words[0].reading)
    }

    func testDisabledEmptyOrExcludedDictionariesAreOnlyWhatTheAppPasses() throws {
        // DEC-06 A : seuls les dictionnaires passés par l'app sont lus (désactivé, vide, variante exclue : absents).
        let kept = try dictionary("Gardé", terms: [("木", "き", "[\"arbre\"]")])
        _ = try dictionary("Désactivé", enabled: false, terms: [("火", "ひ", "[\"feu\"]")])
        _ = try dictionary(BundledLexicon.Language.chinese.title, terms: [("水", "みず", "[\"水\"]")])
        XCTAssertEqual(try all([kept], limit: 20).map(\.expression), ["木"])
        XCTAssertTrue(try db.lexiconPage(dictionaryIds: []).words.isEmpty)
    }

    func testNullGlossaryKeepsWordWithoutSense() throws {
        let id = try dictionary("D", terms: [("空", "そら", "null"), ("空", "そら", "[\"ciel\"]"), ("無", "む", "[]")])
        let words = try all([id], limit: 20)
        XCTAssertEqual(words.map(\.expression), ["空", "無"])
        XCTAssertEqual(words[0].senses.map(\.full), ["ciel"])
        XCTAssertTrue(words[1].senses.isEmpty)
        XCTAssertNil(words[1].summary(.french), "DEC-02 A : rien d'inventé")
    }

    func testUnknownLanguageAndKanaReading() throws {
        let id = try dictionary("Dictionnaire maison", terms: [("ペン", "ペン", "[\"stylo\"]"), ("本", "ほん", "[\"livre\"]")])
        let words = try all([id], limit: 20)
        XCTAssertEqual(words.first { $0.expression == "本" }?.senses.first?.language, .unknown)
        XCTAssertEqual(words.first { $0.expression == "本" }?.reading, "ほん")
        XCTAssertNil(words.first { $0.expression == "ペン" }?.reading, "lecture identique au mot : non répétée")
        XCTAssertEqual(LexiconLanguage.forDictionary(title: BundledLexicon.Language.english.title), .english)
    }

    func testPrefixInKanaOrKanji() throws {
        let id = try dictionary("D", terms: [("建具", "たてぐ", "[\"menuiserie\"]"), ("建物", "たてもの", "[\"bâtiment\"]"),
                                             ("畳", "たたみ", "[\"tatami\"]")])
        XCTAssertEqual(try all([id], limit: 20, prefix: "たて").map(\.expression), ["建具", "建物"])
        XCTAssertEqual(try all([id], limit: 20, prefix: "畳").map(\.expression), ["畳"])
    }

    func testLongDefinitionHasShortLine() throws {
        let long = String(repeating: "très long ", count: 40)
        let id = try dictionary("D", terms: [("長", "ちょう", "[\"\(long)\"]")])
        let sense = try all([id], limit: 20)[0].senses[0]
        XCTAssertLessThanOrEqual(sense.short.count, DictionaryDatabase.lexiconShortLength)
        XCTAssertTrue(sense.short.hasSuffix("…"))
        XCTAssertEqual(sense.full, long.trimmingCharacters(in: .whitespaces))
    }
}
