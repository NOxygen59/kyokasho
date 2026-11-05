// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Règles qui décident si les barres du lecteur s'affichent ou se cachent, sans UIKit pour être testées sur Mac.
///
/// Invariant (recette iPad 1.4.7) : aucune situation ne doit laisser les barres cachées sans moyen de les rappeler.
public enum ReaderBarsPolicy {
    /// Durée pendant laquelle un changement de page suivant un affichage des barres n'est pas un geste de lecture.
    ///
    /// Montrer ou cacher les barres fait apparaître ou disparaître la barre d'état : la zone sûre change, donc la vue PDF
    /// est redimensionnée et PDFKit peut annoncer un changement de page. Sans ce délai, ce faux changement recachait
    /// les barres qu'un toucher venait de montrer.
    public static let settleDelay: TimeInterval = 0.8

    /// Un changement de page doit-il cacher les barres (« Masquer les barres en tournant les pages ») ?
    public static func hidesOnPageChange(pageChanged: Bool, rebuilding: Bool, hideOnTurn: Bool, barsVisible: Bool,
                                         secondsSinceBarsChanged: TimeInterval) -> Bool {
        pageChanged && !rebuilding && hideOnTurn && barsVisible && secondsSinceBarsChanged >= settleDelay
    }

    /// La sélection de PDFKit contient-elle du texte visible ? Sinon, le toucher ne sert pas à l'effacer.
    public static func isVisibleSelection(_ text: String?) -> Bool {
        guard let text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Mode dictionnaire : un toucher sans mot (marge, image, blanc) montre ou cache les barres, comme hors de ce mode.
    /// Une fenêtre déjà ouverte reste la priorité : ce toucher ne doit pas, en plus, changer les barres. `isStale` : un geste
    /// plus récent (toucher, page, flèche, mode) est arrivé pendant l'attente de l'OCR, et décide à sa place.
    public static func togglesAfterLookup(isStale: Bool = false, popupWasOpen: Bool, popupIsOpen: Bool) -> Bool {
        !isStale && !popupWasOpen && !popupIsOpen
    }
}
