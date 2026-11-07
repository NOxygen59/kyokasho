// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Recette 1.3.2 (61), E5 : accueil en sections Manuels, Livres, Non classés.
final class LibrarySectionsTests: XCTestCase {
    private func doc(_ id: String, _ category: DocumentCategory?) -> LibraryDocument {
        LibraryDocument(id: id, title: id, originalFileName: "\(id).pdf", pageCount: 1, fileSize: 1, category: category)
    }

    func testTextbooksFirstThenBooksThenUncategorizedKeepingOrder() {
        let sections = LibrarySections.group([doc("b1", .book), doc("m1", .textbook), doc("n1", nil),
                                              doc("m2", .textbook), doc("b2", .book)])
        XCTAssertEqual(sections.map(\.title), ["Manuels", "Livres", "Non classés"])
        XCTAssertEqual(sections[0].documents.map(\.id), ["m1", "m2"])
        XCTAssertEqual(sections[1].documents.map(\.id), ["b1", "b2"])
    }

    func testEmptySectionsAreHidden() {
        XCTAssertEqual(LibrarySections.group([doc("b", .book)]).map(\.title), ["Livres"])
        XCTAssertTrue(LibrarySections.group([]).isEmpty)
    }

    func testCardIdentityChangesWithCategoryAndSelectionMode() {
        let initial = LibraryCardRenderIdentity(documentId: "d", category: nil, selecting: false)
        XCTAssertNotEqual(initial, LibraryCardRenderIdentity(documentId: "d", category: .book, selecting: false))
        XCTAssertNotEqual(initial, LibraryCardRenderIdentity(documentId: "d", category: nil, selecting: true))
        XCTAssertEqual(initial, LibraryCardRenderIdentity(documentId: "d", category: nil, selecting: false))
    }

    // Espace Manga en deux sections, comme Livres et Manuels (demande de NOxygen59, 07/11/2026) : les mangas PDF d'abord,
    // puis les CBZ. Une section vide n'apparaît pas ; l'ordre des documents est gardé.

    private func mangaDoc(_ id: String, file: String) -> LibraryDocument {
        LibraryDocument(id: id, title: id, originalFileName: file, pageCount: 1, fileSize: 1)
    }

    func testMangaSpaceSplitsPDFMangaAndCBZ() {
        let sections = LibrarySections.groupManga([mangaDoc("a", file: "a.cbz"), mangaDoc("b", file: "b.pdf"), mangaDoc("c", file: "c.cbz")])
        XCTAssertEqual(sections.map { $0.documents.map(\.id) }, [["b"], ["a", "c"]])
    }

    func testEmptyMangaSectionIsHidden() {
        let sections = LibrarySections.groupManga([mangaDoc("a", file: "a.cbz")])
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.documents.map(\.id), ["a"])
        XCTAssertTrue(LibrarySections.groupManga([]).isEmpty)
    }
}
