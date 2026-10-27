// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Modes d'outil du lecteur, propres à **un** document (Issue #15, recette 1.3.1) : chaque livre retrouve
/// les siens à la réouverture et après redémarrage, sans changer ceux des autres livres.
/// Le survol au curseur reste un réglage global, comme avant.
public struct ReaderToolModes: Codable, Equatable, Sendable {
    /// Mode écriture au Pencil (PencilKit).
    public var drawing = false
    /// Dictionnaire au toucher (bouton 辞).
    public var lookup = false
    /// Le Pencil cherche le mot touché au lieu de dessiner.
    public var pencilLookup = false

    public init(drawing: Bool = false, lookup: Bool = false, pencilLookup: Bool = false) {
        self.drawing = drawing
        self.lookup = lookup
        self.pencilLookup = pencilLookup
    }
}

/// Lecture et écriture des modes par document dans `UserDefaults` (clé `reader.modes.<documentId>`).
/// Valeur absente ou illisible : tous les modes désactivés.
public struct ReaderToolModeStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public static func key(documentId: String) -> String { "reader.modes." + documentId }

    public func modes(documentId: String) -> ReaderToolModes {
        guard let data = defaults.data(forKey: Self.key(documentId: documentId)),
              let modes = try? JSONDecoder().decode(ReaderToolModes.self, from: data) else { return ReaderToolModes() }
        return modes
    }

    /// Modifie un ou plusieurs modes d'un document ; rien n'est écrit si la valeur ne change pas.
    public func update(documentId: String, _ change: (inout ReaderToolModes) -> Void) {
        var modes = self.modes(documentId: documentId)
        let before = modes
        change(&modes)
        guard modes != before, let data = try? JSONEncoder().encode(modes) else { return }
        defaults.set(data, forKey: Self.key(documentId: documentId))
    }

    /// Document supprimé de la bibliothèque : ses modes sont oubliés.
    public func forget(documentId: String) {
        defaults.removeObject(forKey: Self.key(documentId: documentId))
    }
}
