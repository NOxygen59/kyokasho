// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
@testable import DictionaryKit

/// Filtre « Mes mots » du Lexique (choix de NOxygen59 du 11/11/2026) : les mots enregistrés d'une étoile, lus dans les
/// dictionnaires actifs.
final class LexiconSavedWordsTests: XCTestCase {
    private var db: DictionaryDatabase!

    override func setUpWithError() throws {
        db = try DictionaryDatabase.inMemory()
    }

    @discardableResult
    private func dictionary(_ title: String, terms: [(String, String, String)]) throws -> Int64 {
        try db.writer.write { d in
            var info = DictionaryInfo(title: title, revision: "1", format: 3, priority: 0, enabled: true, termCount: terms.count)
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

    func testSavedWordsComeBackSortedWithTheirSenses() throws {
        let a = try dictionary("A", terms: [("天井", "てんじょう", "[\"plafond\"]"), ("畳", "たたみ", "[\"tatami\"]"),
                                            ("床", "ゆか", "[\"sol\"]"), ("たたみ", "たたみ", "[\"tatami (kana)\"]")])
        let b = try dictionary("B", terms: [("天井", "てんじょう", "[\"ceiling\"]")])
        let words = try db.lexiconWords(dictionaryIds: [a, b], entries: [("床", "ゆか"), ("天井", "てんじょう"), ("畳", "たたみ")])
        XCTAssertEqual(words.map(\.expression), ["畳", "天井", "床"], "ordre par lecture, comme la liste")
        XCTAssertEqual(words.first { $0.expression == "天井" }?.senses.count, 2, "sens de chaque source regroupés")
    }

    func testUnknownDuplicateAndInactiveEntriesAreNotInvented() throws {
        let a = try dictionary("A", terms: [("天井", "てんじょう", "[\"plafond\"]")])
        let off = try dictionary("Désactivé", terms: [("襖", "ふすま", "[\"cloison\"]")])
        let entries = [("天井", "てんじょう"), ("天井", "てんじょう"), ("襖", "ふすま"), ("無い", "ない")]
        // Le dictionnaire « désactivé » n'est pas passé : l'app filtre, comme pour la recherche.
        XCTAssertEqual(try db.lexiconWords(dictionaryIds: [a], entries: entries).map(\.expression), ["天井"])
        XCTAssertEqual(try db.lexiconWords(dictionaryIds: [a, off], entries: entries).map(\.expression), ["天井", "襖"])
        XCTAssertTrue(try db.lexiconWords(dictionaryIds: [], entries: entries).isEmpty)
        XCTAssertTrue(try db.lexiconWords(dictionaryIds: [a], entries: []).isEmpty)
    }

    func testEmptyReadingMeansTheWordItself() throws {
        // L'importeur recopie le mot quand la lecture manque : un mot enregistré sans lecture le retrouve.
        let a = try dictionary("A", terms: [("カーテン", "カーテン", "[\"rideau\"]")])
        let words = try db.lexiconWords(dictionaryIds: [a], entries: [("カーテン", "")])
        XCTAssertEqual(words.map(\.expression), ["カーテン"])
        XCTAssertNil(words.first?.reading, "DEC-04 : pas de lecture affichée quand elle répète le mot")
    }

    func testPrefixFilterFollowsTheSearchRule() throws {
        let a = try dictionary("A", terms: [("天井", "てんじょう", "[\"plafond\"]"), ("畳", "たたみ", "[\"tatami\"]")])
        let words = try db.lexiconWords(dictionaryIds: [a], entries: [("天井", "てんじょう"), ("畳", "たたみ")])
        XCTAssertEqual(words.filter { $0.matches(prefix: "てん") }.map(\.expression), ["天井"])
        XCTAssertEqual(words.filter { $0.matches(prefix: " 畳 ") }.map(\.expression), ["畳"])
        XCTAssertEqual(words.filter { $0.matches(prefix: "") }.count, 2)
        XCTAssertTrue(words.filter { $0.matches(prefix: "ぬ") }.isEmpty)
    }

    /// PLAN-CARTES-001 E2 : mots de la page cherchés par leur forme ; lecture de la page préférée, sinon la source la
    /// plus prioritaire ; forme absente ou sans sens : pas proposée.
    func testPageWordsAreFoundByTheirFormWithTheRightReading() throws {
        let a = try dictionary("A", terms: [("上手", "じょうず", "[\"habile\"]"), ("上手", "うわて", "[\"supérieur\"]"),
                                            ("床", "ゆか", "[\"sol\"]"), ("空", "そら", "null")])
        let found = try db.lexiconWords(dictionaryIds: [a], expressions: [("上手", "うわて"), ("床", ""), ("無い語", ""), ("空", "")])
        XCTAssertEqual(found["上手"]?.reading, "うわて")
        XCTAssertEqual(found["床"]?.summary(.unknown), "sol")
        XCTAssertNil(found["無い語"])
        XCTAssertNil(found["空"], "sans aucun sens : rien à mettre sur la carte")
        XCTAssertEqual(try db.lexiconWords(dictionaryIds: [a], expressions: [("上手", "")])["上手"]?.senses.isEmpty, false)
        XCTAssertTrue(try db.lexiconWords(dictionaryIds: [], expressions: [("床", "")]).isEmpty)
    }
}
