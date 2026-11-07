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

        public init(category: DocumentCategory?, title: String, documents: [LibraryDocument]) {
            self.category = category
            self.title = title
            self.documents = documents
        }
    }

    public static let order: [DocumentCategory?] = [.textbook, .book, nil]

    public static func group(_ documents: [LibraryDocument]) -> [Section] {
        order.compactMap { category in
            let docs = documents.filter { $0.category == category }
            guard !docs.isEmpty else { return nil }
            return Section(category: category, title: title(category), documents: docs)
        }
    }

    /// Espace Manga, comme Livres et Manuels (demande de NOxygen59, 07/11/2026) : « Manga » (PDF, avec OCR et étude)
    /// puis « CBZ » (lecture visuelle). Une section vide n'apparaît pas ; l'ordre des documents est gardé.
    public static func groupManga(_ documents: [LibraryDocument]) -> [Section] {
        let pdf = documents.filter { !$0.isComicArchive }, comics = documents.filter(\.isComicArchive)
        return [(String(localized: "Manga", bundle: .main), pdf), ("CBZ", comics)].compactMap { title, docs in
            docs.isEmpty ? nil : Section(category: nil, title: title, documents: docs)
        }
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
    public var manga: Bool

    public init(documentId: String, category: DocumentCategory?, selecting: Bool, manga: Bool = false) {
        self.documentId = documentId
        self.category = category
        self.selecting = selecting
        self.manga = manga
    }
}
