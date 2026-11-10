// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import DictionaryKit

/// PLAN-LEX-001, étapes E2 et E3 : état de la liste du Lexique (défilement sans fin, recherche, réponses tardives).
final class LexiconFeedTests: XCTestCase {
    private func word(_ expression: String, _ reading: String, fr: String? = nil, en: String? = nil) -> LexiconWord {
        var senses: [LexiconSense] = []
        if let fr { senses.append(LexiconSense(dictionaryId: 1, dictionaryTitle: "fr", language: .french, short: fr, full: fr)) }
        if let en { senses.append(LexiconSense(dictionaryId: 2, dictionaryTitle: "en", language: .english, short: en, full: en)) }
        return LexiconWord(expression: expression, reading: reading == expression ? nil : reading, sortReading: reading,
                           senses: senses)
    }

    private func page(_ range: Range<Int>, last: Bool = false) -> LexiconPage {
        let words = range.map { word("語\($0)", "ご\(String(format: "%04d", $0))") }
        let cursor = words.last.map { LexiconCursor(reading: $0.sortReading, expression: $0.expression) }
        return LexiconPage(words: words, next: last ? nil : cursor)
    }

    func testPagesAreAppendedInOrderUntilTheEnd() throws {
        var feed = LexiconFeed()
        feed.reset()
        var start = try XCTUnwrap(feed.beginLoading())
        XCTAssertNil(start.after)
        XCTAssertNil(feed.beginLoading(), "une seule lecture à la fois")
        XCTAssertTrue(feed.accept(page(0..<100), request: start.request))
        XCTAssertFalse(feed.reachedEnd)
        start = try XCTUnwrap(feed.beginLoading())
        XCTAssertEqual(start.after, LexiconCursor(reading: "ご0099", expression: "語99"))
        XCTAssertTrue(feed.accept(page(100..<150, last: true), request: start.request))
        XCTAssertEqual(feed.words.count, 150)
        XCTAssertTrue(feed.reachedEnd)
        XCTAssertNil(feed.beginLoading(), "plus rien à lire après la dernière page")
    }

    func testNextPageIsAskedNearTheEndOnly() throws {
        var feed = LexiconFeed()
        feed.reset()
        let start = try XCTUnwrap(feed.beginLoading())
        XCTAssertFalse(feed.shouldLoadMore(appearing: "x"), "rien pendant une lecture")
        feed.accept(page(0..<100), request: start.request)
        XCTAssertFalse(feed.shouldLoadMore(appearing: feed.words[10].id))
        XCTAssertTrue(feed.shouldLoadMore(appearing: feed.words[99].id))
        XCTAssertTrue(feed.shouldLoadMore(appearing: feed.words[100 - LexiconFeed.prefetchDistance].id))
    }

    func testLateAnswerOfAnOldSearchIsDiscarded() throws {
        var feed = LexiconFeed()
        feed.reset()
        let old = try XCTUnwrap(feed.beginLoading())
        // L'utilisateur tape une recherche pendant la première lecture.
        feed.reset(prefix: "  てん ")
        XCTAssertEqual(feed.prefix, "てん")
        let current = try XCTUnwrap(feed.beginLoading())
        XCTAssertEqual(current.prefix, "てん")
        XCTAssertFalse(feed.accept(page(0..<100), request: old.request))
        XCTAssertTrue(feed.words.isEmpty)
        XCTAssertTrue(feed.isLoading, "la lecture en cours n'est pas confondue avec l'ancienne")
        feed.fail(request: old.request)
        XCTAssertTrue(feed.isLoading)
        XCTAssertTrue(feed.accept(page(0..<3, last: true), request: current.request))
        XCTAssertEqual(feed.words.count, 3)
    }

    func testAWordAlreadyShownIsNotAddedTwice() throws {
        var feed = LexiconFeed()
        feed.reset()
        var start = try XCTUnwrap(feed.beginLoading())
        feed.accept(page(0..<10), request: start.request)
        start = try XCTUnwrap(feed.beginLoading())
        // Base changée entre deux pages : la page suivante reprend deux mots déjà affichés.
        feed.accept(page(8..<15, last: true), request: start.request)
        XCTAssertEqual(feed.words.count, 15)
        XCTAssertEqual(Set(feed.words.map(\.id)).count, 15)
    }

    func testAFailedReadCanBeRetried() throws {
        var feed = LexiconFeed()
        feed.reset()
        let start = try XCTUnwrap(feed.beginLoading())
        feed.fail(request: start.request)
        XCTAssertFalse(feed.isLoading)
        XCTAssertNotNil(feed.beginLoading())
    }

    func testMissingSenseIsNilAndNothingIsInvented() {
        // DEC-02 : sens absent dans une langue = `nil` (l'écran affiche « — »), jamais l'autre langue recopiée.
        let onlyEnglish = word("天井", "てんじょう", en: "ceiling")
        XCTAssertNil(onlyEnglish.summary(.french))
        XCTAssertEqual(onlyEnglish.summary(.english), "ceiling")
        XCTAssertNil(word("床", "ゆか").summary(.english))
    }

    func testFuriganaFollowTheKanjiAndDisappearWithoutReading() {
        XCTAssertEqual(word("食べ物", "たべもの").furigana.map(\.reading), ["た", "", "もの"])
        // DEC-04 : lecture qui répète le mot = pas de lecture affichée.
        let kana = word("てんじょう", "てんじょう")
        XCTAssertEqual(kana.furigana.map(\.text), ["てんじょう"])
        XCTAssertEqual(kana.furigana.map(\.reading), [""])
    }
}
