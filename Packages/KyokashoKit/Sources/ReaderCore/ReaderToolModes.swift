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
    /// Position du panneau d'étude dans ce livre (valeur brute de `StudyPanelMode` côté app : `docked`, `floating`,
    /// `full`) ; `nil` : réglage général (recette 1.3.2 (61), M2). Facultatif pour relire les modes enregistrés
    /// avant ce champ.
    public var panelMode: String?

    public init(drawing: Bool = false, lookup: Bool = false, pencilLookup: Bool = false, panelMode: String? = nil) {
        self.drawing = drawing
        self.lookup = lookup
        self.pencilLookup = pencilLookup
        self.panelMode = panelMode
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

/// Retour terrain T1 du 10/11/2026 : en page seule avec transition « Glissement », PDFKit passe par un contrôleur de
/// pages dont le défilement interne prenait l'Apple Pencil comme un doigt : écrire faisait tourner la page.
/// Pendant le dessin dans ce mode, les défilements de PDFKit refusent le Pencil ; le doigt et le trackpad gardent le
/// tour de page. Valeurs brutes de `UITouch.TouchType` (direct 0, indirect 1, pencil 2, indirectPointer 3) pour rester
/// testable sans UIKit.
public enum PencilPageTurnGuard {
    public static let pencil = 2
    /// Types de toucher par défaut d'un geste UIKit.
    public static let allTouchTypes = [0, 1, 2, 3]
    /// Tout sauf le Pencil.
    public static let withoutPencil = [0, 1, 3]

    /// Le Pencil doit-il être refusé par les défilements de PDFKit ?
    public static func blocksPencil(drawing: Bool, pageController: Bool) -> Bool {
        drawing && pageController
    }

    /// Types de toucher à donner au glisser d'un défilement de PDFKit, ou `nil` pour n'y rien changer.
    /// Seule une valeur posée par cette garde (`withoutPencil`) est rétablie : un réglage venu d'ailleurs reste intact.
    public static func touchTypes(current: [Int], drawing: Bool, pageController: Bool) -> [Int]? {
        if blocksPencil(drawing: drawing, pageController: pageController) {
            return current.contains(pencil) ? current.filter { $0 != pencil } : nil
        }
        return Set(current) == Set(withoutPencil) ? allTouchTypes : nil
    }
}
