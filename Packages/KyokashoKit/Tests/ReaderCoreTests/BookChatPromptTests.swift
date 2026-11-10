// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// T2 (retours terrain du 10/11/2026) : le chat d'un livre répond aussi aux questions générales en le signalant,
/// et ne liste que les pages qu'il cite.
final class BookChatPromptTests: XCTestCase {
    func testContextAllowsGeneralKnowledgeWithMarker() {
        let context = BookChatPrompt.context(sources: "[p. 3] Lecture non recoupée.\n…")
        XCTAssertFalse(context.contains("uniquement les extraits"), "ancienne consigne restrictive revenue")
        XCTAssertTrue(context.contains("connaissances générales"))
        XCTAssertTrue(context.contains(BookChatPrompt.generalMarker))
        XCTAssertTrue(context.contains("Ne cite jamais une page dont l'extrait ne sert pas"))
        XCTAssertTrue(context.hasSuffix("[p. 3] Lecture non recoupée.\n…"))
    }

    func testGeneralContextHasMarkerAndNoPages() {
        XCTAssertTrue(BookChatPrompt.generalContext.contains(BookChatPrompt.generalMarker))
        XCTAssertTrue(BookChatPrompt.generalContext.contains("Ne cite aucune page"))
    }

    func testCitedLabels() {
        let answer = "Voir [p. 12] puis [p. 3, 4] et encore [p. 12]. Pas une page : [note]."
        XCTAssertEqual(BookChatPrompt.citedLabels(in: answer), ["12", "3", "4"])
        XCTAssertEqual(BookChatPrompt.citedLabels(in: "Rien ici"), [])
        XCTAssertEqual(BookChatPrompt.citedLabels(in: "Crochet ouvert [p. 5"), [])
        XCTAssertEqual(BookChatPrompt.citedLabels(in: "[p. ii]"), ["ii"])
    }

    func testOnlyCitedPassagesAreKept() {
        let passages = [(page: 10, label: "11"), (page: 2, label: "3"), (page: 40, label: "41")]
        XCTAssertEqual(BookChatPrompt.citedPages(in: "D'après [p. 41] et [p. 11].", passages: passages), [10, 40])
        // Question générale : aucune page citée, aucune page listée.
        XCTAssertEqual(BookChatPrompt.citedPages(in: "\(BookChatPrompt.generalMarker) Un verbe…", passages: passages), [])
        // Page inventée hors des extraits : ignorée.
        XCTAssertEqual(BookChatPrompt.citedPages(in: "[p. 99]", passages: passages), [])
    }

    func testRangesAndCaseFromReviewD07() {
        XCTAssertEqual(BookChatPrompt.citedLabels(in: "[p. 12-13] [p. 14–15] [p. 16 et 17] [p.18]"),
                       ["12", "13", "14", "15", "16", "17", "18"])
        let passages = [(page: 2, label: "iii"), (page: 20, label: "13")]
        XCTAssertEqual(BookChatPrompt.citedPages(in: "Voir [p. III] et [p. 12-13].", passages: passages), [2, 20])
    }

    func testListedPagesFallback() {
        let passages = [(page: 4, label: "5"), (page: 9, label: "10")]
        // Prose sans [p. N], appuyée sur le manuel : les extraits restent listés.
        XCTAssertEqual(BookChatPrompt.listedPages(in: "Comme le dit la page 5, …", passages: passages), [4, 9])
        // Explication générale : aucune page.
        XCTAssertEqual(BookChatPrompt.listedPages(in: "\(BookChatPrompt.generalMarker) …", passages: passages), [])
        // Citation précise : seulement elle.
        XCTAssertEqual(BookChatPrompt.listedPages(in: "[p. 10]", passages: passages), [9])
    }
}
