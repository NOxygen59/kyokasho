// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Onglets des documents ouverts, en haut du lecteur (RET-013, #16) : passer d'un livre à l'autre sans revenir à la
/// bibliothèque. Seul le document affiché est chargé ; les autres se rouvrent à leur page.
public struct DocumentTabs: Equatable, Sendable {
    /// À partir de ce nombre d'onglets, une bulle conseille de surveiller la mémoire (décision de NOxygen59, 28/10).
    public static let warningCount = 4

    public private(set) var ids: [String] = []

    public init(ids: [String] = []) { self.ids = ids }

    public var showsMemoryWarning: Bool { ids.count >= Self.warningCount }

    /// Ouvre (ou retrouve) l'onglet du document, ajouté à la fin.
    public mutating func open(_ id: String) {
        if !ids.contains(id) { ids.append(id) }
    }

    /// Ferme l'onglet `id` et renvoie le document à afficher ensuite : le courant s'il reste ouvert, sinon l'onglet
    /// voisin (celui de droite, sinon de gauche), `nil` quand il n'en reste aucun (retour à la bibliothèque).
    public mutating func close(_ id: String, current: String?) -> String? {
        guard let i = ids.firstIndex(of: id) else { return current }
        ids.remove(at: i)
        guard current == id else { return current }
        if ids.isEmpty { return nil }
        return ids[min(i, ids.count - 1)]
    }

    /// Documents supprimés de la bibliothèque : leurs onglets partent.
    public mutating func keep(only existing: Set<String>) {
        ids.removeAll { !existing.contains($0) }
    }
}
