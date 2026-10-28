// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore
import ReviewKit
import SQLite3
import XCTest

// DATA-02 (Issue #83) : inventaire complet (I1), garde-fou d'inventaire (I2) et base d'une version antérieure (C1).
// Extension de `BackupRoundTripTests` pour réutiliser `runTool`. Conteneurs synthétiques temporaires uniquement.
extension BackupRoundTripTests {
    /// Racine du dépôt (le test lit les sources de l'app pour I2, comme `runTool` lit l'outil Python).
    var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../..").standardizedFileURL
    }

    /// Fichiers sources qui demandent un dossier du conteneur, et ce qu'ils y écrivent (chemins relatifs au conteneur).
    /// Toute nouvelle source qui appelle ces API doit être ajoutée ici, puis à `docs/DONNEES-ET-SAUVEGARDES.md`.
    static let storageInventory: [String: String] = [
        "App/AppModel.swift": "persistant : Kyokasho/kyokasho.sqlite, Kyokasho/Documents/ ; cache : Caches/Thumbnails",
        "App/Review/ReviewModel.swift": "persistant : Kyokasho/Review/ (review.sqlite, Media/)",
        "Packages/KyokashoKit/Sources/ReviewKit/ReviewStore.swift": "persistant : Review/Media/ ; base en mémoire de secours",
        "App/Dictionary/DictionaryModel.swift": "persistant : Kyokasho/Dictionaries/ ; non essentiel (NOxygen59, 28/10) : Documents/Audio/",
        "Packages/KyokashoKit/Sources/DictionaryKit/DictionaryDatabase.swift": "temporaire : médias de la base en mémoire",
        "App/Dictionary/DomainLexicon.swift": "persistant : Kyokasho/lexique.json",
        "App/Dictionary/DefinitionTranslation.swift": "persistant : Application Support/definition-translations.json",
        "App/Library/DocumentAITextStore.swift": "persistant : Application Support/Analysis/",
        "App/Settings/AIModelViews.swift": "persistant : Kyokasho/Chats/",
        "Packages/KyokashoKit/Sources/ReaderCore/NoteDraftStore.swift": "persistant : Kyokasho/NoteDrafts/",
        "Packages/KyokashoKit/Sources/OCRKit/ModelStore.swift": "modèles : Kyokasho/Models/ (omissible, retéléchargeable)",
        "App/Library/PageShift.swift": "transaction : Kyokasho/page-shift.json (sauvegarde refusée) ; secours : Kyokasho/PageShift/<UUID>/",
        "App/Settings/Diagnostics.swift": "diagnostic : Documents/Diagnostics/journal.txt",
        "App/Settings/StorageUsage.swift": "lecture seule (calcul de l'espace)",
        "App/Settings/GitHubUpdate.swift": "cache : Caches/Update",
        "App/Reader/ScanSharpening.swift": "cache : Caches/Sharpened",
        "App/Reader/ReaderController.swift": "cache : Caches/Equalized",
        "App/Dictionary/MorphologyService.swift": "temporaire : tmp/unidic-lite.tar.gz",
        "App/Drive/GoogleDrive.swift": "temporaire : tmp/<UUID>/",
        "App/Library/AddPagesView.swift": "temporaire : tmp/AddPages-<UUID>/",
        "App/Library/PDFMergeView.swift": "temporaire : tmp/Merge-<UUID>/",
        "App/Library/DocumentExport.swift": "temporaire : tmp/Export/",
        "App/Reader/ReaderSheets.swift": "temporaire : tmp/<titre>.md (partage)",
        "App/Review/ReviewSettingsView.swift": "temporaire : tmp/Export/",
        "Packages/KyokashoKit/Sources/ReviewKit/Exporters.swift": "temporaire : tmp/apkg-<UUID>/",
    ]

    /// I2 — garde-fou : une source qui ouvre un dossier du conteneur sans figurer dans l'inventaire fait échouer le test.
    func testI2EveryStorageLocationInCodeIsInventoried() throws {
        let pattern = try NSRegularExpression(pattern:
            #"\.(applicationSupportDirectory|documentDirectory|cachesDirectory|libraryDirectory)\b|\btemporaryDirectory\b"#)
        var found = Set<String>()
        for folder in ["App", "Packages/KyokashoKit/Sources"] {
            let root = repository.appendingPathComponent(folder)
            let walk = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let url as URL in walk where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                if pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                    found.insert(String(url.standardizedFileURL.path.dropFirst(repository.path.count + 1)))
                }
            }
        }
        let unknown = found.subtracting(Self.storageInventory.keys).sorted()
        XCTAssertEqual(unknown, [], "Nouvel emplacement de stockage : l'ajouter à l'inventaire DATA-02 et à DONNEES-ET-SAUVEGARDES.md")
        let stale = Set(Self.storageInventory.keys).subtracting(found).sorted()
        XCTAssertEqual(stale, [], "Inventaire périmé : ces sources n'ouvrent plus de dossier du conteneur")
    }

    /// I1 — données apparues depuis la PR #3 : brouillons, traductions de définitions, base de dictionnaire, journal de
    /// diagnostic, copie de secours PageShift sans journal. Retour octet pour octet et relecture par `NoteDraftStore`.
    func testI1RecentDataRoundTripsAndDraftsAreReadable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kyokasho-inventory-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appendingPathComponent("source")
        let support = container.appendingPathComponent("Library/Application Support/Kyokasho")
        let database = try AppDatabase.open(at: support.appendingPathComponent("kyokasho.sqlite"))
        let review = try ReviewStore.open(directory: support.appendingPathComponent("Review"))
        let drafts = NoteDraftStore(folder: support.appendingPathComponent("NoteDrafts"))
        try drafts.setDraft("brouillon 図", documentId: "synth", page: 3)
        let dictionary = support.appendingPathComponent("Dictionaries/dictionary.sqlite")
        try FileManager.default.createDirectory(at: dictionary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sqlite(dictionary, "PRAGMA journal_mode=WAL; CREATE TABLE term(expression TEXT, reading TEXT);"
                   + "INSERT INTO term VALUES ('図', 'ず');")
        let files = [
            "Library/Application Support/definition-translations.json": #"{"図|ず":{"text":"figure","status":"liked"}}"#,
            "Documents/Diagnostics/journal.txt": "journal synthétique",
            "Library/Application Support/Kyokasho/PageShift/7D3B6A2E-0000-4000-8000-000000000001/original.pdf": "PDF secours",
        ]
        for (name, value) in files {
            let url = container.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(value.utf8).write(to: url)
        }
        try database.writer.close()
        try review.writer.close()
        let backup = root.appendingPathComponent("backup")
        try runTool(["backup", container.path, backup.path, "--source-stopped"])
        let target = root.appendingPathComponent("restored")
        try runTool(["restore", backup.appendingPathComponent("backup").path, target.path])
        let restored = target.appendingPathComponent("container")
        for (name, value) in files {
            XCTAssertEqual(try String(contentsOf: restored.appendingPathComponent(name)), value, name)
        }
        let restoredSupport = restored.appendingPathComponent("Library/Application Support/Kyokasho")
        XCTAssertEqual(NoteDraftStore(folder: restoredSupport.appendingPathComponent("NoteDrafts")).drafts(documentId: "synth"),
                       [3: "brouillon 図"])
        XCTAssertEqual(try sqliteRows(restoredSupport.appendingPathComponent("Dictionaries/dictionary.sqlite"),
                                      "SELECT expression || '|' || reading FROM term"), ["図|ず"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: restoredSupport.appendingPathComponent("page-shift.json").path))
    }

    /// C1 — base `AppDatabase` au schéma `v3-page-one` (avant `v4-note-canvas-anchor`), sauvegardée et restaurée :
    /// l'app actuelle l'ouvre, applique `v4` et relit notes, repères et OCR, puis écrit une note ancrée.
    func testC1OlderAppDatabaseSchemaRestoresAndMigrates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kyokasho-old-schema-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appendingPathComponent("source")
        let support = container.appendingPathComponent("Library/Application Support/Kyokasho")
        let path = support.appendingPathComponent("kyokasho.sqlite")
        let database = try AppDatabase.open(at: path)
        let doc = LibraryDocument(id: "ancien", title: "Ancien", originalFileName: "a.pdf", pageCount: 3, fileSize: 1,
                                  importedAt: Date(timeIntervalSince1970: 1000))
        try database.save(doc)
        try database.save(PageComment(documentId: doc.id, pageIndex: 2, body: "Note d'avant v4"))
        try database.save(Bookmark(documentId: doc.id, pageIndex: 1, title: "Repère ancien"))
        let ocr = Data(#"{"edited":true}"#.utf8)
        try database.save(OCRResultRecord(documentId: doc.id, pageIndex: 0, engine: "synthetic", json: ocr, durationMs: 1))
        try database.writer.close()
        // Revenir au schéma v3 : colonnes de v4 retirées et migration oubliée, comme une base jamais migrée.
        try sqlite(path, """
            ALTER TABLE pageComment DROP COLUMN drawing; ALTER TABLE pageComment DROP COLUMN anchorX;
            ALTER TABLE pageComment DROP COLUMN anchorY; ALTER TABLE pageComment DROP COLUMN anchorWidth;
            ALTER TABLE pageComment DROP COLUMN anchorHeight; ALTER TABLE pageComment DROP COLUMN anchorText;
            DELETE FROM grdb_migrations WHERE identifier = 'v4-note-canvas-anchor';
            """)
        XCTAssertEqual(try sqliteRows(path, "SELECT identifier FROM grdb_migrations ORDER BY identifier"),
                       ["v1", "v2-ocr", "v3-page-one"])
        try ReviewStore.open(directory: support.appendingPathComponent("Review")).writer.close()
        let backup = root.appendingPathComponent("backup")
        try runTool(["backup", container.path, backup.path, "--source-stopped"])
        let target = root.appendingPathComponent("restored")
        try runTool(["restore", backup.appendingPathComponent("backup").path, target.path])
        let restored = target.appendingPathComponent("container/Library/Application Support/Kyokasho/kyokasho.sqlite")
        let app = try AppDatabase.open(at: restored)
        XCTAssertEqual(try app.document(id: doc.id)?.title, "Ancien")
        XCTAssertEqual(try app.comments(documentId: doc.id).map(\.body), ["Note d'avant v4"])
        XCTAssertNil(try app.comments(documentId: doc.id).first?.anchorRect)
        XCTAssertEqual(try app.bookmarks(documentId: doc.id).first?.pageIndex, 1)
        XCTAssertEqual(try app.ocrResult(documentId: doc.id, pageIndex: 0, engine: "synthetic")?.json, ocr)
        var anchored = PageComment(documentId: doc.id, pageIndex: 0, body: "Après migration", drawing: Data([9]))
        anchored.anchorRect = .init(x: 1, y: 2, width: 3, height: 4)
        try app.save(anchored)
        XCTAssertEqual(try app.comments(documentId: doc.id).count, 2)
        try app.writer.close()
        XCTAssertTrue(try sqliteRows(restored, "SELECT identifier FROM grdb_migrations").contains("v4-note-canvas-anchor"))
    }

    // MARK: SQLite direct (sans dépendance supplémentaire à GRDB dans cette cible)

    func sqlite(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw NSError(domain: "SQLite", code: 1) }
        defer { sqlite3_close(handle) }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "?"
            sqlite3_free(error)
            throw NSError(domain: "SQLite", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func sqliteRows(_ url: URL, _ sql: String) throws -> [String] {
        var handle: OpaquePointer?, statement: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw NSError(domain: "SQLite", code: 3) }
        defer { sqlite3_close(handle) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw NSError(domain: "SQLite", code: 4) }
        defer { sqlite3_finalize(statement) }
        var rows: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(String(cString: sqlite3_column_text(statement, 0))) }
        return rows
    }
}
