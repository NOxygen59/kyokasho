// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Accueil en sections par catégorie (recette 1.3.2 (61), E5 ; suite de RET-039, #54) : « Manuels » en haut,
/// « Livres » en dessous, puis « Non classés ». Chaque section s'allonge avec ses documents ; une section vide
/// n'apparaît pas. L'ordre des documents (dernier ouvert en premier) est gardé dans chaque section.
public enum LibrarySections {
    public struct Section: Equatable, Sendable {
        public var category: DocumentCategory?
        public var title: String
        public var documents: [LibraryDocument]
        public var isComics = false
    }

    /// Clé des PDF rangés à la main dans « Comics ». Simple classement, hors de la colonne `category` : une version plus
    /// ancienne de l'app ne sait pas lire une catégorie inconnue, et toute sa bibliothèque paraîtrait vide.
    public static let comicMarksKey = "comics.marked"

    public static func isComics(_ document: LibraryDocument, marks: Set<String>) -> Bool {
        document.isComicArchive || marks.contains(document.id)
    }

    public static let order: [DocumentCategory?] = [.textbook, .book, nil]

    public static func group(_ documents: [LibraryDocument], comicMarks: Set<String> = []) -> [Section] {
        let comics = documents.filter { isComics($0, marks: comicMarks) }
        let others = documents.filter { !isComics($0, marks: comicMarks) }
        var sections: [Section] = order.compactMap { category in
            let docs = others.filter { $0.category == category }
            guard !docs.isEmpty else { return nil }
            return Section(category: category, title: title(category), documents: docs)
        }
        if !comics.isEmpty {
            // Avant « Non classés », toujours en dernier.
            let index = sections.last?.category == nil && !sections.isEmpty ? sections.count - 1 : sections.count
            sections.insert(Section(category: nil, title: String(localized: "Comics", bundle: .main), documents: comics, isComics: true), at: index)
        }
        return sections
    }

    public static func title(_ category: DocumentCategory?) -> String {
        switch category {
        case .textbook: return String(localized: "Manuels", bundle: .main)
        case .book: return String(localized: "Livres", bundle: .main)
        case nil: return String(localized: "Non classés", bundle: .main)
        }
    }
}

/// Force SwiftUI à reconstruire une carte quand elle change de section ou quand le mode sélection apparaît.
public struct LibraryCardRenderIdentity: Hashable, Sendable {
    public var documentId: String
    public var category: DocumentCategory?
    public var selecting: Bool
    public var comics: Bool

    public init(documentId: String, category: DocumentCategory?, selecting: Bool, comics: Bool = false) {
        self.documentId = documentId
        self.category = category
        self.selecting = selecting
        self.comics = comics
    }
}
