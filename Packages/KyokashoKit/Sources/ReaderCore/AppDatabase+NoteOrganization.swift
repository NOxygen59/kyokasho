// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB

// Rangement des notes — PLAN-T4-001, étape E1 (plan approuvé par NOxygen59 le 11/11/2026, recommandations A).
//
// Décisions : échéance « avant le… » (un jour), priorité haute / normale / basse (normale par défaut, DEC-T4-07),
// archive à la main seulement (DEC-T4-08), **un** classeur et **plusieurs** étiquettes par note (DEC-T4-05) ; la
// pastille de l'accueil compte les notes non archivées dont l'échéance est passée, aujourd'hui ou demain (DEC-T4-06).
//
// Invariants (voir la migration `v7-note-organization`) :
// - les colonnes `dueDay`, `priority`, `archived`, `noteFolderId`, `tagIds` vivent dans la ligne `pageComment` mais pas
//   dans `PageComment` : elles ne sont lues et écrites **qu'ici**, par des UPDATE ciblés ; enregistrer le texte ou le
//   dessin d'une note ne peut pas les effacer ;
// - étant dans la ligne, elles suivent la note partout où elle est copiée (paquets, pages retirées puis restaurées,
//   fusion de remplacement Drive) sans code de plus ;
// - classeur et étiquettes sont référencés sans clé étrangère : un identifiant inconnu (paquet venu d'un autre appareil,
//   classeur supprimé ailleurs) est ignoré à la lecture, jamais une erreur ; supprimer un classeur ou une étiquette
//   les retire des notes présentes dans la même transaction. Limite connue (revue DeepSeek R2 n°1) : une note dont la
//   page est retirée vit dans l'archive des pages (`pageEditRow`), qui n'est pas réécrite ; restaurée, elle garde
//   l'identifiant supprimé, ignoré à la lecture (aucun effet visible) ;
// - une échéance non canonique (paquet modifié à la main) est ignorée à la lecture et par la pastille ;
// - réorganiser une note ne change pas son `updatedAt` (revue DeepSeek n°4) : la date reste celle du contenu ;
// - `tagIds` est un tableau JSON trié et sans doublon (forme canonique, comparable).

/// Classeur de notes (un par note au plus).
public struct NoteFolder: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "noteFolder"
    public var id: String
    public var name: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// Étiquette de note (plusieurs par note).
public struct NoteTag: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "noteTag"
    public var id: String
    public var name: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

public enum NotePriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case low = 0, normal = 1, high = 2

    public static func < (lhs: NotePriority, rhs: NotePriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Rangement d'une note.
public struct NoteOrganization: Equatable, Hashable, Sendable {
    /// Échéance « avant le… », jour local « AAAA-MM-JJ » ; `nil` : aucune.
    public var dueDay: String?
    public var priority: NotePriority
    public var archived: Bool
    public var folderId: String?
    /// Triées, sans doublon.
    public var tagIds: [String]

    public static let `default` = NoteOrganization(dueDay: nil, priority: .normal, archived: false, folderId: nil, tagIds: [])

    public init(dueDay: String?, priority: NotePriority, archived: Bool, folderId: String?, tagIds: [String]) {
        self.dueDay = dueDay
        self.priority = priority
        self.archived = archived
        self.folderId = folderId
        self.tagIds = tagIds
    }
}

/// Une note avec son rangement (écran « Notes », PLAN-T4-001 E2).
public struct OrganizedNote: Identifiable, Equatable, Sendable {
    public var id: String { note.id }
    public var note: PageComment
    public var organization: NoteOrganization
}

/// Modification de rangement appliquée à une ou plusieurs notes (tout ou rien).
public enum NoteChange: Equatable, Sendable {
    case due(String?)
    case priority(NotePriority)
    case archived(Bool)
    case folder(String?)
    case addTag(String)
    case removeTag(String)
}

public enum NoteOrganizationError: LocalizedError, Equatable {
    case emptyName, invalidDay, folderNotFound, tagNotFound, duplicateName, noteNotFound

    public var errorDescription: String? {
        switch self {
        case .emptyName: return String(localized: "Donne un nom.", bundle: .main)
        case .invalidDay: return String(localized: "Date d'échéance invalide.", bundle: .main)
        case .folderNotFound: return String(localized: "Ce classeur n'existe plus.", bundle: .main)
        case .tagNotFound: return String(localized: "Cette étiquette n'existe plus.", bundle: .main)
        case .duplicateName: return String(localized: "Une étiquette porte déjà ce nom.", bundle: .main)
        case .noteNotFound: return String(localized: "Cette note n'existe plus.", bundle: .main)
        }
    }
}

/// Jours d'échéance : texte « AAAA-MM-JJ » dans le calendrier de l'appareil (une échéance est un jour, pas une heure :
/// changer de fuseau ne la déplace pas). Fonctions pures, testées.
public enum NoteDay {
    /// Calendrier des jours d'échéance (revue GLM R2 n°1) : toujours grégorien, au fuseau de l'appareil. Avec le
    /// calendrier de l'iPad réglé sur « japonais », `Calendar.current` aurait écrit l'année d'ère (« 0008-… ») : tri et
    /// comparaisons faux.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    public static func string(_ date: Date, calendar: Calendar = NoteDay.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func isValid(_ day: String) -> Bool {
        let parts = day.split(separator: "-")
        guard day.count == 10, parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayNumber = Int(parts[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: dayNumber)) else { return false }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        return check.year == year && check.month == month && check.day == dayNumber
    }

    /// DEC-T4-06 : à revoir = non archivée, échéance passée, aujourd'hui ou demain. Même règle, en SQL, dans
    /// `notesToReviewCount` (pastille) et, par groupes, dans `NoteListing.Group.isToReview` (écran) : les trois sont
    /// comparées par `NoteListingTests` (revue DeepSeek F6).
    public static func isToReview(_ organization: NoteOrganization, today: Date, calendar: Calendar = NoteDay.calendar) -> Bool {
        guard !organization.archived, let due = organization.dueDay else { return false }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return false }
        return due <= string(tomorrow, calendar: calendar)
    }
}

extension AppDatabase {
    // MARK: Classeurs

    public func noteFolders() throws -> [NoteFolder] {
        try writer.read { db in try Self.sortedByName(NoteFolder.fetchAll(db)) { $0.name } }
    }

    public func createNoteFolder(name: String) throws -> NoteFolder {
        let folder = NoteFolder(name: try Self.clean(name))
        try writer.write { db in try folder.insert(db) }
        return folder
    }

    public func renameNoteFolder(id: String, to name: String) throws {
        let clean = try Self.clean(name)
        try writer.write { db in
            try db.execute(sql: "UPDATE noteFolder SET name = ? WHERE id = ?", arguments: [clean, id])
            guard db.changesCount == 1 else { throw NoteOrganizationError.folderNotFound }
        }
    }

    /// Supprime le classeur ; ses notes restent, sans classeur.
    public func deleteNoteFolder(id: String) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE pageComment SET noteFolderId = NULL WHERE noteFolderId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM noteFolder WHERE id = ?", arguments: [id])
        }
    }

    // MARK: Étiquettes

    public func noteTags() throws -> [NoteTag] {
        try writer.read { db in try Self.sortedByName(NoteTag.fetchAll(db)) { $0.name } }
    }

    /// Étiquette de ce nom (sans tenir compte des majuscules), créée si elle n'existe pas : on tape un nom, jamais deux
    /// étiquettes « Test S46 » et « test s46 ».
    public func noteTag(named name: String) throws -> NoteTag {
        let clean = try Self.clean(name)
        return try writer.write { db in
            if let existing = try NoteTag.fetchAll(db).first(where: { $0.name.compare(clean, options: .caseInsensitive) == .orderedSame }) {
                return existing
            }
            let tag = NoteTag(name: clean)
            try tag.insert(db)
            return tag
        }
    }

    public func renameNoteTag(id: String, to name: String) throws {
        let clean = try Self.clean(name)
        try writer.write { db in
            // Revue DeepSeek n°7 : comme à la création, jamais deux étiquettes au même nom (sans les majuscules).
            if try NoteTag.fetchAll(db).contains(where: { $0.id != id && $0.name.compare(clean, options: .caseInsensitive) == .orderedSame }) {
                throw NoteOrganizationError.duplicateName
            }
            try db.execute(sql: "UPDATE noteTag SET name = ? WHERE id = ?", arguments: [clean, id])
            guard db.changesCount == 1 else { throw NoteOrganizationError.tagNotFound }
        }
    }

    /// Supprime l'étiquette et la retire de toutes les notes, dans la même transaction.
    public func deleteNoteTag(id: String) throws {
        try writer.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, tagIds FROM pageComment WHERE instr(tagIds, ?) > 0",
                                        arguments: [Self.quoted(id)])
            for row in rows {
                let tags = Self.decodeTags(row["tagIds"]).filter { $0 != id }
                try db.execute(sql: "UPDATE pageComment SET tagIds = ? WHERE id = ?",
                               arguments: [Self.encodeTags(tags), row["id"] as String])
            }
            try db.execute(sql: "DELETE FROM noteTag WHERE id = ?", arguments: [id])
        }
    }

    // MARK: Rangement des notes

    /// Applique `change` à toutes les notes données, tout ou rien. Seules les colonnes de rangement sont écrites.
    /// Une note disparue (supprimée ailleurs pendant que l'écran était ouvert) annule tout le lot
    /// (`noteNotFound`, revue DeepSeek D-07 F4) : jamais un « succès » qui n'a rien écrit.
    public func apply(_ change: NoteChange, to noteIds: [String]) throws {
        guard !noteIds.isEmpty else { return }
        try writer.write { db in
            for id in Set(noteIds) where try !Self.noteExists(db, id) { throw NoteOrganizationError.noteNotFound }
            switch change {
            case .due(let day):
                if let day, !NoteDay.isValid(day) { throw NoteOrganizationError.invalidDay }
                try Self.update(db, "dueDay", day, noteIds)
            case .priority(let priority):
                try Self.update(db, "priority", priority.rawValue, noteIds)
            case .archived(let archived):
                try Self.update(db, "archived", archived, noteIds)
            case .folder(let folderId):
                if let folderId, try NoteFolder.fetchOne(db, key: folderId) == nil { throw NoteOrganizationError.folderNotFound }
                try Self.update(db, "noteFolderId", folderId, noteIds)
            case .addTag(let tagId), .removeTag(let tagId):
                if case .addTag = change, try NoteTag.fetchOne(db, key: tagId) == nil { throw NoteOrganizationError.tagNotFound }
                for id in noteIds {
                    guard let raw = try String.fetchOne(db, sql: "SELECT tagIds FROM pageComment WHERE id = ?", arguments: [id])
                    else { continue }
                    var tags = Set(Self.decodeTags(raw))
                    if case .addTag = change { tags.insert(tagId) } else { tags.remove(tagId) }
                    try db.execute(sql: "UPDATE pageComment SET tagIds = ? WHERE id = ?",
                                   arguments: [Self.encodeTags(Array(tags)), id])
                }
            }
        }
    }

    /// Étiquette de ce nom (créée au besoin) posée sur la note, en une transaction : si la note a disparu, rien n'est
    /// créé (revue DeepSeek D-07 F4 : pas d'étiquette orpheline).
    public func addTag(named name: String, toNote noteId: String) throws {
        let clean = try Self.clean(name)
        try writer.write { db in
            guard try Self.noteExists(db, noteId) else { throw NoteOrganizationError.noteNotFound }
            let tag: NoteTag
            if let existing = try NoteTag.fetchAll(db).first(where: { $0.name.compare(clean, options: .caseInsensitive) == .orderedSame }) {
                tag = existing
            } else {
                tag = NoteTag(name: clean)
                try tag.insert(db)
            }
            let raw = try String.fetchOne(db, sql: "SELECT tagIds FROM pageComment WHERE id = ?", arguments: [noteId])
            try db.execute(sql: "UPDATE pageComment SET tagIds = ? WHERE id = ?",
                           arguments: [Self.encodeTags(Self.decodeTags(raw) + [tag.id]), noteId])
        }
    }

    /// Classeur créé et donné à la note en une transaction : si la note a disparu, rien n'est créé (relecture finale
    /// f2b3d49, N2 : même règle que `addTag(named:toNote:)`).
    @discardableResult
    public func createNoteFolder(name: String, assigningTo noteId: String) throws -> NoteFolder {
        let folder = NoteFolder(name: try Self.clean(name))
        try writer.write { db in
            guard try Self.noteExists(db, noteId) else { throw NoteOrganizationError.noteNotFound }
            try folder.insert(db)
            try db.execute(sql: "UPDATE pageComment SET noteFolderId = ? WHERE id = ?", arguments: [folder.id, noteId])
        }
        return folder
    }

    /// Rangement d'une note (identifiants inconnus de classeur ou d'étiquette retirés).
    public func organization(noteId: String) throws -> NoteOrganization? {
        try writer.read { db in
            let known = try Self.knownIds(db)
            return try Row.fetchOne(db, sql: "SELECT \(Self.columns) FROM pageComment WHERE id = ?", arguments: [noteId])
                .map { Self.organization($0, known: known) }
        }
    }

    /// Toutes les notes de tous les documents avec leur rangement (écran « Notes ») ; archivées seulement si demandé.
    /// Revue GLM R2 (n°2) : le dessin (`drawing`) n'est pas lu, la liste n'en a pas besoin (`note.drawing == nil`) ;
    /// ouvrir la note dans le lecteur relit la note complète.
    /// `excludingDocuments` : documents à la corbeille (hors base), comme pour la pastille (revue DeepSeek n°2).
    public func organizedNotes(includeArchived: Bool, excludingDocuments: Set<String> = []) throws -> [OrganizedNote] {
        try writer.read { db in
            let known = try Self.knownIds(db)
            var sql = "SELECT id, documentId, pageIndex, body, createdAt, updatedAt, anchorX, anchorY, anchorWidth, anchorHeight, anchorText, \(Self.columns) FROM pageComment"
            if !includeArchived { sql += " WHERE archived = 0" }
            sql += " ORDER BY documentId, pageIndex, createdAt"
            return try Row.fetchAll(db, sql: sql).filter { !excludingDocuments.contains($0["documentId"] as String) }.map { row in
                OrganizedNote(note: try PageComment(row: row), organization: Self.organization(row, known: known))
            }
        }
    }

    /// Pastille de l'accueil (DEC-T4-06) : notes non archivées à revoir, hors documents donnés (corbeille).
    public func notesToReviewCount(today: Date, calendar: Calendar = NoteDay.calendar, excludingDocuments: Set<String> = []) throws -> Int {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return 0 }
        let limit = NoteDay.string(tomorrow, calendar: calendar)
        return try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT documentId, dueDay FROM pageComment WHERE archived = 0 AND dueDay IS NOT NULL AND dueDay <= ?",
                             arguments: [limit])
                .filter { NoteDay.isValid($0["dueDay"] as String) && !excludingDocuments.contains($0["documentId"] as String) }.count
        }
    }

    // MARK: Interne

    private static let columns = "dueDay, priority, archived, noteFolderId, tagIds"

    private static func update(_ db: Database, _ column: String, _ value: (any DatabaseValueConvertible)?, _ ids: [String]) throws {
        for id in ids {
            try db.execute(sql: "UPDATE pageComment SET \(column) = ? WHERE id = ?", arguments: [value, id])
        }
    }

    private static func noteExists(_ db: Database, _ id: String) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM pageComment WHERE id = ?)", arguments: [id]) ?? false
    }

    private static func knownIds(_ db: Database) throws -> (folders: Set<String>, tags: Set<String>) {
        (Set(try String.fetchAll(db, sql: "SELECT id FROM noteFolder")), Set(try String.fetchAll(db, sql: "SELECT id FROM noteTag")))
    }

    private static func organization(_ row: Row, known: (folders: Set<String>, tags: Set<String>)) -> NoteOrganization {
        let folder: String? = row["noteFolderId"]
        let due: String? = row["dueDay"]
        return NoteOrganization(dueDay: due.flatMap { NoteDay.isValid($0) ? $0 : nil },
                                priority: NotePriority(rawValue: row["priority"] ?? 1) ?? .normal,
                                archived: row["archived"] ?? false,
                                folderId: folder.flatMap { known.folders.contains($0) ? $0 : nil },
                                tagIds: decodeTags(row["tagIds"]).filter { known.tags.contains($0) })
    }

    static func decodeTags(_ raw: String?) -> [String] {
        guard let data = raw?.data(using: .utf8), let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Array(Set(list)).sorted()
    }

    static func encodeTags(_ tags: [String]) -> String {
        let data = (try? JSONEncoder().encode(Array(Set(tags)).sorted())) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func quoted(_ id: String) -> String {
        String(decoding: (try? JSONEncoder().encode(id)) ?? Data(), as: UTF8.self)
    }

    private static func clean(_ name: String) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw NoteOrganizationError.emptyName }
        return clean
    }

    private static func sortedByName<T>(_ items: [T], _ name: (T) -> String) -> [T] {
        items.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
    }
}
