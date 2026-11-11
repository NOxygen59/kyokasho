// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Accueil avec dossiers — PLAN-T5-001, étape E2 (plan approuvé par NOxygen59 le 10/11/2026, décisions « tout A »).
///
/// Décision pure, testée sur Mac : l'écran (`LibraryView`) ne fait qu'afficher ce calcul.
/// - Les dossiers de l'espace affiché viennent **en tête**, par ordre alphabétique (ordre déjà donné par la base,
///   DEC-T5-08) ; les documents hors dossier gardent leurs sections habituelles en dessous.
/// - Un dossier vide reste visible pour pouvoir le remplir (DEC-T5-07)…
/// - … sauf pendant un filtre ou une recherche : un dossier ne montre que ses documents qui passent le filtre, et un
///   dossier sans document filtré est masqué (DEC-T5-09).
/// - Défense : une appartenance vers un dossier de l'autre espace ou inconnu est ignorée ; le document reste visible
///   dans sa section habituelle (jamais caché dans un dossier qu'on ne peut pas ouvrir).
public enum LibraryFolderLayout {
    public struct Tile: Equatable, Sendable, Identifiable {
        public var id: String { folder.id }
        public var folder: LibraryFolder
        /// Documents du dossier qui passent le filtre, dans l'ordre reçu (dernier ouvert en premier).
        public var documents: [LibraryDocument]

        public init(folder: LibraryFolder, documents: [LibraryDocument]) {
            self.folder = folder
            self.documents = documents
        }
    }

    public struct Result: Equatable, Sendable {
        public var tiles: [Tile]
        /// Documents hors dossier, à grouper en sections comme avant.
        public var loose: [LibraryDocument]
    }

    /// - Parameters:
    ///   - documents: documents de l'espace affiché, déjà filtrés (filtre et recherche).
    ///   - folders: dossiers de la base (tous espaces) et appartenances.
    ///   - space: espace affiché.
    ///   - filtering: un filtre autre que « Tous » ou une recherche est actif.
    public static func layout(documents: [LibraryDocument], folders: LibraryFolders, space: LibrarySpace,
                              filtering: Bool) -> Result {
        let shown = folders.folders(in: space.rawValue)
        let known = Set(shown.map(\.id))
        var byFolder: [String: [LibraryDocument]] = [:]
        var loose: [LibraryDocument] = []
        for document in documents {
            if let folderId = folders.membership[document.id], known.contains(folderId) {
                byFolder[folderId, default: []].append(document)
            } else {
                loose.append(document)
            }
        }
        let tiles = shown.compactMap { folder -> Tile? in
            let documents = byFolder[folder.id] ?? []
            if filtering && documents.isEmpty { return nil }
            return Tile(folder: folder, documents: documents)
        }
        return Result(tiles: tiles, loose: loose)
    }

    /// Espace commun d'une sélection de documents à ranger, ou `nil` si elle mélange les deux espaces (refusé :
    /// un dossier appartient à un seul espace).
    public static func commonSpace(of documents: [LibraryDocument]) -> LibrarySpace? {
        let spaces = Set(documents.map(LibrarySpace.init(document:)))
        return spaces.count == 1 ? spaces.first : nil
    }
}
