// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Recette 1.3.2 (62), N1 : modifier le texte d'une note dans la liste.
final class NoteEditTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_800_000_000)

    func testEditChangesBodyAndDate() {
        let note = PageComment(documentId: "d", pageIndex: 3, body: "天井")
        let edited = note.editing(body: "  天井を張る \n", at: t)
        XCTAssertEqual(edited?.body, "天井を張る")
        XCTAssertEqual(edited?.updatedAt, t)
        XCTAssertEqual(edited?.id, note.id)
        XCTAssertEqual(edited?.createdAt, note.createdAt)
    }

    func testNoChangeOrEmptyTextIsRefused() {
        let note = PageComment(documentId: "d", pageIndex: 0, body: "a")
        XCTAssertNil(note.editing(body: "a "))
        XCTAssertNil(note.editing(body: "   "))
        var drawn = note
        drawn.drawing = Data([1])
        XCTAssertEqual(drawn.editing(body: "")?.body, "")
    }
}
