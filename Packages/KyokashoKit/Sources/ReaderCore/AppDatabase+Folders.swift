// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import Foundation
import GRDB

// Dossiers de l'accueil — PLAN-T5-001, étape E1 (plan approuvé par NOxygen59 le 10/11/2026).
//
// Décisions : un document dans **un seul** dossier (DEC-T5-01) ; dossiers propres à un espace, Manga ou
// Livres & Manuels (DEC-T5-02) ; un seul niveau (DEC-T5-03) ; dossier supprimé = ses documents reviennent dans leur
// section habituelle, rien n'est effacé (DEC-T5-05) ; le dossier ne voyage pas dans un paquet `.kyokasho`
// (DEC-T5-06, voir `DocumentPackage`) ; dossiers rangés par ordre alphabétique (DEC-T5-08).
//
// Invariant : l'appartenance vit dans la colonne `document.folderId` (clé étrangère `ON DELETE SET NULL`), lue et
// écrite **seulement** ici. `LibraryDocument` ne la porte pas : ses enregistrements ne peuvent pas l'effacer.
// La sauvegarde complète copie la base entière (dossiers compris) ; la corbeille ne touche pas la ligne du document,
// donc un document restauré retrouve son dossier.

/// Un dossier de l'accueil.
public struct LibraryFolder: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "folder"

    public var id: String
    public var name: String
    /// Espace de l'accueil : valeur brute de `LibrarySpace` côté app (dossiers séparés, DEC-T5-02).
    public var space: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, space: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.space = space
        self.createdAt = createdAt
    }
}

/// Les dossiers et qui est dedans, lus ensemble (une seule lecture cohérente).
public struct LibraryFolders: Equatable, Sendable {
    /// Par ordre alphabétique du nom (DEC-T5-08), puis date de création.
    public var folders: [LibraryFolder]
    /// Identifiant de document → identifiant de son dossier (documents rangés seulement).
    public var membership: [String: String]

    public init(folders: [LibraryFolder] = [], membership: [String: String] = [:]) {
        self.folders = folders
        self.membership = membership
    }

    public func folders(in space: String) -> [LibraryFolder] { folders.filter { $0.space == space } }
}

public enum FolderError: LocalizedError, Equatable {
    case emptyName, notFound, wrongSpace

    public var errorDescription: String? {
        switch self {
        case .emptyName: return String(localized: "Donne un nom au dossier.", bundle: .main)
        case .notFound: return String(localized: "Ce dossier n'existe plus.", bundle: .main)
        case .wrongSpace: return String(localized: "Ce dossier appartient à l'autre espace de l'accueil.", bundle: .main)
        }
    }
}

extension AppDatabase {
    public func createFolder(name: String, space: String) throws -> LibraryFolder {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw FolderError.emptyName }
        let folder = LibraryFolder(name: clean, space: space)
        try writer.write { db in try folder.insert(db) }
        return folder
    }

    public func renameFolder(id: String, to name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw FolderError.emptyName }
        try writer.write { db in
            try db.execute(sql: "UPDATE folder SET name = ? WHERE id = ?", arguments: [clean, id])
            guard db.changesCount == 1 else { throw FolderError.notFound }
        }
    }

    /// Supprime le dossier ; ses documents redeviennent « hors dossier » (DEC-T5-05). Aucun document n'est touché
    /// d'une autre façon. La remise à `NULL` est écrite explicitement, sans compter sur la clé étrangère seule.
    public func deleteFolder(id: String) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE document SET folderId = NULL WHERE folderId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM folder WHERE id = ?", arguments: [id])
        }
    }

    /// Range des documents dans un dossier, ou les sort de leur dossier (`folderId == nil`). Tout ou rien.
    /// `space` : espace des documents, vérifié contre celui du dossier (DEC-T5-02).
    public func moveDocuments(_ documentIds: [String], toFolder folderId: String?, space: String) throws {
        guard !documentIds.isEmpty else { return }
        try writer.write { db in
            if let folderId {
                guard let folder = try LibraryFolder.fetchOne(db, key: folderId) else { throw FolderError.notFound }
                guard folder.space == space else { throw FolderError.wrongSpace }
            }
            for id in documentIds {
                try db.execute(sql: "UPDATE document SET folderId = ? WHERE id = ?", arguments: [folderId, id])
            }
        }
    }

    public func libraryFolders() throws -> LibraryFolders {
        try writer.read { db in try Self.libraryFolders(db) }
    }

    /// Publie dossiers et appartenances à chaque changement de `folder` ou de `document` (l'accueil s'y abonne).
    public func foldersPublisher() -> AnyPublisher<LibraryFolders, Error> {
        ValueObservation
            .tracking { db in try Self.libraryFolders(db) }
            .removeDuplicates()
            .publisher(in: writer, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    static func libraryFolders(_ db: Database) throws -> LibraryFolders {
        let folders = try LibraryFolder.fetchAll(db).sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.createdAt < $1.createdAt : order == .orderedAscending
        }
        var membership: [String: String] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT id, folderId FROM document WHERE folderId IS NOT NULL") {
            membership[row[0]] = row[1]
        }
        return LibraryFolders(folders: folders, membership: membership)
    }
}
