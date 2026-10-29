// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB

/// Modifications des pages d'un document (#49), côté base de l'app. Plan revu par Codex le 29/10/2026 :
///
/// - **Identité des pages** (`pageIdentity`) : chaque page physique a un identifiant stable et garde son numéro
///   imprimé (R5). La table est créée à la première modification, depuis la numérotation actuelle.
/// - **Version de mise en page** (`document.layoutVersion`) : change à chaque opération ; l'opération appliquée est
///   enregistrée (`pageEdit`) **dans la même transaction**. Une reprise reconnaît donc l'opération par son
///   identifiant, pas par le seul nombre de pages (deux opérations peuvent donner le même total).
/// - **Archive** (`pageEditRow`) : les lignes des pages retirées sont copiées dans la même transaction, avant d'être
///   effacées ; aucune donnée active n'est modifiée si la copie échoue (R1). L'archive suit le document : effacée
///   avec lui (cascade), conservée tant qu'il est dans la corbeille.
extension AppDatabase {
    /// Tables rangées par numéro de page, toutes clés comprises (mêmes six tables que `shiftPages`).
    static let pageTables = ["ocrResult", "highlight", "inkDrawing", "bookmark", "pageComment", "pageTransform"]

    public enum PageEditKind: String, Codable, Sendable { case insertion, removal, restoration }

    public struct PageEditError: LocalizedError {
        public let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    /// Une page physique : position actuelle (base 0), identifiant stable, numéro imprimé s'il est connu.
    public struct PageIdentity: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
        public static let databaseTableName = "pageIdentity"
        public var documentId: String
        public var position: Int
        public var pageId: String
        public var printedNumber: Int?
    }

    /// Une opération appliquée. `pageOrder` = identifiants de toutes les pages **avant** l'opération, dans l'ordre :
    /// une restauration replace les pages après la page restante qui les précédait, quel que soit l'ordre
    /// d'annulation de plusieurs suppressions (R2).
    public struct PageEdit: Equatable, Sendable {
        public var id: String
        public var documentId: String
        public var kind: PageEditKind
        public var versionBefore: Int
        public var versionAfter: Int
        public var appliedAt: Date
        public var mapping: PageMapping
        public var pageOrder: [String]
    }

    /// Valeur SQLite archivée telle quelle (texte, nombre, blob ou NULL), pour réinsérer une ligne à l'identique.
    public enum ArchivedValue: Codable, Equatable, Sendable {
        case null, integer(Int64), real(Double), text(String), blob(Data)

        init(_ value: DatabaseValue) {
            switch value.storage {
            case .null: self = .null
            case .int64(let v): self = .integer(v)
            case .double(let v): self = .real(v)
            case .string(let v): self = .text(v)
            case .blob(let v): self = .blob(v)
            }
        }

        var databaseValue: DatabaseValue {
            switch self {
            case .null: return .null
            case .integer(let v): return v.databaseValue
            case .real(let v): return v.databaseValue
            case .text(let v): return v.databaseValue
            case .blob(let v): return v.databaseValue
            }
        }
    }

    /// Ligne archivée d'une page retirée.
    public struct ArchivedRow: Equatable, Sendable {
        public var tableName: String
        public var pageId: String
        public var columns: [String: ArchivedValue]
    }

    public func layoutVersion(documentId: String) throws -> Int? {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT layoutVersion FROM document WHERE id = ?", arguments: [documentId])
        }
    }

    public func pageIdentities(documentId: String) throws -> [PageIdentity] {
        try writer.read { db in
            try PageIdentity.filter(Column("documentId") == documentId).order(Column("position")).fetchAll(db)
        }
    }

    public func pageEdit(id: String) throws -> PageEdit? {
        try writer.read { db in try Self.fetchEdit(db, id: id) }
    }

    public func archivedRows(editId: String) throws -> [ArchivedRow] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT tableName, pageId, rowJSON FROM pageEditRow WHERE editId = ? ORDER BY rowid",
                             arguments: [editId]).map { row in
                ArchivedRow(tableName: row["tableName"], pageId: row["pageId"],
                            columns: try JSONDecoder().decode([String: ArchivedValue].self, from: row["rowJSON"] as Data))
            }
        }
    }

    /// Applique `mapping` à tout ce que la base range par numéro de page, en **une** transaction : archive des lignes
    /// des pages retirées, effacement de ces lignes, renumérotation des autres, identités des pages, position de
    /// lecture, page 1, nombre de pages, taille, version, et enregistrement de l'opération.
    ///
    /// Rejouable : si `editId` est déjà enregistré, rien n'est refait et la fonction renvoie `false`. Sinon, le
    /// document doit être exactement dans l'état attendu (`expectedVersion` et `mapping.oldCount`), sans quoi rien
    /// n'est modifié. Les cartes (`review.sqlite`) se remappent à part : `ReviewStore.remapSourcePages`.
    @discardableResult
    public func remapPages(documentId: String, mapping: PageMapping, editId: String, kind: PageEditKind,
                           expectedVersion: Int, fileSize: Int64, at date: Date = Date()) throws -> Bool {
        try writer.write { db in
            if let done = try Self.fetchEdit(db, id: editId) {
                // Rejeu (journal encore présent) : seule la **même** opération, sur un document resté dans l'état
                // qu'elle a produit, est reconnue ; toute divergence arrête la reprise (revue Codex F2).
                let current = try Row.fetchOne(db, sql: "SELECT pageCount, fileSize, layoutVersion FROM document WHERE id = ?",
                                               arguments: [documentId])
                guard done.documentId == documentId, done.kind == kind, done.mapping == mapping,
                      done.versionBefore == expectedVersion, let current,
                      current["layoutVersion"] as Int == done.versionAfter, current["pageCount"] as Int == mapping.newCount,
                      current["fileSize"] as Int64 == fileSize else {
                    throw PageEditError("Opération déjà enregistrée avec d'autres valeurs : reprise arrêtée sans modification.")
                }
                return false
            }
            guard let row = try Row.fetchOne(db, sql: """
                SELECT pageCount, layoutVersion, lastPageIndex, firstPageIndex FROM document WHERE id = ?
                """, arguments: [documentId]) else { throw PageEditError("Document introuvable.") }
            guard row["layoutVersion"] as Int == expectedVersion, row["pageCount"] as Int == mapping.oldCount else {
                throw PageEditError("Le document a changé depuis la préparation : aucune modification des pages.")
            }
            let identities = try Self.identities(db, documentId: documentId, pageCount: mapping.oldCount,
                                                 firstPageIndex: row["firstPageIndex"])
            let order = identities.map(\.pageId)
            let version = expectedVersion + 1
            // 0. L'opération d'abord (l'archive s'y rattache) ; même transaction : rien n'existe si la suite échoue.
            try db.execute(sql: """
                INSERT INTO pageEdit (id, documentId, kind, versionBefore, versionAfter, appliedAt, mappingJSON, pageOrderJSON)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [editId, documentId, kind.rawValue, expectedVersion, version, date,
                                 try JSONEncoder().encode(mapping), try JSONEncoder().encode(order)])

            // 1. Archive, avant tout effacement : lignes des six tables ET identité de chaque page retirée (position
            //    d'origine, numéro imprimé, même `nil` ; revue Codex F3), pour une restauration exacte.
            let removed = mapping.removed
            let archivedTables = Self.pageTables.map { ($0, "pageIndex") } + [("pageIdentity", "position")]
            for (table, column) in archivedTables where !removed.isEmpty {
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM \(table) WHERE documentId = ? AND \(column) IN (\(removed.map(String.init).joined(separator: ",")))",
                                            arguments: [documentId])
                for archived in rows {
                    let columns = Dictionary(uniqueKeysWithValues: archived.columnNames.map { ($0, ArchivedValue(archived[$0] as DatabaseValue)) })
                    try db.execute(sql: "INSERT INTO pageEditRow (editId, tableName, pageId, rowJSON) VALUES (?, ?, ?, ?)",
                                   arguments: [editId, table, order[archived[column] as Int], try JSONEncoder().encode(columns)])
                }
            }
            // 2. Effacement des pages retirées.
            for table in Self.pageTables where !removed.isEmpty {
                try db.execute(sql: "DELETE FROM \(table) WHERE documentId = ? AND pageIndex IN (\(removed.map(String.init).joined(separator: ",")))",
                               arguments: [documentId])
            }
            if !removed.isEmpty {
                try db.execute(sql: "DELETE FROM pageIdentity WHERE documentId = ? AND position IN (\(removed.map(String.init).joined(separator: ",")))",
                               arguments: [documentId])
            }
            // 3. Renumérotation en deux temps (valeurs négatives puis positives) : jamais deux lignes sur la même clé.
            let moves = mapping.targets.enumerated().compactMap { old, new in new.flatMap { $0 == old ? nil : (old, $0) } }
            for (table, column) in Self.pageTables.map({ ($0, "pageIndex") }) + [("pageIdentity", "position")] where !moves.isEmpty {
                for (old, new) in moves {
                    try db.execute(sql: "UPDATE \(table) SET \(column) = ? WHERE documentId = ? AND \(column) = ?",
                                   arguments: [-1 - new, documentId, old])
                }
                try db.execute(sql: "UPDATE \(table) SET \(column) = -1 - \(column) WHERE documentId = ? AND \(column) < 0",
                               arguments: [documentId])
            }
            // 4. Nouvelles pages : nouvel identifiant, sans numéro imprimé connu.
            for position in mapping.inserted {
                try PageIdentity(documentId: documentId, position: position, pageId: UUID().uuidString, printedNumber: nil).insert(db)
            }
            // 5. Document : la position de lecture et la page 1 suivent leur page, ou la plus proche qui reste.
            try db.execute(sql: """
                UPDATE document SET pageCount = ?, fileSize = ?, layoutVersion = ?, lastPageIndex = ?, firstPageIndex = ?
                WHERE id = ?
                """, arguments: [mapping.newCount, fileSize, version, Self.nearest(row["lastPageIndex"], in: mapping),
                                 Self.nearest(row["firstPageIndex"], in: mapping), documentId])
            return true
        }
    }

    /// Nouvelle position d'une ancienne page ; si elle est retirée, celle de la page suivante qui reste, sinon de la
    /// précédente. Une suppression valide garde toujours au moins une page.
    static func nearest(_ page: Int, in mapping: PageMapping) -> Int {
        let clamped = min(max(page, 0), mapping.oldCount - 1)
        if let target = mapping.target(of: clamped) { return target }
        if let after = (clamped..<mapping.oldCount).lazy.compactMap(mapping.target(of:)).first { return after }
        return (0..<clamped).reversed().lazy.compactMap(mapping.target(of:)).first ?? 0
    }

    /// Identités du document ; créées au premier besoin depuis la numérotation actuelle (page 1 = `firstPageIndex`).
    /// Une table incomplète n'est jamais complétée en devinant : l'opération s'arrête.
    private static func identities(_ db: Database, documentId: String, pageCount: Int, firstPageIndex: Int) throws -> [PageIdentity] {
        let existing = try PageIdentity.filter(Column("documentId") == documentId).order(Column("position")).fetchAll(db)
        if existing.isEmpty {
            let created = (0..<pageCount).map { position in
                PageIdentity(documentId: documentId, position: position, pageId: UUID().uuidString,
                             printedNumber: position >= firstPageIndex ? position - firstPageIndex + 1 : nil)
            }
            for identity in created { try identity.insert(db) }
            return created
        }
        guard existing.map(\.position) == Array(0..<pageCount) else {
            throw PageEditError("Identités des pages incohérentes : aucune modification des pages.")
        }
        return existing
    }

    private static func fetchEdit(_ db: Database, id: String) throws -> PageEdit? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM pageEdit WHERE id = ?", arguments: [id]),
              let kind = PageEditKind(rawValue: row["kind"]) else { return nil }
        return PageEdit(id: row["id"], documentId: row["documentId"], kind: kind,
                        versionBefore: row["versionBefore"], versionAfter: row["versionAfter"], appliedAt: row["appliedAt"],
                        mapping: try JSONDecoder().decode(PageMapping.self, from: row["mappingJSON"] as Data),
                        pageOrder: try JSONDecoder().decode([String].self, from: row["pageOrderJSON"] as Data))
    }
}
