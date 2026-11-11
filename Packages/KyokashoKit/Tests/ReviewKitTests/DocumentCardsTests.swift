// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import XCTest
@testable import ReviewKit

/// PLAN-CARTES-001, étape E1 : cartes d'un document et modification à la main (DEC-CA-07 = A).
final class DocumentCardsTests: XCTestCase {
    private func add(_ store: ReviewStore, _ key: String, word: String, reading: String, document: String?, page: Int?,
                     at time: TimeInterval) throws -> StudyCard {
        let deck = try XCTUnwrap(store.decks().first), template = try XCTUnwrap(store.templates().first)
        var card = StudyCard(deckId: try XCTUnwrap(deck.id), templateId: try XCTUnwrap(template.id), key: key,
                             fields: ["Mot": word, "Lecture": reading, "Sens": "sens"], sourceDocumentId: document,
                             sourcePage: page, now: Date(timeIntervalSince1970: time))
        card.reps = 3
        card.stability = 9
        card.state = .review
        return try store.add(card)
    }

    func testCardsOfADocumentAreAllReturnedByPageWithoutTheListLimit() throws {
        let store = try ReviewStore.inMemory()
        for i in 0..<600 { _ = try add(store, "語\(i)|ご", word: "語\(i)", reading: "ご", document: "d", page: 600 - i, at: Double(i)) }
        _ = try add(store, "他|た", word: "他", reading: "た", document: "other", page: 1, at: 1)
        let cards = try store.cards(sourceDocumentId: "d")
        XCTAssertEqual(cards.count, 600, "pas de limite de 500")
        XCTAssertEqual(cards.first?.sourcePage, 1)
        XCTAssertEqual(try store.cards(sourceDocumentId: "d", query: "語599").count, 1)
    }

    func testIndexExistsAfterMigration() throws {
        let store = try ReviewStore.inMemory()
        let indexes = try store.writer.read { try $0.indexes(on: "card").map(\.name) }
        XCTAssertTrue(indexes.contains("card_source"))
    }

    func testEditingTheMeaningKeepsKeyAndHistory() throws {
        let store = try ReviewStore.inMemory()
        // Clé venue du dictionnaire (lecture en kana) différente du texte du champ : elle ne doit pas bouger.
        var card = try add(store, "図|ず", word: "図", reading: "<b>ず</b>", document: "d", page: 1, at: 1)
        card.fields["Sens"] = "plan, dessin"
        let saved = try store.saveEdited(card)
        XCTAssertEqual(saved.key, "図|ず")
        XCTAssertEqual(saved.reps, 3)
        XCTAssertEqual(saved.stability, 9)
    }

    func testEditingTheWordMovesTheKeyButNeverTheHistory() throws {
        let store = try ReviewStore.inMemory()
        var card = try add(store, "図|ず", word: "図", reading: "ず", document: "d", page: 1, at: 1)
        let guid = card.guid
        card.fields["Lecture"] = "と"
        let saved = try store.saveEdited(card)
        XCTAssertEqual(saved.key, "図|と")
        XCTAssertEqual(saved.guid, guid, "même note Anki")
        XCTAssertEqual(try store.card(id: XCTUnwrap(saved.id))?.reps, 3)
    }

    func testEditingIntoAnExistingWordIsRefused() throws {
        let store = try ReviewStore.inMemory()
        _ = try add(store, "木|き", word: "木", reading: "き", document: "x", page: 1, at: 1)
        var card = try add(store, "図|ず", word: "図", reading: "ず", document: "d", page: 1, at: 2)
        card.fields["Mot"] = "木"
        card.fields["Lecture"] = "き"
        XCTAssertThrowsError(try store.saveEdited(card)) { XCTAssertEqual($0 as? ReviewStore.EditError, .duplicate) }
        XCTAssertEqual(try store.card(id: XCTUnwrap(card.id))?.key, "図|ず", "rien enregistré")
    }
}
