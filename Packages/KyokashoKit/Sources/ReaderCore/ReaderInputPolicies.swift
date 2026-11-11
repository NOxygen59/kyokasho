// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

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

/// Retour terrain T3 du 10/11/2026 : fenêtres secondaires du navigateur intégré.
/// Une fenêtre ouverte par le script de la page (`window.open`, connexion Google) ou avec une taille demandée devient
/// une vraie fenêtre fille, pour garder son lien avec la page d'origine ; un simple lien `target="_blank"` cliqué
/// reste ouvert dans la même vue.
public enum WebPopupPolicy {
    public static func opensRealWindow(linkActivated: Bool, hasSize: Bool) -> Bool {
        !linkActivated || hasSize
    }
}

/// Barre d'adresse du navigateur intégré : texte tapé → adresse, ou recherche Brave (demande de NOxygen59 du
/// 10/11/2026, à la place de DuckDuckGo).
public enum WebAddress {
    public static let searchEngine = "https://search.brave.com/search"

    public static func url(for text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://"), let url = URL(string: text) { return url }
        if !text.contains(" "), text.contains("."), let url = URL(string: "https://" + text) { return url }
        var parts = URLComponents(string: searchEngine)!
        parts.queryItems = [URLQueryItem(name: "q", value: text)]
        return parts.url
    }
}
