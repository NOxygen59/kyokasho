// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
@testable import ReaderCore

/// RET-039 (#54) : catégorie livre/manuel, migration `v5-document-category` sur une base synthétique jetable.
final class DocumentCategoryTests: XCTestCase {
    private func temporaryDatabase() throws -> (AppDatabase, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kyokasho-category-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("kyokasho.sqlite")
        return (try AppDatabase.open(at: path), path)
    }

    func testOlderDatabaseMigratesWithDocumentsUncategorized() throws {
        let (database, path) = try temporaryDatabase()
        let doc = LibraryDocument(id: "ancien", title: "Ancien", originalFileName: "a.pdf", pageCount: 3, fileSize: 1,
                                  lastPageIndex: 2, firstPageIndex: 1)
        try database.save(doc)
        // Revenir au schéma v4 : colonne et migration v5 retirées.
        try database.writer.write { db in
            try db.execute(sql: "ALTER TABLE document DROP COLUMN category")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v5-document-category'")
        }
        try database.writer.close()
        let reopened = try AppDatabase.open(at: path)
        let migrated = try XCTUnwrap(reopened.document(id: "ancien"))
        XCTAssertNil(migrated.category)
        XCTAssertEqual(migrated.lastPageIndex, 2)
        XCTAssertEqual(migrated.firstPageIndex, 1)
        try reopened.writer.close()
    }

    func testUpdateCategoryChangesOnlyCategory() throws {
        let (database, _) = try temporaryDatabase()
        try database.save(LibraryDocument(id: "d", title: "Titre", originalFileName: "d.pdf", pageCount: 9, fileSize: 1,
                                          lastPageIndex: 4))
        try database.updateCategory(documentId: "d", category: .textbook)
        var doc = try XCTUnwrap(database.document(id: "d"))
        XCTAssertEqual(doc.category, .textbook)
        XCTAssertEqual(doc.title, "Titre")
        XCTAssertEqual(doc.lastPageIndex, 4)
        try database.updateCategory(documentId: "d", category: nil)
        doc = try XCTUnwrap(database.document(id: "d"))
        XCTAssertNil(doc.category)
        try database.writer.close()
    }

    func testCategoryRoundTripsThroughSave() throws {
        let (database, _) = try temporaryDatabase()
        try database.save(LibraryDocument(id: "b", title: "B", originalFileName: "b.pdf", pageCount: 1, fileSize: 1,
                                          category: .book))
        XCTAssertEqual(try database.document(id: "b")?.category, .book)
        XCTAssertEqual(DocumentCategory.allCases.map(\.title), ["Livre", "Manuel", "Comics"])
        try database.writer.close()
    }
}
