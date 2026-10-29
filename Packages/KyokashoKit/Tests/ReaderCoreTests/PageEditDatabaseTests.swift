// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
@testable import ReaderCore

/// Base synthétique en mémoire uniquement.
final class PageEditDatabaseTests: XCTestCase {
    var db: AppDatabase!

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
        var doc = LibraryDocument(id: "d", title: "Test", originalFileName: "t.pdf", pageCount: 5, fileSize: 1)
        doc.lastPageIndex = 2
        doc.firstPageIndex = 1
        try db.save(doc)
        try db.save(LibraryDocument(id: "autre", title: "Autre", originalFileName: "a.pdf", pageCount: 5, fileSize: 1))
        for page in 0..<5 {
            try db.save(PageComment(documentId: "d", pageIndex: page, body: "note \(page)"))
            try db.save(InkDrawing(documentId: "d", pageIndex: page, data: Data([UInt8(page)])), isEmpty: false)
        }
        try db.save(Highlight(documentId: "d", pageIndex: 2, rects: [], color: .yellow, text: "surligné"))
        try db.save(PageComment(documentId: "autre", pageIndex: 2, body: "autre document"))
    }

    private func notes() throws -> [String] { try db.comments(documentId: "d").map { "\($0.pageIndex):\($0.body)" } }

    func testRemovalArchivesThenRemapsEverythingInOneTransaction() throws {
        let mapping = try PageMapping.removal(oldCount: 5, removing: [1, 2])
        XCTAssertTrue(try db.remapPages(documentId: "d", mapping: mapping, editId: "e1", kind: .removal,
                                        expectedVersion: 0, fileSize: 7))
        XCTAssertEqual(try notes(), ["0:note 0", "1:note 3", "2:note 4"])
        XCTAssertEqual(try db.inkDrawing(documentId: "d", pageIndex: 1)?.data, Data([3]))
        XCTAssertTrue(try db.highlights(documentId: "d").isEmpty)
        let doc = try XCTUnwrap(db.document(id: "d"))
        XCTAssertEqual([doc.pageCount, Int(doc.fileSize), doc.lastPageIndex, doc.firstPageIndex], [3, 7, 1, 1])
        XCTAssertEqual(try db.layoutVersion(documentId: "d"), 1)
        // Archive : 2 notes + 2 dessins + 1 surlignage, reliés à l'identité de leur page.
        let archived = try db.archivedRows(editId: "e1")
        XCTAssertEqual(archived.map(\.tableName).sorted(), ["highlight", "inkDrawing", "inkDrawing", "pageComment", "pageComment"])
        let edit = try XCTUnwrap(db.pageEdit(id: "e1"))
        XCTAssertEqual(Set(archived.map(\.pageId)), Set([edit.pageOrder[1], edit.pageOrder[2]]))
        XCTAssertEqual(archived.first { $0.tableName == "pageComment" && $0.columns["body"] == .text("note 1") }?.pageId, edit.pageOrder[1])
        // Autre document intact.
        XCTAssertEqual(try db.comments(documentId: "autre").map(\.pageIndex), [2])
    }

    func testIdentitiesKeepPrintedNumbersAcrossARemovalInTheMiddle() throws {
        try db.remapPages(documentId: "d", mapping: PageMapping.removal(oldCount: 5, removing: [2]), editId: "e1",
                          kind: .removal, expectedVersion: 0, fileSize: 1)
        let identities = try db.pageIdentities(documentId: "d")
        XCTAssertEqual(identities.map(\.position), [0, 1, 2, 3])
        XCTAssertEqual(identities.map(\.printedNumber), [nil, 1, 3, 4], "les numéros imprimés ne glissent pas")
    }

    func testSameEditIdIsNotAppliedTwice() throws {
        let mapping = try PageMapping.removal(oldCount: 5, removing: [0])
        try db.remapPages(documentId: "d", mapping: mapping, editId: "e1", kind: .removal, expectedVersion: 0, fileSize: 1)
        XCTAssertFalse(try db.remapPages(documentId: "d", mapping: mapping, editId: "e1", kind: .removal, expectedVersion: 0, fileSize: 1))
        XCTAssertEqual(try notes(), ["0:note 1", "1:note 2", "2:note 3", "3:note 4"])
        XCTAssertEqual(try db.archivedRows(editId: "e1").count, 2)
    }

    func testSamePageCountButOtherVersionIsRefusedWithoutEffect() throws {
        try db.remapPages(documentId: "d", mapping: PageMapping.insertion(oldCount: 5, inserted: 1, at: 0), editId: "e1",
                          kind: .insertion, expectedVersion: 0, fileSize: 1)
        try db.remapPages(documentId: "d", mapping: PageMapping.removal(oldCount: 6, removing: [5]), editId: "e2",
                          kind: .removal, expectedVersion: 1, fileSize: 1)
        let before = try notes()
        // Même nombre de pages (5) qu'au départ, mais version 2 : une opération préparée en version 0 est refusée.
        XCTAssertThrowsError(try db.remapPages(documentId: "d", mapping: PageMapping.removal(oldCount: 5, removing: [0]),
                                               editId: "e3", kind: .removal, expectedVersion: 0, fileSize: 1))
        XCTAssertEqual(try notes(), before)
        XCTAssertNil(try db.pageEdit(id: "e3"))
    }

    func testInsertionMatchesTheOldShiftAndGivesNewIdentities() throws {
        let reference = try AppDatabase.inMemory()
        var doc = try XCTUnwrap(db.document(id: "d"))
        try reference.save(doc)
        for page in 0..<5 { try reference.save(PageComment(documentId: "d", pageIndex: page, body: "note \(page)")) }
        try reference.shiftPages(documentId: "d", by: 2, pageCount: 7, fileSize: 9)

        try db.remapPages(documentId: "d", mapping: PageMapping.insertion(oldCount: 5, inserted: 2, at: 0), editId: "e1",
                          kind: .insertion, expectedVersion: 0, fileSize: 9)
        XCTAssertEqual(try db.comments(documentId: "d").map(\.pageIndex), try reference.comments(documentId: "d").map(\.pageIndex))
        doc = try XCTUnwrap(db.document(id: "d"))
        let expected = try XCTUnwrap(reference.document(id: "d"))
        XCTAssertEqual([doc.pageCount, doc.lastPageIndex, doc.firstPageIndex], [expected.pageCount, expected.lastPageIndex, expected.firstPageIndex])
        let identities = try db.pageIdentities(documentId: "d")
        XCTAssertEqual(identities.count, 7)
        XCTAssertEqual(Set(identities.map(\.pageId)).count, 7)
        XCTAssertEqual(identities.prefix(2).map(\.printedNumber), [nil, nil])
        XCTAssertTrue(try db.archivedRows(editId: "e1").isEmpty)
    }

    func testReadingPositionMovesToTheNearestRemainingPage() throws {
        // lastPageIndex = 2 retirée avec 3 : on arrive sur l'ancienne 4 (nouvelle 2).
        try db.remapPages(documentId: "d", mapping: PageMapping.removal(oldCount: 5, removing: [2, 3]), editId: "e1",
                          kind: .removal, expectedVersion: 0, fileSize: 1)
        XCTAssertEqual(try db.document(id: "d")?.lastPageIndex, 2)
        XCTAssertEqual(AppDatabase.nearest(4, in: try PageMapping.removal(oldCount: 5, removing: [3, 4])), 2)
    }

    func testIncoherentIdentitiesStopTheEdit() throws {
        try db.writer.write { db in
            try db.execute(sql: "INSERT INTO pageIdentity (documentId, position, pageId) VALUES ('d', 0, 'x')")
        }
        XCTAssertThrowsError(try db.remapPages(documentId: "d", mapping: PageMapping.removal(oldCount: 5, removing: [0]),
                                               editId: "e1", kind: .removal, expectedVersion: 0, fileSize: 1))
        XCTAssertEqual(try notes().count, 5)
    }

    func testDeletingTheDocumentDeletesItsArchives() throws {
        try db.remapPages(documentId: "d", mapping: PageMapping.removal(oldCount: 5, removing: [1]), editId: "e1",
                          kind: .removal, expectedVersion: 0, fileSize: 1)
        try db.deleteDocument(id: "d")
        XCTAssertNil(try db.pageEdit(id: "e1"))
        XCTAssertTrue(try db.archivedRows(editId: "e1").isEmpty)
    }
}
