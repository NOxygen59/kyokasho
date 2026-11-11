// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB
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

    /// Revue DeepSeek n°1 : migration d'une base d'avant (v1, peuplée, sur disque) : index ajouté, cartes et FSRS intacts.
    func testMigrationFromAPopulatedV1Database() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("review-v1-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let queue = try DatabaseQueue(path: folder.appendingPathComponent("review.sqlite").path)
            try ReviewStore.migrator.migrate(queue, upTo: "v1")
            try queue.write { db in
                var deck = Deck(name: "Kyōkasho")
                try deck.insert(db)
                var template = NoteTemplate.japaneseWord
                try template.insert(db)
                var card = StudyCard(deckId: try XCTUnwrap(deck.id), templateId: try XCTUnwrap(template.id), key: "図|ず",
                                     fields: ["Mot": "図"], sourceDocumentId: "d", sourcePage: 2)
                card.reps = 3
                card.stability = 9
                try card.insert(db)
            }
            XCTAssertFalse(try queue.read { try $0.indexes(on: "card").map(\.name) }.contains("card_source"))
            try queue.close()
        }
        let store = try ReviewStore.open(directory: folder)
        XCTAssertTrue(try store.writer.read { try $0.indexes(on: "card").map(\.name) }.contains("card_source"))
        let card = try XCTUnwrap(store.cards(sourceDocumentId: "d").first)
        XCTAssertEqual(card.reps, 3)
        XCTAssertEqual(card.stability, 9)
        XCTAssertEqual(card.key, "図|ず")
    }

    /// Revue DeepSeek n°2 : après un remplacement Drive, l'écran du nouveau document retrouve ses cartes, dans l'ordre.
    func testCardsFollowADriveReplacementInPageThenCreationOrder() throws {
        let store = try ReviewStore.inMemory()
        _ = try add(store, "b|b", word: "b", reading: "b", document: "old", page: 4, at: 20)
        _ = try add(store, "a|a", word: "a", reading: "a", document: "old", page: 4, at: 10)
        _ = try add(store, "c|c", word: "c", reading: "c", document: "old", page: 1, at: 30)
        XCTAssertEqual(try store.remapDocumentId(from: "old", to: "new"), 3)
        XCTAssertEqual(try store.cards(sourceDocumentId: "new").map(\.key), ["c|c", "a|a", "b|b"])
        XCTAssertTrue(try store.cards(sourceDocumentId: "old").isEmpty)
    }

    /// Revue DeepSeek n°7 : « % » et « _ » sont cherchés tels quels.
    func testSearchIsLiteral() throws {
        let store = try ReviewStore.inMemory()
        _ = try add(store, "百|ひゃく", word: "100 %", reading: "ひゃく", document: "d", page: 1, at: 1)
        _ = try add(store, "他|た", word: "1000", reading: "た", document: "d", page: 1, at: 2)
        XCTAssertEqual(try store.cards(sourceDocumentId: "d", query: "0 %").count, 1)
        XCTAssertEqual(try store.cards(sourceDocumentId: "d", query: "_").count, 0)
    }

    /// Revue DeepSeek n°9 : une révision faite après l'ouverture de l'éditeur n'est pas écrasée à l'enregistrement.
    func testSavingAnOldEditorCopyNeverRewindsTheSchedule() throws {
        let store = try ReviewStore.inMemory()
        var editorCopy = try add(store, "図|ず", word: "図", reading: "ず", document: "d", page: 1, at: 1)
        var reviewed = editorCopy
        reviewed.reps = 4
        reviewed.stability = 20
        try store.writer.write { try reviewed.update($0) }
        editorCopy.fields["Sens"] = "plan"
        let saved = try store.saveEdited(editorCopy)
        XCTAssertEqual(saved.reps, 4)
        XCTAssertEqual(saved.stability, 20)
        XCTAssertEqual(saved.fields["Sens"], "plan")
    }

    /// Revue DeepSeek n°4 : un sens en liste HTML reste lisible sur une ligne.
    func testOneLineMeaningSeparatesListItems() {
        XCTAssertEqual(CardTemplate.oneLine("<ol><li>manger</li><li>repas</li></ol>"), "manger · repas")
        XCTAssertEqual(CardTemplate.oneLine("plan<br>dessin"), "plan · dessin")
        XCTAssertEqual(CardTemplate.oneLine("simple"), "simple")
    }
}
