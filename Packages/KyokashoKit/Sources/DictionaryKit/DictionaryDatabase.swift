// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB

/// Un dictionnaire importé (format Yomitan).
public struct DictionaryInfo: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "dictionary"

    public var id: Int64?
    public var title: String
    public var revision: String
    public var format: Int
    public var sequenced: Bool
    public var author: String?
    public var url: String?
    public var description: String?
    public var attribution: String?
    /// Plus petit = plus prioritaire (affiché en premier).
    public var priority: Int
    public var enabled: Bool
    public var termCount: Int
    public var termMetaCount: Int
    public var kanjiCount: Int
    public var kanjiMetaCount: Int
    public var mediaCount: Int
    public var styles: String?
    public var importedAt: Date

    public init(id: Int64? = nil, title: String, revision: String, format: Int, sequenced: Bool = false,
                author: String? = nil, url: String? = nil, description: String? = nil, attribution: String? = nil,
                priority: Int = 0, enabled: Bool = true, termCount: Int = 0, termMetaCount: Int = 0,
                kanjiCount: Int = 0, kanjiMetaCount: Int = 0, mediaCount: Int = 0, styles: String? = nil,
                importedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.revision = revision
        self.format = format
        self.sequenced = sequenced
        self.author = author
        self.url = url
        self.description = description
        self.attribution = attribution
        self.priority = priority
        self.enabled = enabled
        self.termCount = termCount
        self.termMetaCount = termMetaCount
        self.kanjiCount = kanjiCount
        self.kanjiMetaCount = kanjiMetaCount
        self.mediaCount = mediaCount
        self.styles = styles
        self.importedAt = importedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public var kind: String {
        if termCount > 0 { return "Termes" }
        if kanjiCount > 0 { return "Kanji" }
        if termMetaCount > 0 || kanjiMetaCount > 0 { return "Fréquence / accent" }
        return "—"
    }
}

/// Une entrée de terme brute (une ligne de `term_bank_*.json`).
public struct TermRow: Hashable, Sendable {
    public let id: Int64
    public let dictionaryId: Int64
    public let expression: String
    public let reading: String
    public let definitionTags: String
    public let rules: String
    public let score: Int
    /// JSON du tableau `glossary`.
    public let glossary: String
    public let sequence: Int
    public let termTags: String
}

public struct TermMetaRow: Hashable, Sendable {
    public let dictionaryId: Int64
    public let expression: String
    public let mode: String     // freq, pitch, ipa
    public let data: String     // JSON
}

/// Entrée légère pour parcourir les mots sans construire toutes leurs définitions.
public struct DictionaryWord: Hashable, Sendable, Identifiable {
    public var id: String { expression + "|" + reading }
    public let expression: String
    public let reading: String
    public let gloss: String
}

public struct KanjiRow: Hashable, Sendable {
    public let dictionaryId: Int64
    public let character: String
    public let onyomi: String
    public let kunyomi: String
    public let tags: String
    public let meanings: [String]
    public let stats: [String: String]
}

public struct TagRow: Hashable, Sendable {
    public let name: String
    public let category: String
    public let order: Int
    public let notes: String
    public let score: Int
}

/// Base SQLite des dictionnaires, séparée de celle de l'app (peut peser des centaines de Mo).
/// WAL : les recherches ne sont jamais bloquées par un import en cours.
public final class DictionaryDatabase: @unchecked Sendable {
    public let writer: any DatabaseWriter
    /// Dossier des médias (images des dictionnaires), un sous-dossier par dictionnaire.
    public let mediaRoot: URL

    public init(_ writer: any DatabaseWriter, mediaRoot: URL) throws {
        self.writer = writer
        self.mediaRoot = mediaRoot
        try Self.migrator.migrate(writer)
    }

    public static func open(directory: URL) throws -> DictionaryDatabase {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA cache_size = -32000")   // ~32 Mo
            try db.execute(sql: "PRAGMA mmap_size = 536870912") // 512 Mo mappés (lecture rapide)
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
        }
        let pool = try DatabasePool(path: directory.appendingPathComponent("dictionaries.sqlite").path, configuration: config)
        return try DictionaryDatabase(pool, mediaRoot: directory.appendingPathComponent("Media", isDirectory: true))
    }

    public static func inMemory() throws -> DictionaryDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dict-media-" + UUID().uuidString)
        return try DictionaryDatabase(DatabaseQueue(), mediaRoot: root)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "dictionary") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull().unique()
                t.column("revision", .text).notNull()
                t.column("format", .integer).notNull()
                t.column("sequenced", .boolean).notNull().defaults(to: false)
                t.column("author", .text)
                t.column("url", .text)
                t.column("description", .text)
                t.column("attribution", .text)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("termCount", .integer).notNull().defaults(to: 0)
                t.column("termMetaCount", .integer).notNull().defaults(to: 0)
                t.column("kanjiCount", .integer).notNull().defaults(to: 0)
                t.column("kanjiMetaCount", .integer).notNull().defaults(to: 0)
                t.column("mediaCount", .integer).notNull().defaults(to: 0)
                t.column("styles", .text)
                t.column("importedAt", .datetime).notNull()
            }
            // Tables compactes, sans clé étrangère (suppression par lots plus rapide).
            try db.execute(sql: """
                CREATE TABLE term (
                    id INTEGER PRIMARY KEY, dictionaryId INTEGER NOT NULL, expression TEXT NOT NULL,
                    reading TEXT NOT NULL, definitionTags TEXT NOT NULL, rules TEXT NOT NULL, score INTEGER NOT NULL,
                    glossary TEXT NOT NULL, sequence INTEGER NOT NULL, termTags TEXT NOT NULL);
                CREATE INDEX term_expression ON term(expression);
                CREATE INDEX term_reading ON term(reading);
                CREATE INDEX term_dictionary ON term(dictionaryId);
                CREATE TABLE termMeta (dictionaryId INTEGER NOT NULL, expression TEXT NOT NULL, mode TEXT NOT NULL, data TEXT NOT NULL);
                CREATE INDEX termMeta_expression ON termMeta(expression);
                CREATE INDEX termMeta_dictionary ON termMeta(dictionaryId);
                CREATE TABLE kanji (dictionaryId INTEGER NOT NULL, character TEXT NOT NULL, onyomi TEXT NOT NULL,
                    kunyomi TEXT NOT NULL, tags TEXT NOT NULL, meanings TEXT NOT NULL, stats TEXT NOT NULL);
                CREATE INDEX kanji_character ON kanji(character);
                CREATE INDEX kanji_dictionary ON kanji(dictionaryId);
                CREATE TABLE kanjiMeta (dictionaryId INTEGER NOT NULL, character TEXT NOT NULL, mode TEXT NOT NULL, data TEXT NOT NULL);
                CREATE INDEX kanjiMeta_character ON kanjiMeta(character);
                CREATE INDEX kanjiMeta_dictionary ON kanjiMeta(dictionaryId);
                CREATE TABLE tag (dictionaryId INTEGER NOT NULL, name TEXT NOT NULL, category TEXT NOT NULL,
                    sortOrder INTEGER NOT NULL, notes TEXT NOT NULL, score INTEGER NOT NULL);
                CREATE INDEX tag_name ON tag(dictionaryId, name);
                """)
        }
        return m
    }

    // MARK: Dictionnaires

    public func dictionaries() throws -> [DictionaryInfo] {
        try writer.read { db in try DictionaryInfo.order(Column("priority"), Column("title")).fetchAll(db) }
    }

    public func dictionary(title: String) throws -> DictionaryInfo? {
        try writer.read { db in try DictionaryInfo.filter(Column("title") == title).fetchOne(db) }
    }

    public func setEnabled(_ enabled: Bool, dictionaryId: Int64) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE dictionary SET enabled = ? WHERE id = ?", arguments: [enabled, dictionaryId])
        }
    }

    /// Nouvel ordre de priorité (le premier = le plus prioritaire).
    public func setOrder(_ ids: [Int64]) throws {
        try writer.write { db in
            for (i, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE dictionary SET priority = ? WHERE id = ?", arguments: [i, id])
            }
        }
    }

    /// Supprime un dictionnaire, par lots (pas de transaction géante ni de pic mémoire).
    public func deleteDictionary(id: Int64, progress: ((Double) -> Void)? = nil) throws {
        let tables = ["term", "termMeta", "kanji", "kanjiMeta", "tag"]
        for (i, table) in tables.enumerated() {
            while true {
                let changed: Int = try writer.write { db in
                    try db.execute(sql: "DELETE FROM \(table) WHERE rowid IN (SELECT rowid FROM \(table) WHERE dictionaryId = ? LIMIT 20000)",
                                   arguments: [id])
                    return db.changesCount
                }
                if changed == 0 { break }
            }
            progress?(Double(i + 1) / Double(tables.count + 1))
        }
        try writer.write { db in _ = try DictionaryInfo.deleteOne(db, key: id) }
        try? FileManager.default.removeItem(at: mediaRoot.appendingPathComponent(String(id)))
        progress?(1)
    }

    /// Récupère l'espace disque après des suppressions.
    public func vacuum() throws {
        try writer.vacuum()
    }

    // MARK: Recherche

    /// Début d'un mot ou d'une lecture. Chaque branche utilise son index SQLite.
    public func words(startingWith prefix: String, dictionaryIds: Set<Int64>, limit: Int = 60) throws -> [DictionaryWord] {
        guard !prefix.isEmpty, !dictionaryIds.isEmpty else { return [] }
        let ids = dictionaryIds.sorted()
        let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let boundedLimit = max(1, min(limit, 100))
        let upper = prefix + "\u{10FFFF}"
        return try writer.read { db in
            var result: [DictionaryWord] = []
            var seen = Set<String>()
            for column in ["expression", "reading"] {
                let sql = """
                    SELECT expression, reading, glossary FROM term
                    WHERE \(column) >= ? AND \(column) < ? AND dictionaryId IN (\(marks))
                    ORDER BY \(column), id LIMIT ?
                    """
                let arguments = StatementArguments([prefix, upper] + ids.map { String($0) } + [String(boundedLimit)])
                for row in try Row.fetchAll(db, sql: sql, arguments: arguments) {
                    let expression: String = row[0]
                    let reading: String = row[1]
                    let key = expression + "|" + reading
                    guard seen.insert(key).inserted else { continue }
                    let glossary: String = row[2]
                    result.append(DictionaryWord(expression: expression, reading: reading,
                                                 gloss: GlossaryText.plain(glossary)))
                    if result.count >= boundedLimit { return result }
                }
            }
            return result
        }
    }

    /// Entrées dont l'expression ou la lecture est dans `texts`, dictionnaires actifs seulement.
    public func terms(matching texts: [String], dictionaryIds: Set<Int64>) throws -> [TermRow] {
        guard !texts.isEmpty, !dictionaryIds.isEmpty else { return [] }
        let unique = Array(Set(texts))
        return try writer.read { db in
            var rows: [TermRow] = []
            var seen = Set<Int64>()
            for chunk in stride(from: 0, to: unique.count, by: 400).map({ Array(unique[$0..<min($0 + 400, unique.count)]) }) {
                let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                let sql = """
                    SELECT id, dictionaryId, expression, reading, definitionTags, rules, score, glossary, sequence, termTags
                    FROM term WHERE expression IN (\(marks)) OR reading IN (\(marks))
                    """
                let cursor = try Row.fetchCursor(db, sql: sql, arguments: StatementArguments(chunk + chunk))
                while let r = try cursor.next() {
                    let dictionaryId: Int64 = r[1]
                    let id: Int64 = r[0]
                    guard dictionaryIds.contains(dictionaryId), seen.insert(id).inserted else { continue }
                    rows.append(TermRow(id: id, dictionaryId: dictionaryId, expression: r[2], reading: r[3],
                                        definitionTags: r[4], rules: r[5], score: r[6], glossary: r[7],
                                        sequence: r[8], termTags: r[9]))
                }
            }
            return rows
        }
    }

    public func termMeta(for expressions: [String], dictionaryIds: Set<Int64>) throws -> [TermMetaRow] {
        guard !expressions.isEmpty, !dictionaryIds.isEmpty else { return [] }
        let unique = Array(Set(expressions))
        return try writer.read { db in
            let marks = Array(repeating: "?", count: unique.count).joined(separator: ",")
            return try Row.fetchAll(db, sql: "SELECT dictionaryId, expression, mode, data FROM termMeta WHERE expression IN (\(marks))",
                                    arguments: StatementArguments(unique))
                .filter { dictionaryIds.contains($0[0]) }
                .map { TermMetaRow(dictionaryId: $0[0], expression: $0[1], mode: $0[2], data: $0[3]) }
        }
    }

    public func kanji(_ character: String, dictionaryIds: Set<Int64>) throws -> [KanjiRow] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT dictionaryId, character, onyomi, kunyomi, tags, meanings, stats FROM kanji WHERE character = ?",
                             arguments: [character])
                .filter { dictionaryIds.contains($0[0]) }
                .map { r in
                    let meanings = (try? JSONDecoder().decode([String].self, from: Data((r[5] as String).utf8))) ?? []
                    let stats = (try? JSONDecoder().decode([String: String].self, from: Data((r[6] as String).utf8))) ?? [:]
                    return KanjiRow(dictionaryId: r[0], character: r[1], onyomi: r[2], kunyomi: r[3], tags: r[4],
                                    meanings: meanings, stats: stats)
                }
        }
    }

    public func kanjiMeta(_ character: String, dictionaryIds: Set<Int64>) throws -> [TermMetaRow] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT dictionaryId, character, mode, data FROM kanjiMeta WHERE character = ?", arguments: [character])
                .filter { dictionaryIds.contains($0[0]) }
                .map { TermMetaRow(dictionaryId: $0[0], expression: $0[1], mode: $0[2], data: $0[3]) }
        }
    }

    /// Étiquettes (« v5 », « n », « P »…) d'un dictionnaire, en cache après le premier appel.
    public func tags(dictionaryId: Int64) throws -> [String: TagRow] {
        if let cached = tagCacheLock.withLock({ tagCache[dictionaryId] }) { return cached }
        let rows: [String: TagRow] = try writer.read { db in
            var out: [String: TagRow] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT name, category, sortOrder, notes, score FROM tag WHERE dictionaryId = ?",
                                      arguments: [dictionaryId]) {
                let tag = TagRow(name: r[0], category: r[1], order: r[2], notes: r[3], score: r[4])
                out[tag.name] = tag
            }
            return out
        }
        tagCacheLock.withLock { tagCache[dictionaryId] = rows }
        return rows
    }

    public func clearCaches() {
        tagCacheLock.withLock { tagCache.removeAll() }
    }

    private var tagCache: [Int64: [String: TagRow]] = [:]
    private let tagCacheLock = NSLock()
}
