// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import XCTest
@testable import ReviewKit

/// C2.2 (Lot C2, fiche f85d0c0, DEC-C2 = A) — quand un cours est remplacé par une version mise à
/// jour, ses cartes restent liées à l'ancien identifiant de document : la recherche « cartes de ce
/// livre » ne les trouve plus et un ajout de pages plus tard les ignore. `remapDocumentId(from:to:)`
/// les rattache au nouvel identifiant sans toucher à la planification FSRS ni à l'historique.
final class RemapDocumentIdTests: XCTestCase {
    func testRemapMovesOnlyTheReplacedDocumentCards() throws {
        let store = try ReviewStore.inMemory()
        let deck = try XCTUnwrap(store.decks().first)   // un paquet est déjà semé par inMemory()
        let template = try XCTUnwrap(store.templates().first)

        func card(_ key: String, document: String?) throws -> StudyCard {
            var c = StudyCard(deckId: try XCTUnwrap(deck.id), templateId: try XCTUnwrap(template.id),
                              key: key, fields: ["Mot": key], sourceDocumentId: document, sourcePage: document == nil ? nil : 3,
                              now: Date(timeIntervalSince1970: 1000))
            c.stability = 7
            c.difficulty = 5
            c.reps = 4
            c.state = .review
            c.due = Date(timeIntervalSince1970: 2000)
            return try store.add(c)
        }

        let linked = try card("図|ず", document: "old")
        let other = try card("木|き", document: "other")
        let detached = try card("sans livre", document: nil)

        let moved = try store.remapDocumentId(from: "old", to: "new")
        XCTAssertEqual(moved, 1)

        var expected = linked
        expected.sourceDocumentId = "new"
        XCTAssertEqual(try store.card(id: try XCTUnwrap(linked.id)), expected,
                       "la carte suit le cours mis à jour")
        XCTAssertEqual(try store.card(id: try XCTUnwrap(expected.id))?.sourcePage, 3,
                       "la page source est laissée en place")
        XCTAssertEqual(try store.card(id: try XCTUnwrap(other.id)), other,
                       "les cartes d'un autre book ne bougent pas")
        XCTAssertEqual(try store.card(id: try XCTUnwrap(detached.id)), detached,
                       "une carte sans document n'est pas rattachée")
        XCTAssertEqual(try store.history(cardId: try XCTUnwrap(expected.id)).count, 0,
                       "l'historique n'est pas touché")
    }

    /// Une reprise de bascule interrompue rejoue le remplacement : aucun double effet ni erreur.
    func testRemapIsReplayable() throws {
        let store = try ReviewStore.inMemory()
        let deck = try XCTUnwrap(store.decks().first)   // un paquet est déjà semé par inMemory()
        let template = try XCTUnwrap(store.templates().first)
        let c = StudyCard(deckId: try XCTUnwrap(deck.id), templateId: try XCTUnwrap(template.id),
                          key: "図|ず", fields: ["Mot": "図"], sourceDocumentId: "old", sourcePage: 0,
                          now: Date(timeIntervalSince1970: 1000))
        let saved = try store.add(c)

        XCTAssertEqual(try store.remapDocumentId(from: "old", to: "new"), 1)
        XCTAssertEqual(try store.remapDocumentId(from: "old", to: "new"), 0, "rejouable : rien de plus à déplacer")
        XCTAssertEqual(try store.sourcePages(documentId: "new"), [try XCTUnwrap(saved.id): 0])
        // `sourcePages` de l'ancien identifiant ne voit plus rien : la liste du livre reste cohérente.
        XCTAssertTrue(try store.sourcePages(documentId: "old").isEmpty)
        // Même identifiant : ce n'est pas un remplacement, la fonction ne fait rien.
        XCTAssertEqual(try store.remapDocumentId(from: "new", to: "new"), 0)
    }
}
