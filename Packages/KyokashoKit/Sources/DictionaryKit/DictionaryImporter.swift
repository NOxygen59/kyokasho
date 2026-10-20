// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB
import ZIPFoundation

/// Importe un dictionnaire au format Yomitan (zip : index.json, term_bank_N.json,
/// term_meta_bank_N.json, kanji_bank_N.json, kanji_meta_bank_N.json, tag_bank_N.json,
/// styles.css, médias). Lecture **en flux** : un fichier du zip à la fois, insertion par lots
/// de quelques milliers de lignes ; un gros dictionnaire n'est jamais entièrement en mémoire.
public struct DictionaryImporter: Sendable {
    public struct Progress: Sendable, Equatable {
        public var step: String
        public var fraction: Double
    }

    public enum ImportError: LocalizedError, Equatable {
        case notADictionary
        case unsupportedFormat(Int)
        case alreadyImported(String, String)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .notADictionary: return "Ce fichier n'est pas un dictionnaire Yomitan (index.json manquant)."
            case .unsupportedFormat(let f): return "Format de dictionnaire non pris en charge (\(f))."
            case .alreadyImported(let title, let revision): return "« \(title) » (\(revision)) est déjà importé."
            case .cancelled: return "Import annulé."
            }
        }
    }

    struct Index: Decodable {
        let title: String
        let revision: String
        let format: Int?
        let version: Int?
        let sequenced: Bool?
        let author: String?
        let url: String?
        let description: String?
        let attribution: String?
    }

    public let database: DictionaryDatabase
    public var batchSize = 5000

    public init(database: DictionaryDatabase) {
        self.database = database
    }

    /// Importe le zip (synchrone : à lancer dans une tâche de fond ; l'annulation de la tâche
    /// arrête l'import proprement). `replaceExisting` : même titre déjà présent → mise à jour.
    @discardableResult
    public func importDictionary(at url: URL, replaceExisting: Bool = true,
                                 progress: (Progress) -> Void = { _ in }) throws -> DictionaryInfo {
        let archive = try Archive(url: url, accessMode: .read)
        guard let indexEntry = archive["index.json"] else { throw ImportError.notADictionary }
        let index = try JSONDecoder().decode(Index.self, from: try extract(indexEntry, from: archive))
        let format = index.format ?? index.version ?? 3
        guard format == 1 || format == 2 || format == 3 else { throw ImportError.unsupportedFormat(format) }

        var replacedPriority: Int?
        if let existing = try database.dictionary(title: index.title) {
            guard replaceExisting else { throw ImportError.alreadyImported(index.title, index.revision) }
            progress(Progress(step: "Suppression de l'ancienne version", fraction: 0))
            replacedPriority = existing.priority
            try database.deleteDictionary(id: existing.id!)
        }

        let styles = archive["styles.css"].flatMap { try? String(decoding: extract($0, from: archive), as: UTF8.self) }
        let nextPriority = try database.writer.read { db in try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(priority) + 1, 0) FROM dictionary") ?? 0 }
        var info = DictionaryInfo(title: index.title, revision: index.revision, format: format, sequenced: index.sequenced ?? false,
                                  author: index.author, url: index.url, description: index.description,
                                  attribution: index.attribution, priority: replacedPriority ?? nextPriority, enabled: true,
                                  styles: styles)
        info = try database.writer.write { [info] db in try info.inserted(db) }
        let dictionaryId = info.id!

        do {
            let entries = archive.filter { $0.type == .file }
            func banks(_ prefix: String) -> [Entry] {
                entries.filter { $0.path.hasPrefix(prefix) && $0.path.hasSuffix(".json") }
                    .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            }
            let tagBanks = banks("tag_bank_")
            let termBanks = banks("term_bank_")
            let termMetaBanks = banks("term_meta_bank_")
            let kanjiBanks = banks("kanji_bank_")
            let kanjiMetaBanks = banks("kanji_meta_bank_")
            let media = entries.filter { e in
                let p = e.path.lowercased()
                return !p.hasSuffix(".json") && !p.hasSuffix(".css") && !p.hasPrefix("__macosx")
            }
            let totalFiles = Double(max(1, tagBanks.count + termBanks.count + termMetaBanks.count + kanjiBanks.count
                                        + kanjiMetaBanks.count + (media.isEmpty ? 0 : 1)))
            var done = 0.0
            func report(_ step: String) {
                progress(Progress(step: step, fraction: done / totalFiles))
            }

            var counts = (terms: 0, termMeta: 0, kanji: 0, kanjiMeta: 0, media: 0)

            for entry in tagBanks {
                try Task.checkCancellation()
                report("Étiquettes")
                try importRows(entry, archive: archive, sql: "INSERT INTO tag (dictionaryId, name, category, sortOrder, notes, score) VALUES (?,?,?,?,?,?)") { row in
                    guard row.count >= 5 else { return nil }
                    return [dictionaryId, str(row[0]), str(row[1]), int(row[2]), str(row[3]), int(row[4])]
                }
                done += 1
            }
            // Format 1 : les tags sont dans index.json (tagMeta) — ignorés (rarissime aujourd'hui).

            for entry in termBanks {
                try Task.checkCancellation()
                report("Termes · \(entry.path)")
                counts.terms += try importRows(entry, archive: archive,
                    sql: "INSERT INTO term (dictionaryId, expression, reading, definitionTags, rules, score, glossary, sequence, termTags) VALUES (?,?,?,?,?,?,?,?,?)") { row in
                    guard row.count >= 5 else { return nil }
                    let expression = str(row[0])
                    let reading = str(row[1]).isEmpty ? expression : str(row[1])
                    let glossary: Any
                    let sequence: Int
                    let termTags: String
                    if format == 1 {
                        glossary = Array(row.dropFirst(5))
                        sequence = 0
                        termTags = ""
                    } else {
                        glossary = row.count > 5 ? row[5] : []
                        sequence = row.count > 6 ? int(row[6]) : 0
                        termTags = row.count > 7 ? str(row[7]) : ""
                    }
                    return [dictionaryId, expression, reading, str(row[2]), str(row[3]), int(row[4]),
                            json(glossary), sequence, termTags]
                }
                done += 1
            }

            for entry in termMetaBanks {
                try Task.checkCancellation()
                report("Fréquences et accents")
                counts.termMeta += try importRows(entry, archive: archive,
                    sql: "INSERT INTO termMeta (dictionaryId, expression, mode, data) VALUES (?,?,?,?)") { row in
                    guard row.count >= 3 else { return nil }
                    return [dictionaryId, str(row[0]), str(row[1]), json(row[2])]
                }
                done += 1
            }

            for entry in kanjiBanks {
                try Task.checkCancellation()
                report("Kanji")
                counts.kanji += try importRows(entry, archive: archive,
                    sql: "INSERT INTO kanji (dictionaryId, character, onyomi, kunyomi, tags, meanings, stats) VALUES (?,?,?,?,?,?,?)") { row in
                    guard row.count >= 4 else { return nil }
                    let meanings: [Any]
                    var stats: [String: String] = [:]
                    if format == 1 {
                        meanings = Array(row.dropFirst(4))
                    } else {
                        meanings = (row.count > 4 ? row[4] as? [Any] : nil) ?? []
                        if row.count > 5, let s = row[5] as? [String: Any] {
                            for (k, v) in s { stats[k] = "\(v)" }
                        }
                    }
                    return [dictionaryId, str(row[0]), str(row[1]), str(row[2]), str(row[3]),
                            json(meanings.map { "\($0)" }), json(stats)]
                }
                done += 1
            }

            for entry in kanjiMetaBanks {
                try Task.checkCancellation()
                report("Fréquences des kanji")
                counts.kanjiMeta += try importRows(entry, archive: archive,
                    sql: "INSERT INTO kanjiMeta (dictionaryId, character, mode, data) VALUES (?,?,?,?)") { row in
                    guard row.count >= 3 else { return nil }
                    return [dictionaryId, str(row[0]), str(row[1]), json(row[2])]
                }
                done += 1
            }

            if !media.isEmpty {
                report("Images (\(media.count))")
                let folder = database.mediaRoot.appendingPathComponent(String(dictionaryId), isDirectory: true)
                for entry in media {
                    try Task.checkCancellation()
                    let destination = folder.appendingPathComponent(entry.path)
                    // Pas de chemin qui sort du dossier du dictionnaire.
                    guard destination.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path) else { continue }
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    _ = try archive.extract(entry, to: destination, skipCRC32: true)
                    counts.media += 1
                }
                done += 1
            }

            info.termCount = counts.terms
            info.termMetaCount = counts.termMeta
            info.kanjiCount = counts.kanji
            info.kanjiMetaCount = counts.kanjiMeta
            info.mediaCount = counts.media
            let final = info
            try database.writer.write { db in try final.update(db) }
            database.clearCaches()
            progress(Progress(step: "Terminé", fraction: 1))
            return final
        } catch {
            // Import incomplet : on ne laisse pas un dictionnaire à moitié rempli.
            try? database.deleteDictionary(id: dictionaryId)
            if error is CancellationError { throw ImportError.cancelled }
            throw error
        }
    }

    // MARK: Lecture d'un fichier du zip

    private func extract(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        data.reserveCapacity(Int(entry.uncompressedSize))
        _ = try archive.extract(entry, skipCRC32: true) { chunk in data.append(chunk) }
        return data
    }

    /// Insère les lignes d'un fichier JSON (tableau de tableaux) par lots ; renvoie le nombre de lignes.
    @discardableResult
    private func importRows(_ entry: Entry, archive: Archive, sql: String,
                            map: ([Any]) -> [DatabaseValueConvertible?]?) throws -> Int {
        let rows: [Any] = try autoreleasepool {
            let data = try extract(entry, from: archive)
            return (try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any]) ?? []
        }
        var inserted = 0
        var start = 0
        while start < rows.count {
            let end = min(start + batchSize, rows.count)
            let slice = rows[start..<end]
            try database.writer.write { db in
                let statement = try db.cachedStatement(sql: sql)
                for case let row as [Any] in slice {
                    guard let values = map(row) else { continue }
                    try statement.execute(arguments: StatementArguments(values))
                    inserted += 1
                }
            }
            start = end
        }
        return inserted
    }
}

// MARK: - Conversions JSON → SQLite

private func str(_ v: Any) -> String {
    switch v {
    case let s as String: return s
    case is NSNull: return ""
    case let n as NSNumber: return n.stringValue
    default: return ""
    }
}

private func int(_ v: Any) -> Int {
    switch v {
    case let n as NSNumber: return n.intValue
    case let s as String: return Int(s) ?? 0
    default: return 0
    }
}

private func json(_ v: Any) -> String {
    guard JSONSerialization.isValidJSONObject(v) || v is String || v is NSNumber,
          let data = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .withoutEscapingSlashes]) else {
        return "null"
    }
    return String(decoding: data, as: UTF8.self)
}
