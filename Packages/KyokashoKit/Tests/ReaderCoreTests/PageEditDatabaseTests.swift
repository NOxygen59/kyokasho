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
        XCTAssertEqual(archived.map(\.tableName).sorted(), ["highlight", "inkDrawing", "inkDrawing", "pageComment", "pageComment",
                                                          "pageIdentity", "pageIdentity"])
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
        XCTAssertEqual(try db.archivedRows(editId: "e1").count, 3, "note, dessin et identité de la page, une seule fois")
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

    // MARK: - Revue croisée de Codex sur S1 (29/10/2026)

    private func remove(_ pages: Set<Int>, oldCount: Int, id: String, version: Int) throws {
        try db.remapPages(documentId: "d", mapping: PageMapping.removal(oldCount: oldCount, removing: pages), editId: id,
                          kind: .removal, expectedVersion: version, fileSize: 1)
    }

    /// F1 : un remplacement Drive (autre PDF, autre nombre de pages, puis même nombre) n'empêche plus l'ajout suivant.
    func testF1DriveReplacementResetsIdentitiesAndAllowsTheNextEdit() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kyokasho-replace-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let importer = DocumentImporter(storage: DocumentStorage(root: folder), database: try AppDatabase.inMemory())
        let base = importer.database
        let v1 = try importer.importFile(at: try makePDF(pages: 3, marker: "a")).document
        try base.remapPages(documentId: v1.id, mapping: PageMapping.insertion(oldCount: 3, inserted: 1, at: 0), editId: "e1",
                            kind: .insertion, expectedVersion: 0, fileSize: 1)
        XCTAssertEqual(try base.pageIdentities(documentId: v1.id).count, 4)
        // Autre nombre de pages.
        let v2 = try importer.replace(documentId: v1.id, withFileAt: try makePDF(pages: 5, marker: "b"))
        XCTAssertTrue(try base.pageIdentities(documentId: v2.id).isEmpty, "identités refaites à la prochaine modification")
        XCTAssertEqual(try base.layoutVersion(documentId: v2.id), 2, "version changée sans opération : chaîne rompue")
        XCTAssertNotNil(try base.pageEdit(id: "e1"), "archive d'avant gardée")
        try base.remapPages(documentId: v2.id, mapping: PageMapping.insertion(oldCount: 5, inserted: 1, at: 5), editId: "e2",
                            kind: .insertion, expectedVersion: 2, fileSize: 1)
        XCTAssertEqual(try base.pageIdentities(documentId: v2.id).count, 6)
        // Même nombre de pages : les anciennes identités ne sont pas reprises sans preuve.
        let before = Set(try base.pageIdentities(documentId: v2.id).map(\.pageId))
        let v3 = try importer.replace(documentId: v2.id, withFileAt: try makePDF(pages: 6, marker: "c"))
        try base.remapPages(documentId: v3.id, mapping: PageMapping.removal(oldCount: 6, removing: [0]), editId: "e3",
                            kind: .removal, expectedVersion: 4, fileSize: 1)
        XCTAssertTrue(before.isDisjoint(with: try base.pageIdentities(documentId: v3.id).map(\.pageId)))
    }

    /// F2 : un identifiant déjà enregistré n'est reconnu que pour la même opération, sur le document qu'elle a produit.
    func testF2ReplayIsAcceptedOnlyForTheSameOperationInItsFinalState() throws {
        let mapping = try PageMapping.removal(oldCount: 5, removing: [1])
        try db.remapPages(documentId: "d", mapping: mapping, editId: "op", kind: .removal, expectedVersion: 0, fileSize: 1)
        // Reprise authentique : idempotente.
        XCTAssertFalse(try db.remapPages(documentId: "d", mapping: mapping, editId: "op", kind: .removal, expectedVersion: 0, fileSize: 1))
        let notes = try notes()
        XCTAssertThrowsError(try db.remapPages(documentId: "autre", mapping: mapping, editId: "op", kind: .removal, expectedVersion: 0, fileSize: 1))
        XCTAssertThrowsError(try db.remapPages(documentId: "d", mapping: PageMapping.removal(oldCount: 5, removing: [2]), editId: "op",
                                               kind: .removal, expectedVersion: 0, fileSize: 1))
        XCTAssertThrowsError(try db.remapPages(documentId: "d", mapping: mapping, editId: "op", kind: .removal, expectedVersion: 99, fileSize: 1))
        XCTAssertThrowsError(try db.remapPages(documentId: "d", mapping: mapping, editId: "op", kind: .insertion, expectedVersion: 0, fileSize: 1))
        XCTAssertThrowsError(try db.remapPages(documentId: "d", mapping: mapping, editId: "op", kind: .removal, expectedVersion: 0, fileSize: 2))
        // Ancien rejeu après une opération ultérieure : refusé.
        try remove([0], oldCount: 4, id: "op2", version: 1)
        XCTAssertThrowsError(try db.remapPages(documentId: "d", mapping: mapping, editId: "op", kind: .removal, expectedVersion: 0, fileSize: 1))
        XCTAssertEqual(try self.notes().count, notes.count - 1)
        XCTAssertEqual(try db.comments(documentId: "autre").map(\.pageIndex), [2])
    }

    /// F3 : l'identité d'une page retirée (numéro imprimé compris, même absent) est archivée, après plusieurs modifications.
    func testF3RemovedIdentitiesAreArchivedExactly() throws {
        try db.remapPages(documentId: "d", mapping: PageMapping.insertion(oldCount: 5, inserted: 1, at: 0), editId: "e1",
                          kind: .insertion, expectedVersion: 0, fileSize: 1)
        let identities = try db.pageIdentities(documentId: "d")       // [nouvelle, garde, 1, 2, 3, 4]
        XCTAssertEqual(identities.map(\.printedNumber), [nil, nil, 1, 2, 3, 4])
        try db.writer.write { try $0.execute(sql: "DELETE FROM pageComment WHERE documentId = 'd' AND pageIndex = 0") }
        try remove([0, 3], oldCount: 6, id: "e2", version: 1)       // page insérée sans annotation + page « 2 »
        let archived = try db.archivedRows(editId: "e2").filter { $0.tableName == "pageIdentity" }
        XCTAssertEqual(archived.count, 2)
        let byId = Dictionary(uniqueKeysWithValues: archived.map { ($0.pageId, $0.columns) })
        XCTAssertEqual(byId[identities[0].pageId]?["printedNumber"], .null)
        XCTAssertEqual(byId[identities[0].pageId]?["position"], .integer(0))
        XCTAssertEqual(byId[identities[3].pageId]?["printedNumber"], .integer(2))
        XCTAssertEqual(byId[identities[3].pageId]?["position"], .integer(3))
    }

    /// Six tables archivées à l'identique, blobs et NULL compris.
    func testArchiveCoversAllSixTablesWithBlobsAndNulls() throws {
        let ocr = Data([0, 255, 7])
        try db.writer.write { db in
            try OCRResultRecord(documentId: "d", pageIndex: 1, engine: "retouche", json: ocr, durationMs: 3).insert(db)
            try Bookmark(documentId: "d", pageIndex: 1, title: "Repère").insert(db)
            try PageTransform(documentId: "d", pageIndex: 1, rotation: 90, split: true,
                              autoCrop: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6)).insert(db)
        }
        try db.save(Highlight(documentId: "d", pageIndex: 1, rects: [], color: .yellow, text: "a"))
        try remove([1], oldCount: 5, id: "e1", version: 0)
        let rows = try db.archivedRows(editId: "e1")
        XCTAssertEqual(Set(rows.map(\.tableName)), Set(AppDatabase.pageTables + ["pageIdentity"]))
        XCTAssertEqual(rows.first { $0.tableName == "ocrResult" }?.columns["json"], .blob(ocr))
        XCTAssertEqual(rows.first { $0.tableName == "pageTransform" }?.columns["rotation"], .integer(90))
        XCTAssertEqual(rows.first { $0.tableName == "pageComment" }?.columns["drawing"], .null)
        XCTAssertEqual(rows.first { $0.tableName == "inkDrawing" }?.columns["data"], .blob(Data([1])))
    }

    /// Panne SQLite pendant l'archivage : tout est annulé (aucune archive, aucune ligne effacée, version inchangée).
    func testFailureWhileArchivingRollsBackEverything() throws {
        try db.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_archive BEFORE INSERT ON pageEditRow WHEN NEW.tableName = 'pageComment' BEGIN SELECT RAISE(ABORT, 'disque simulé'); END")
        }
        XCTAssertThrowsError(try remove([1], oldCount: 5, id: "e1", version: 0))
        XCTAssertEqual(try notes().count, 5)
        XCTAssertNil(try db.pageEdit(id: "e1"))
        XCTAssertTrue(try db.archivedRows(editId: "e1").isEmpty)
        XCTAssertTrue(try db.pageIdentities(documentId: "d").isEmpty)
        XCTAssertEqual(try db.layoutVersion(documentId: "d"), 0)
        try db.writer.write { try $0.execute(sql: "DROP TRIGGER fail_archive") }
        try remove([1], oldCount: 5, id: "e1", version: 0)
        XCTAssertEqual(try notes().count, 4)
    }

    /// Migration d'une base v4 peuplée (fichier sur disque) : données intactes, version 0, puis fermeture et réouverture.
    func testMigrationFromAPopulatedVersion4Database() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kyokasho-v4-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("kyokasho.sqlite")
        do {
            let queue = try DatabaseQueue(path: file.path)
            try AppDatabase.migrator.migrate(queue, upTo: "v4-note-canvas-anchor")
            try queue.write { db in
                try db.execute(sql: "INSERT INTO document (id, title, originalFileName, pageCount, fileSize, importedAt, lastPageIndex, firstPageIndex) VALUES ('v4', 'Ancien', 'a.pdf', 3, 10, '2026-10-01 10:00:00.000', 2, 1)")
                try db.execute(sql: "INSERT INTO pageComment (id, documentId, pageIndex, body, createdAt, updatedAt, drawing) VALUES ('n', 'v4', 2, 'note 図', '2026-10-01 10:00:00.000', '2026-10-01 10:00:00.000', x'0102')")
                try db.execute(sql: "INSERT INTO ocrResult (documentId, pageIndex, engine, json, durationMs, createdAt) VALUES ('v4', 1, 'e', x'00ff', 1, '2026-10-01 10:00:00.000')")
            }
            try queue.close()
        }
        var base: AppDatabase? = try AppDatabase.open(at: file)
        let doc = try XCTUnwrap(base?.document(id: "v4"))
        XCTAssertEqual([doc.pageCount, doc.lastPageIndex, doc.firstPageIndex], [3, 2, 1])
        XCTAssertEqual(try base?.layoutVersion(documentId: "v4"), 0)
        XCTAssertEqual(try base?.comments(documentId: "v4").first?.drawing, Data([1, 2]))
        XCTAssertEqual(try base?.ocrResult(documentId: "v4", pageIndex: 1, engine: "e")?.json, Data([0, 255]))
        XCTAssertTrue(try XCTUnwrap(base?.pageIdentities(documentId: "v4")).isEmpty)
        try base?.remapPages(documentId: "v4", mapping: PageMapping.removal(oldCount: 3, removing: [0]), editId: "m",
                             kind: .removal, expectedVersion: 0, fileSize: 9)
        try base?.writer.close()
        base = nil
        let reopened = try AppDatabase.open(at: file)
        XCTAssertEqual(try reopened.comments(documentId: "v4").map(\.pageIndex), [1])
        XCTAssertEqual(try reopened.pageIdentities(documentId: "v4").map(\.printedNumber), [1, 2])
        XCTAssertEqual(try reopened.pageEdit(id: "m")?.versionAfter, 1)
        try reopened.writer.close()
    }
}

/// R5 : numéros affichés après une suppression au milieu, et repli si la valeur est périmée.
final class PrintedPageNumbersTests: XCTestCase {
    override func tearDown() { PrintedPageNumbers.set([:]) }

    func testLabelsKeepPrintedNumbersAfterAnEdit() throws {
        var doc = LibraryDocument(id: "n", title: "T", originalFileName: "t.pdf", pageCount: 4, fileSize: 1)
        doc.firstPageIndex = 1
        XCTAssertEqual((0..<4).map(doc.pageLabel), ["i", "1", "2", "3"])
        PrintedPageNumbers.set(["n": [nil, 1, 3, 4]])     // ancienne page « 2 » retirée
        XCTAssertEqual((0..<4).map(doc.pageLabel), ["i", "1", "3", "4"])
        XCTAssertEqual(doc.sourceIndex(forPrintedPage: 3), 2)
        XCTAssertEqual(doc.sourceIndex(forPrintedPage: 2), 2, "numéro retiré : la page qui suit")
        XCTAssertEqual(doc.sourceIndex(forPrintedPage: 99), 3)
        doc.pageCount = 5                                  // valeur périmée : numérotation habituelle
        XCTAssertEqual(doc.pageLabel(2), "2")
    }
}
