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
    }

    public static let order: [DocumentCategory?] = [.textbook, .book, nil]

    public static func group(_ documents: [LibraryDocument]) -> [Section] {
        order.compactMap { category in
            let docs = documents.filter { $0.category == category }
            guard !docs.isEmpty else { return nil }
            return Section(category: category, title: title(category), documents: docs)
        }
    }

    public static func title(_ category: DocumentCategory?) -> String {
        switch category {
        case .textbook: return "Manuels"
        case .book: return "Livres"
        case nil: return "Non classés"
        }
    }
}
