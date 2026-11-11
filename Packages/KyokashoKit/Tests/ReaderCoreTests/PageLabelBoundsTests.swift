// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// BUG-002 (audit Fable du 10/11/2026) : `pageLabel` indexait la table des numéros imprimés sans contrôle. Une note
/// ou un repère resté sur une page qui n'existe plus (cours remplacé par une version plus courte, puis pages
/// modifiées) arrêtait l'app à l'affichage de son libellé.
final class PageLabelBoundsTests: XCTestCase {
    private let id = "page-label-bounds-\(UUID().uuidString)"

    override func tearDown() {
        PrintedPageNumbers.set([:])
        super.tearDown()
    }

    func testLabelOutsideThePagesDoesNotCrashWhenPagesHaveIdentities() {
        let document = LibraryDocument(id: id, title: "t", originalFileName: "t.pdf", pageCount: 3, fileSize: 1)
        PrintedPageNumbers.set([id: [nil, 1, 2]])
        XCTAssertEqual(document.pageLabel(1), "1")
        XCTAssertEqual(document.pageLabel(0), "i")
        // Au-delà de la dernière page, et avant la première : repli en chiffres romains, comme sans identités.
        XCTAssertEqual(document.pageLabel(7), "viii")
        XCTAssertEqual(document.pageLabel(-1), "i")
    }
}
