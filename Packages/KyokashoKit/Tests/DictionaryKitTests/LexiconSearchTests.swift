// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
@testable import DictionaryKit

/// PLAN-LEX-001, étape E3 : la recherche du Lexique, de la base à la liste (mêmes gestes que la recette : chercher
/// « てんじょう », puis « 天井 », puis effacer la recherche).
final class LexiconSearchTests: XCTestCase {
    private var db: DictionaryDatabase!
    private var ids: Set<Int64> = []

    override func setUpWithError() throws {
        db = try DictionaryDatabase.inMemory()
        var terms: [(String, String, String)] = [("天井", "てんじょう", "[\"plafond\"]"), ("天井板", "てんじょういた", "[\"lambris de plafond\"]"),
                                                 ("店舗", "てんぽ", "[\"boutique\"]"), ("畳", "たたみ", "[\"tatami\"]")]
        // Assez de mots au même début pour forcer plusieurs pages pendant une recherche.
        for i in 0..<120 { terms.append(("天\(i)", "てん\(String(format: "%03d", i))", "[\"sens \(i)\"]")) }
        ids = [try db.writer.write { d in
            var info = DictionaryInfo(title: "Synthétique", revision: "1", format: 3, priority: 0, enabled: true,
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
        }]
    }

    /// Fait défiler la liste jusqu'au bout, comme l'écran : une page à la fois, par la clé de reprise de `LexiconFeed`.
    private func scrollToEnd(_ feed: inout LexiconFeed, limit: Int) throws {
        var guardCount = 0
        while let start = feed.beginLoading() {
            let page = try db.lexiconPage(dictionaryIds: ids, after: start.after, prefix: start.prefix, limit: limit)
            XCTAssertTrue(feed.accept(page, request: start.request))
            guardCount += 1
            XCTAssertLessThan(guardCount, 1_000, "boucle sans fin")
        }
    }

    func testSearchByReadingThenByKanjiThenCleared() throws {
        var feed = LexiconFeed()
        feed.reset(prefix: "てんじょう")
        try scrollToEnd(&feed, limit: 20)
        XCTAssertEqual(feed.words.map(\.expression), ["天井", "天井板"])

        feed.reset(prefix: "天井")
        try scrollToEnd(&feed, limit: 20)
        XCTAssertEqual(feed.words.map(\.expression), ["天井", "天井板"])
        XCTAssertEqual(feed.words.first?.summary(.french), nil, "titre inconnu : aucune langue devinée")

        // Recherche effacée : toute la liste revient, sans doublon, dans l'ordre des lectures.
        feed.reset(prefix: "")
        try scrollToEnd(&feed, limit: 20)
        XCTAssertEqual(feed.words.count, 124)
        XCTAssertEqual(Set(feed.words.map(\.id)).count, 124)
        XCTAssertEqual(feed.words.map(\.sortReading), feed.words.map(\.sortReading).sorted())
    }

    func testSearchSpanningSeveralPagesHasNoDuplicateNorGap() throws {
        var feed = LexiconFeed()
        feed.reset(prefix: "てん")
        try scrollToEnd(&feed, limit: 20)
        // 120 mots synthétiques + 天井, 天井板, 店舗 ; 畳 (たたみ) n'en fait pas partie.
        XCTAssertEqual(feed.words.count, 123)
        XCTAssertEqual(Set(feed.words.map(\.id)).count, 123)
        XCTAssertFalse(feed.words.contains { $0.expression == "畳" })
        XCTAssertTrue(feed.reachedEnd)
    }

    func testSearchWithoutResultEndsCleanly() throws {
        var feed = LexiconFeed()
        feed.reset(prefix: "ぬ")
        try scrollToEnd(&feed, limit: 20)
        XCTAssertTrue(feed.words.isEmpty)
        XCTAssertTrue(feed.reachedEnd)
    }
}
