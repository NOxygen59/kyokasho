// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import Foundation
import GRDB

/// Base SQLite de l'app (GRDB). Fichier : mode WAL (`DatabasePool`) → lectures concurrentes,
/// écritures sans bloquer l'interface. Tests : base en mémoire.
public final class AppDatabase: @unchecked Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Base sur disque.
    public static func open(at url: URL) throws -> AppDatabase {
        var config = Configuration()
        config.prepareDatabase { db in
            // Cache de pages plus généreux et E/S mappées en mémoire : lectures plus rapides.
            try db.execute(sql: "PRAGMA cache_size = -16000")   // ~16 Mo
            try db.execute(sql: "PRAGMA mmap_size = 268435456") // 256 Mo
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(DatabasePool(path: url.path, configuration: config))
    }

    /// Base en mémoire (tests, aperçus).
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "document") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("originalFileName", .text).notNull()
                t.column("pageCount", .integer).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("importedAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime)
                t.column("lastPageIndex", .integer).notNull().defaults(to: 0)
                t.column("settingsJSON", .text)
                t.column("driveFileId", .text).indexed()
                t.column("driveRevision", .text)
            }
            try db.create(table: "pageTransform") { t in
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("pageIndex", .integer).notNull()
                t.column("rotation", .integer).notNull().defaults(to: 0)
                t.column("split", .boolean).notNull().defaults(to: false)
                t.column("autoCrop", .text)
                t.primaryKey(["documentId", "pageIndex"])
            }
            try db.create(table: "highlight") { t in
                t.primaryKey("id", .text)
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("pageIndex", .integer).notNull()
                t.column("rectsJSON", .text).notNull()
                t.column("color", .text).notNull()
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "highlight_page", on: "highlight", columns: ["documentId", "pageIndex"])
            try db.create(table: "inkDrawing") { t in
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("pageIndex", .integer).notNull()
                t.column("data", .blob).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.primaryKey(["documentId", "pageIndex"])
            }
            try db.create(table: "bookmark") { t in
                t.primaryKey("id", .text)
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("pageIndex", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "bookmark_doc", on: "bookmark", columns: ["documentId", "pageIndex"])
            try db.create(table: "pageComment") { t in
                t.primaryKey("id", .text)
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("pageIndex", .integer).notNull()
                t.column("body", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "pageComment_doc", on: "pageComment", columns: ["documentId", "pageIndex"])
            try db.create(table: "aiPrompt") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("position", .integer).notNull()
            }
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            for prompt in AIPrompt.defaults { try prompt.insert(db) }
        }
        m.registerMigration("v2-ocr") { db in
            // Cache OCR : une ligne par (document, page source, moteur). Changer de moteur n'efface rien.
            try db.create(table: "ocrResult") { t in
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("pageIndex", .integer).notNull()
                t.column("engine", .text).notNull()
                t.column("json", .blob).notNull()
                t.column("durationMs", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.primaryKey(["documentId", "pageIndex", "engine"])
            }
            try db.create(table: "benchSample") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("imageFile", .text).notNull()
                t.column("referenceText", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "benchRun") { t in
                t.primaryKey("id", .text)
                t.column("sampleId", .text).notNull().references("benchSample", onDelete: .cascade)
                t.column("engine", .text).notNull()
                t.column("cer", .double).notNull()
                t.column("durationMs", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "benchRun_sample", on: "benchRun", columns: ["sampleId", "engine"])
        }
        return m
    }
}

// MARK: - Documents

extension AppDatabase {
    public func allDocuments() throws -> [LibraryDocument] {
        try writer.read { db in
            try LibraryDocument.order(sql: "COALESCE(lastOpenedAt, importedAt) DESC").fetchAll(db)
        }
    }

    public func document(id: String) throws -> LibraryDocument? {
        try writer.read { db in try LibraryDocument.fetchOne(db, key: id) }
    }

    public func save(_ document: LibraryDocument) throws {
        try writer.write { db in try document.save(db) }
    }

    public func deleteDocument(id: String) throws {
        try writer.write { db in _ = try LibraryDocument.deleteOne(db, key: id) }
    }

    /// Enregistre la position de lecture (appelé souvent : requête minimale).
    public func updateReadingPosition(documentId: String, pageIndex: Int, at date: Date = Date()) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE document SET lastPageIndex = ?, lastOpenedAt = ? WHERE id = ?",
                           arguments: [pageIndex, date, documentId])
        }
    }

    /// Une nouvelle version d'un document (ex. cours mis à jour sur Drive) remplace l'ancienne :
    /// toutes les annotations suivent grâce aux clés étrangères `ON UPDATE CASCADE`.
    public func rekeyDocument(from oldId: String, to newDocument: LibraryDocument) throws {
        try writer.write { db in
            if oldId != newDocument.id, try LibraryDocument.exists(db, key: newDocument.id) {
                // La nouvelle version existe déjà : on y rattache les annotations de l'ancienne.
                for table in ["pageTransform", "highlight", "inkDrawing", "bookmark", "pageComment"] {
                    try db.execute(sql: "UPDATE OR IGNORE \(table) SET documentId = ? WHERE documentId = ?",
                                   arguments: [newDocument.id, oldId])
                }
                _ = try LibraryDocument.deleteOne(db, key: oldId)
                try newDocument.update(db)
            } else {
                try db.execute(sql: "UPDATE document SET id = ? WHERE id = ?", arguments: [newDocument.id, oldId])
                try newDocument.update(db)
            }
        }
    }

    /// Publie la bibliothèque à chaque changement (pour l'interface).
    public func documentsPublisher() -> AnyPublisher<[LibraryDocument], Error> {
        ValueObservation
            .tracking { db in try LibraryDocument.order(sql: "COALESCE(lastOpenedAt, importedAt) DESC").fetchAll(db) }
            .publisher(in: writer, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}

// MARK: - Réglages

extension AppDatabase {
    static let readerDefaultsKey = "reader.defaults"
    static let appSettingsKey = "app.settings"

    func value<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        try writer.read { db in
            guard let json = try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key]) else {
                return nil
            }
            return try? JSONDecoder().decode(T.self, from: Data(json.utf8))
        }
    }

    func setValue<T: Encodable>(_ value: T, forKey key: String) throws {
        let json = String(decoding: try JSONEncoder.sorted.encode(value), as: UTF8.self)
        try writer.write { db in
            try db.execute(sql: "INSERT INTO setting (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                           arguments: [key, json])
        }
    }

    public func readerDefaults() throws -> ReaderSettings {
        try value(ReaderSettings.self, forKey: Self.readerDefaultsKey) ?? .default
    }

    public func setReaderDefaults(_ settings: ReaderSettings) throws {
        try setValue(settings, forKey: Self.readerDefaultsKey)
    }

    public func appSettings() throws -> AppSettings {
        try value(AppSettings.self, forKey: Self.appSettingsKey) ?? AppSettings()
    }

    public func setAppSettings(_ settings: AppSettings) throws {
        try setValue(settings, forKey: Self.appSettingsKey)
    }
}

// MARK: - Annotations

extension AppDatabase {
    public func pageTransforms(documentId: String) throws -> [Int: PageTransform] {
        try writer.read { db in
            let rows = try PageTransform.filter(Column("documentId") == documentId).fetchAll(db)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.pageIndex, $0) })
        }
    }

    public func save(_ transform: PageTransform) throws {
        try writer.write { db in try transform.save(db) }
    }

    /// Enregistre plusieurs transformations d'un coup (ex. rognages calculés en tâche de fond).
    public func save(_ transforms: [PageTransform]) throws {
        try writer.write { db in for t in transforms { try t.save(db) } }
    }

    public func highlights(documentId: String) throws -> [Highlight] {
        try writer.read { db in
            try Highlight.filter(Column("documentId") == documentId).order(Column("pageIndex"), Column("createdAt")).fetchAll(db)
        }
    }

    public func save(_ highlight: Highlight) throws {
        try writer.write { db in try highlight.save(db) }
    }

    public func deleteHighlight(id: String) throws {
        try writer.write { db in _ = try Highlight.deleteOne(db, key: id) }
    }

    public func inkDrawing(documentId: String, pageIndex: Int) throws -> InkDrawing? {
        try writer.read { db in
            try InkDrawing.fetchOne(db, key: ["documentId": documentId, "pageIndex": pageIndex])
        }
    }

    /// Pages qui ont un dessin (pour ne charger que celles-là).
    public func pagesWithInk(documentId: String) throws -> Set<Int> {
        try writer.read { db in
            Set(try Int.fetchAll(db, sql: "SELECT pageIndex FROM inkDrawing WHERE documentId = ?", arguments: [documentId]))
        }
    }

    /// Enregistre un dessin ; un dessin vide supprime la ligne.
    public func save(_ drawing: InkDrawing, isEmpty: Bool) throws {
        try writer.write { db in
            if isEmpty {
                _ = try InkDrawing.deleteOne(db, key: ["documentId": drawing.documentId, "pageIndex": drawing.pageIndex])
            } else {
                try drawing.save(db)
            }
        }
    }

    public func bookmarks(documentId: String) throws -> [Bookmark] {
        try writer.read { db in
            try Bookmark.filter(Column("documentId") == documentId).order(Column("pageIndex")).fetchAll(db)
        }
    }

    public func save(_ bookmark: Bookmark) throws {
        try writer.write { db in try bookmark.save(db) }
    }

    public func deleteBookmark(id: String) throws {
        try writer.write { db in _ = try Bookmark.deleteOne(db, key: id) }
    }

    public func comments(documentId: String) throws -> [PageComment] {
        try writer.read { db in
            try PageComment.filter(Column("documentId") == documentId).order(Column("pageIndex"), Column("createdAt")).fetchAll(db)
        }
    }

    public func save(_ comment: PageComment) throws {
        try writer.write { db in try comment.save(db) }
    }

    public func deleteComment(id: String) throws {
        try writer.write { db in _ = try PageComment.deleteOne(db, key: id) }
    }

    public func aiPrompts() throws -> [AIPrompt] {
        try writer.read { db in try AIPrompt.order(Column("position")).fetchAll(db) }
    }

    public func save(_ prompt: AIPrompt) throws {
        try writer.write { db in try prompt.save(db) }
    }

    public func deletePrompt(id: String) throws {
        try writer.write { db in _ = try AIPrompt.deleteOne(db, key: id) }
    }
}

// MARK: - OCR

extension AppDatabase {
    public func ocrResult(documentId: String, pageIndex: Int, engine: String) throws -> OCRResultRecord? {
        try writer.read { db in
            try OCRResultRecord.fetchOne(db, key: ["documentId": documentId, "pageIndex": pageIndex, "engine": engine])
        }
    }

    /// Moteurs déjà passés sur une page (pour « Comparer » et l'affichage du moteur).
    public func ocrEngines(documentId: String, pageIndex: Int) throws -> [String] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT engine FROM ocrResult WHERE documentId = ? AND pageIndex = ? ORDER BY createdAt",
                                arguments: [documentId, pageIndex])
        }
    }

    public func save(_ record: OCRResultRecord) throws {
        try writer.write { db in try record.save(db) }
    }

    /// Taille du cache OCR (octets) et nombre de pages.
    public func ocrCacheStats() throws -> (bytes: Int, pages: Int) {
        try writer.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT COALESCE(SUM(LENGTH(json)), 0) AS b, COUNT(*) AS n FROM ocrResult")
            return (row?["b"] ?? 0, row?["n"] ?? 0)
        }
    }

    public func clearOCRCache(documentId: String? = nil) throws {
        try writer.write { db in
            if let documentId {
                try db.execute(sql: "DELETE FROM ocrResult WHERE documentId = ?", arguments: [documentId])
            } else {
                try db.execute(sql: "DELETE FROM ocrResult")
            }
        }
    }

    // MARK: Banc d'essai

    public func benchSamples() throws -> [BenchSample] {
        try writer.read { db in try BenchSample.order(Column("createdAt")).fetchAll(db) }
    }

    public func save(_ sample: BenchSample) throws {
        try writer.write { db in try sample.save(db) }
    }

    public func deleteBenchSample(id: String) throws {
        try writer.write { db in _ = try BenchSample.deleteOne(db, key: id) }
    }

    public func benchRuns(sampleId: String) throws -> [BenchRun] {
        try writer.read { db in
            try BenchRun.filter(Column("sampleId") == sampleId).order(Column("createdAt").desc).fetchAll(db)
        }
    }

    /// Dernier essai de chaque (échantillon, moteur).
    public func latestBenchRuns() throws -> [BenchRun] {
        try writer.read { db in
            try BenchRun.fetchAll(db, sql: """
                SELECT r.* FROM benchRun r
                JOIN (SELECT sampleId, engine, MAX(createdAt) AS c FROM benchRun GROUP BY sampleId, engine) last
                ON r.sampleId = last.sampleId AND r.engine = last.engine AND r.createdAt = last.c
                """)
        }
    }

    public func save(_ run: BenchRun) throws {
        try writer.write { db in try run.save(db) }
    }
}
