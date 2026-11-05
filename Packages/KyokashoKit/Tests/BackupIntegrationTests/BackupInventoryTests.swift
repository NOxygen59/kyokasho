// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
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

    /// Fichiers sources qui demandent un dossier du conteneur : rôle, puis **chaque composant de chemin littéral**
    /// (`appendingPathComponent("…")`) qu'ils emploient. Un nouveau fichier, ou un nouveau dossier/fichier dans un
    /// fichier déjà connu, fait échouer I2 (revue de Codex sur #84). Mettre alors à jour cette table **et**
    /// `docs/DONNEES-ET-SAUVEGARDES.md`. Seuls les fichiers qui appellent directement les API de répertoire recherchées
    /// sont examinés. Hors de portée : un fichier qui dérive un chemin d'une racine existante sans ces API (par exemple
    /// `ModelStore.shared.root.appendingPathComponent("…")`), les chemins entièrement calculés sans littéral, et les
    /// préférences (`UserDefaults`, `@AppStorage`), couvertes en bloc par `Library/Preferences`.
    static let storageInventory: [String: (role: String, components: Set<String>)] = [
        "App/AppModel.swift": ("persistant : Kyokasho/kyokasho.sqlite, Kyokasho/Documents/, Kyokasho/Bench/ ; cache : Caches/Thumbnails",
                               ["Bench", "Documents", "Kyokasho", "Thumbnails", "kyokasho.sqlite"]),
        "App/Review/ReviewModel.swift": ("persistant : Kyokasho/Review/", ["Kyokasho/Review"]),
        "Packages/KyokashoKit/Sources/ReviewKit/ReviewStore.swift": ("persistant : Review/review.sqlite, Review/Media/ ; temporaire : review-media-<UUID>",
                                                                     ["Media", "review-media-", "review.sqlite"]),
        "App/Dictionary/DictionaryModel.swift": ("persistant : Kyokasho/Dictionaries/ ; non essentiel (NOxygen59, 28/10) : Documents/Audio/",
                                                 ["Audio", "Dictionaries", "Kyokasho"]),
        "Packages/KyokashoKit/Sources/DictionaryKit/DictionaryDatabase.swift": ("persistant : Dictionaries/dictionaries.sqlite, Dictionaries/Media/ ; temporaire : dict-media-<UUID>",
                                                                               ["Media", "dict-media-", "dictionaries.sqlite"]),
        "App/Dictionary/DomainLexicon.swift": ("persistant : Kyokasho/lexique.json", ["Kyokasho/lexique.json"]),
        "App/Dictionary/DefinitionTranslation.swift": ("persistant : Application Support/definition-translations.json",
                                                       ["definition-translations.json"]),
        "App/Library/DocumentAITextStore.swift": ("persistant : Application Support/Analysis/", ["Analysis", "\\(reader)-\\(page).md"]),
        "App/Settings/AIModelViews.swift": ("persistant : Kyokasho/Chats/ (qwen-<id>.json, book-<id>.json)",
                                            ["Kyokasho/Chats/qwen\\(document.map { ", "book-\\($0.id).json"]),
        "Packages/KyokashoKit/Sources/ReaderCore/NoteDraftStore.swift": ("persistant : Kyokasho/NoteDrafts/", ["Kyokasho", "NoteDrafts"]),
        "Packages/KyokashoKit/Sources/OCRKit/ModelStore.swift": ("modèles : Kyokasho/Models/ (omissible, retéléchargeable)", ["Kyokasho/Models", "model-"]),
        "App/Dictionary/MorphologyService.swift": ("modèles : Kyokasho/Models/unidic ; temporaire : tmp/unidic-lite.tar.gz",
                                                   ["unidic", "unidic-lite.tar.gz"]),
        "App/Library/PageShift.swift": ("transaction : Kyokasho/page-shift.json (sauvegarde refusée) ; copies 30 jours (#49) : Kyokasho/PageShift/<opération>/ avec manifest.json ; temporaire : tmp/PageEdit-<UUID>/",
                                        [".page-shift-\\(p.transaction!).pdf", "Kyokasho", "PageShift/", "drafts.json", "files", "install-files",
                                         "merged.pdf", "original-drafts.json", "original-files", "original-report.json", "original.pdf",
                                         "page-shift.json", "report.json", "PageEdit-\\(UUID().uuidString)", "PageShift",
                                         "PageShift/\\($0.archiveId)", "PageShift/\\(archiveId)/original.pdf",
                                         "\\(stem[..<dash])-\\(position).md", "manifest.json"]),
        "App/Library/DocumentPackageService.swift": ("export complet : Documents/Paquets de sécurité/<date>/ (avant remplacement) ; temporaire : tmp/PackageImport-<UUID>/ ; installation : .package-<UUID>(.pdf) à côté de la cible, échangé ensuite",
                                                     [".package-\\(UUID().uuidString)", ".package-\\(UUID().uuidString).pdf",
                                                      "PackageImport-\\(UUID().uuidString)", "Paquets de sécurité"]),
        "Packages/KyokashoKit/Sources/ReaderCore/DocumentPackage.swift": ("export complet : temporaire tmp/PackageWrite-<UUID>/data",
                                                                          ["PackageWrite-\\(UUID().uuidString)", "data"]),
        "App/Library/LibraryBackupService.swift": ("sauvegarde complète (#51) : lit tout Kyokasho/ (sauf Models, page-shift.json), Analysis/, definition-translations.json, réglages ; temporaire tmp/BackupApp-<UUID>/ ; écrit dans le dossier choisi (signet)",
                                                   ["BackupApp-\\(UUID().uuidString)", "Kyokasho", "Models", "definition-translations.json", "preferences.plist"]),
        "Packages/KyokashoKit/Sources/ReaderCore/LibraryBackup.swift": ("sauvegarde complète (#51) : temporaire tmp/BackupWrite-<UUID>/ (copies des bases, relecture check/)",
                                                                        ["BackupWrite-\\(UUID().uuidString)", "check", "db-\\(index).sqlite"]),
        "App/Settings/Diagnostics.swift": ("diagnostic : Documents/Diagnostics/journal.txt", ["Diagnostics", "journal.txt"]),
        "App/Settings/StorageUsage.swift": ("lecture seule (calcul de l'espace)", ["Analysis", "Dictionaries", "Documents", "Kyokasho", "unidic"]),
        "App/Settings/GitHubUpdate.swift": ("cache : Caches/Update", ["Update"]),
        "App/Reader/ScanSharpening.swift": ("cache : Caches/Sharpened", ["Sharpened"]),
        "App/Reader/ReaderController.swift": ("cache : Caches/Equalized", ["Equalized", "\\(documentId)-\\(stamp)"]),
        "App/Drive/GoogleDrive.swift": ("temporaire : tmp/<UUID>/", []),
        "App/Library/AddPagesView.swift": ("temporaire : tmp/AddPages-<UUID>/", ["AddPages-\\(UUID().uuidString)", "merged.pdf"]),
        "App/Library/PDFMergeView.swift": ("temporaire : tmp/Merge-<UUID>/", ["Merge-\\(UUID().uuidString)"]),
        "App/Library/ImagesToPDFView.swift": ("temporaire : tmp/Images-<UUID>/", ["Images-\\(UUID().uuidString)"]),
        "App/Dictionary/DictionaryCatalogService.swift": ("temporaire : tmp/DictionaryDownload-<UUID>/ (dictionnaire téléchargé, effacé après import)",
                                                          ["DictionaryDownload-\\(UUID().uuidString)", "\\(entry.id).zip"]),
        "App/Library/DocumentExport.swift": ("temporaire : tmp/Export/", ["Export"]),
        "Packages/KyokashoKit/Sources/ReaderCore/AIReadingExport.swift": ("temporaire : tmp/partage-lectures-<UUID>/<titre> - lectures <modèle>.txt (partage)", ["\\(base) - lectures \\(reader).txt", "partage-lectures-"]),
        "Packages/KyokashoKit/Sources/ReaderCore/MarkdownShareFile.swift": ("temporaire : tmp/partage-markdown-<UUID>/<titre>.md (partage)", ["partage-markdown-"]),
        "App/Review/ReviewSettingsView.swift": ("temporaire : tmp/Export/", ["Export", "Kyokasho.\\(apkg ? "]),
        "Packages/KyokashoKit/Sources/ReviewKit/Exporters.swift": ("temporaire : tmp/apkg-<UUID>/", ["apkg-", "collection.anki2"]),
    ]

    /// Composants de chemin littéraux d'un fichier source, tels qu'écrits (interpolations comprises).
    static func pathComponents(in text: String) throws -> Set<String> {
        let literal = try NSRegularExpression(pattern: #"appendingPathComponent\("((?:[^"\\]|\\.)*)""#)
        let range = NSRange(text.startIndex..., in: text)
        return Set(literal.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        })
    }

    /// I2 — garde-fou : un fichier qui ouvre un dossier du conteneur sans figurer dans l'inventaire, ou un composant
    /// de chemin nouveau dans un fichier inventorié, fait échouer le test.
    func testI2EveryStorageLocationInCodeIsInventoried() throws {
        let pattern = try NSRegularExpression(pattern:
            #"\.(applicationSupportDirectory|documentDirectory|cachesDirectory|libraryDirectory)\b|\btemporaryDirectory\b"#)
        var found: [String: String] = [:]
        for folder in ["App", "Packages/KyokashoKit/Sources"] {
            let root = repository.appendingPathComponent(folder)
            let walk = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let url as URL in walk where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                if pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                    found[String(url.standardizedFileURL.path.dropFirst(repository.path.count + 1))] = text
                }
            }
        }
        let unknown = Set(found.keys).subtracting(Self.storageInventory.keys).sorted()
        XCTAssertEqual(unknown, [], "Nouvel emplacement de stockage : l'ajouter à l'inventaire DATA-02 et à DONNEES-ET-SAUVEGARDES.md")
        let stale = Set(Self.storageInventory.keys).subtracting(found.keys).sorted()
        XCTAssertEqual(stale, [], "Inventaire périmé : ces sources n'ouvrent plus de dossier du conteneur")
        for (file, text) in found {
            guard let expected = Self.storageInventory[file]?.components else { continue }
            let actual = try Self.pathComponents(in: text)
            XCTAssertEqual(actual.subtracting(expected).sorted(), [],
                           "\(file) : nouveau chemin dans un fichier inventorié ; mettre à jour l'inventaire DATA-02")
            XCTAssertEqual(expected.subtracting(actual).sorted(), [], "\(file) : chemin de l'inventaire disparu du code")
        }
    }

    /// Dictionnaire Yomitan v3 minimal (index + une entrée), compressé par `ditto` (outil système, sans dépendance).
    func syntheticDictionary(in root: URL) throws -> URL {
        let folder = root.appendingPathComponent("dictionnaire-synthetique")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"title":"Dictionnaire synthétique DATA-02","revision":"1","format":3,"sequenced":true}"#.utf8)
            .write(to: folder.appendingPathComponent("index.json"))
        try Data(#"[["図","ず","n","",10,["figure"],1,""]]"#.utf8).write(to: folder.appendingPathComponent("term_bank_1.json"))
        let zip = root.appendingPathComponent("dictionnaire-synthetique.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", folder.path, zip.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return zip
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
        // Vraie base `DictionaryDatabase` (`Dictionaries/dictionaries.sqlite`), remplie par l'importeur réel à partir
        // d'un petit dictionnaire Yomitan synthétique (revue de Codex : le SQLite générique ne prouvait pas la réouverture).
        let dictionaries = try DictionaryDatabase.open(directory: support.appendingPathComponent("Dictionaries"))
        try DictionaryImporter(database: dictionaries).importDictionary(at: try syntheticDictionary(in: root))
        let dictionaryIds = Set(try dictionaries.dictionaries().compactMap(\.id))
        let termsBefore = try dictionaries.terms(matching: ["図"], dictionaryIds: dictionaryIds).count
        XCTAssertEqual(termsBefore, 1)
        try dictionaries.writer.close()
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
        let reopened = try DictionaryDatabase.open(directory: restoredSupport.appendingPathComponent("Dictionaries"))
        XCTAssertEqual(try reopened.dictionaries().map(\.title), ["Dictionnaire synthétique DATA-02"])
        XCTAssertEqual(try reopened.terms(matching: ["図"], dictionaryIds: Set(try reopened.dictionaries().compactMap(\.id))).count, 1)
        try reopened.writer.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: restoredSupport.appendingPathComponent("page-shift.json").path))
    }

    /// C1 — base `AppDatabase` au schéma `v3-page-one` (avant `v4-note-canvas-anchor`), sauvegardée et restaurée :
    /// l'app actuelle l'ouvre, applique `v4` et `v5` et relit notes, repères et OCR, puis écrit une note ancrée.
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
        // Revenir au schéma v3 : colonnes de v4 et v5 retirées et migrations oubliées, comme une base jamais migrée.
        try sqlite(path, """
            ALTER TABLE document DROP COLUMN category;
            DELETE FROM grdb_migrations WHERE identifier = 'v5-document-category';
            DROP TABLE pageEditRow; DROP TABLE pageEdit; DROP TABLE pageIdentity;
            ALTER TABLE document DROP COLUMN layoutVersion;
            DELETE FROM grdb_migrations WHERE identifier = 'v5-page-edits';
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
        XCTAssertNil(try app.document(id: doc.id)?.category)
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
        // v5 (RET-039, #54) appliquée aussi : document ancien non classé.
        XCTAssertTrue(try sqliteRows(restored, "SELECT identifier FROM grdb_migrations").contains("v5-document-category"))
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
