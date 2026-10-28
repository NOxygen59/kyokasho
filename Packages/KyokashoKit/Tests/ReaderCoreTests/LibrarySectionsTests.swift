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
}
