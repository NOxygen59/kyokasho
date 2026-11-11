// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
@testable import ReaderCore

/// PLAN-T5-001, étape E1 : dossiers de l'accueil (base synthétique jetable).
final class LibraryFoldersTests: XCTestCase {
    private func temporaryDatabase() throws -> (AppDatabase, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kyokasho-folders-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("kyokasho.sqlite")
        return (try AppDatabase.open(at: path), path)
    }

    private func document(_ id: String) -> LibraryDocument {
        LibraryDocument(id: id, title: "Titre \(id)", originalFileName: "\(id).pdf", pageCount: 5, fileSize: 1,
                        lastPageIndex: 3, category: .textbook)
    }

    func testOlderDatabaseMigratesWithDocumentsOutsideFolders() throws {
        let (database, path) = try temporaryDatabase()
        try database.save(document("ancien"))
        // Revenir au schéma d'avant v6 : table, index, colonne et migration retirés.
        try database.writer.write { db in
            try db.execute(sql: "DROP INDEX document_folder")
            try db.execute(sql: "ALTER TABLE document DROP COLUMN folderId")
            try db.execute(sql: "DROP TABLE folder")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v6-folders'")
        }
        try database.writer.close()
        let reopened = try AppDatabase.open(at: path)
        let migrated = try XCTUnwrap(reopened.document(id: "ancien"))
        XCTAssertEqual(migrated.lastPageIndex, 3)
        XCTAssertEqual(migrated.category, .textbook)
        XCTAssertEqual(try reopened.libraryFolders(), LibraryFolders())
        try reopened.writer.close()
    }

    func testCreateMoveRenameDeleteKeepsDocuments() throws {
        let database = try AppDatabase.inMemory()
        for id in ["a", "b", "c"] { try database.save(document(id)) }
        let folder = try database.createFolder(name: "  Japonais  ", space: "study")
        XCTAssertEqual(folder.name, "Japonais")
        try database.moveDocuments(["a", "b"], toFolder: folder.id, space: "study")
        XCTAssertEqual(try database.libraryFolders().membership, ["a": folder.id, "b": folder.id])

        try database.renameFolder(id: folder.id, to: "Cours")
        XCTAssertEqual(try database.libraryFolders().folders.map(\.name), ["Cours"])

        // DEC-T5-05 : supprimer le dossier rend ses documents, intacts.
        try database.deleteFolder(id: folder.id)
        let after = try database.libraryFolders()
        XCTAssertTrue(after.folders.isEmpty)
        XCTAssertTrue(after.membership.isEmpty)
        XCTAssertEqual(try database.allDocuments().count, 3)
        XCTAssertEqual(try database.document(id: "a")?.lastPageIndex, 3)
    }

    func testMoveIsAllOrNothingAndChecksSpace() throws {
        let database = try AppDatabase.inMemory()
        try database.save(document("a"))
        let manga = try database.createFolder(name: "Shōnen", space: "manga")
        XCTAssertThrowsError(try database.moveDocuments(["a"], toFolder: manga.id, space: "study")) {
            XCTAssertEqual($0 as? FolderError, .wrongSpace)
        }
        XCTAssertThrowsError(try database.moveDocuments(["a"], toFolder: "inconnu", space: "study")) {
            XCTAssertEqual($0 as? FolderError, .notFound)
        }
        XCTAssertTrue(try database.libraryFolders().membership.isEmpty)
        XCTAssertThrowsError(try database.createFolder(name: "   ", space: "study")) {
            XCTAssertEqual($0 as? FolderError, .emptyName)
        }
        // Sortir d'un dossier.
        let study = try database.createFolder(name: "Étude", space: "study")
        try database.moveDocuments(["a"], toFolder: study.id, space: "study")
        try database.moveDocuments(["a"], toFolder: nil, space: "study")
        XCTAssertTrue(try database.libraryFolders().membership.isEmpty)
    }

    func testSavingADocumentNeverClearsItsFolder() throws {
        // Invariant : renommage, réglages, remplacement Drive enregistrent `LibraryDocument`, qui ne porte pas le dossier.
        let database = try AppDatabase.inMemory()
        try database.save(document("a"))
        let folder = try database.createFolder(name: "F", space: "study")
        try database.moveDocuments(["a"], toFolder: folder.id, space: "study")
        var doc = try XCTUnwrap(database.document(id: "a"))
        doc.title = "Renommé"
        doc.lastPageIndex = 4
        try database.save(doc)
        XCTAssertEqual(try database.libraryFolders().membership["a"], folder.id)
    }

    func testFoldersAreAlphabeticalAndPerSpace() throws {
        let database = try AppDatabase.inMemory()
        _ = try database.createFolder(name: "vocabulaire", space: "study")
        _ = try database.createFolder(name: "Grammaire", space: "study")
        _ = try database.createFolder(name: "Aventure", space: "manga")
        let all = try database.libraryFolders()
        XCTAssertEqual(all.folders(in: "study").map(\.name), ["Grammaire", "vocabulaire"])
        XCTAssertEqual(all.folders(in: "manga").map(\.name), ["Aventure"])
    }

    func testPackageDoesNotCarryFolderAndReplacementKeepsIt() throws {
        let source = try AppDatabase.inMemory()
        try source.save(document("a"))
        let folder = try source.createFolder(name: "F", space: "study")
        try source.moveDocuments(["a"], toFolder: folder.id, space: "study")
        var rows = try source.packageRows(documentId: "a")
        XCTAssertNil(rows["document"]?.first?["folderId"], "DEC-T5-06 : le dossier reste sur l'appareil")

        // Autre appareil : installation sans erreur de clé étrangère, document hors dossier.
        let target = try AppDatabase.inMemory()
        try target.installPackage(documentId: "a", rows: rows, replacing: false)
        XCTAssertNil(try target.libraryFolders().membership["a"])

        // Paquet d'une version qui aurait exporté un dossier inconnu : ignoré, pas de refus.
        rows["document"]?[0]["folderId"] = .text("dossier-d-ailleurs")
        let other = try AppDatabase.inMemory()
        XCTAssertNoThrow(try other.installPackage(documentId: "a", rows: rows, replacing: false))

        // Remplacement sur l'appareil d'origine : le document garde son dossier.
        try source.installPackage(documentId: "a", rows: rows, replacing: true)
        XCTAssertEqual(try source.libraryFolders().membership["a"], folder.id)
    }

    func testPublisherSeesFolderChanges() throws {
        let database = try AppDatabase.inMemory()
        var seen: [LibraryFolders] = []
        let token = database.foldersPublisher().sink(receiveCompletion: { _ in }, receiveValue: { seen.append($0) })
        defer { token.cancel() }
        _ = try database.createFolder(name: "Nouveau", space: "study")
        let deadline = Date().addingTimeInterval(2)
        while seen.last?.folders.count != 1, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(seen.last?.folders.map(\.name), ["Nouveau"])
    }

    /// Revue GLM R2 (G1) : l'espace réel du document est relu en base, même si l'appelant annonce le mauvais.
    func testMangaDocumentIsRefusedInAStudyFolderWhateverTheCallerSays() throws {
        let (database, _) = try temporaryDatabase()
        try database.save(document("a"))
        try database.updateMangaSpace(documentId: "a", inManga: true)
        let study = try database.createFolder(name: "Étude", space: "study")
        XCTAssertThrowsError(try database.moveDocuments(["a"], toFolder: study.id, space: "study")) {
            XCTAssertEqual($0 as? FolderError, .wrongSpace)
        }
        XCTAssertNil(try database.libraryFolders().membership["a"], "tout ou rien : rien n'est rangé")
    }

    /// PLAN-T5-001, E2 : un document qui change d'espace sort de son dossier (jamais rangé dans l'autre espace).
    func testChangingSpaceTakesTheDocumentOutOfItsFolder() throws {
        let (database, _) = try temporaryDatabase()
        try database.save(document("a"))
        try database.save(document("b"))
        let study = try database.createFolder(name: "Étude", space: "study")
        try database.moveDocuments(["a", "b"], toFolder: study.id, space: "study")
        try database.updateMangaSpace(documentId: "a", inManga: true)
        try database.updateMangaSpace(documentId: "b", inManga: false)
        let membership = try database.libraryFolders().membership
        XCTAssertNil(membership["a"], "passé en Manga : hors du dossier Livres & Manuels")
        XCTAssertEqual(membership["b"], study.id, "même espace : reste dans son dossier")
        XCTAssertEqual(try database.allDocuments().count, 2, "aucun document perdu")
    }
}
