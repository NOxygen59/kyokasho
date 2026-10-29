// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Style de l'app (chantier des styles, S1) : tout ce qui n'est pas une couleur de fonction. Forme, relief, encres
/// hors palette, clair ou sombre. Il se combine avec une palette (`Theme`) : décision de NOxygen59 du 29/10/2026.
/// Le style habille toute l'app, lecteur compris, jamais les pages du manuel (PDF, papier, encre des notes, exports).
///
/// S1 : un seul style, « Atelier », dont chaque valeur reprend exactement l'ancienne valeur écrite en dur.
/// Ajouter un style ne doit donc rien changer aux autres ; les 22 styles demandés viennent aux étapes S2 et suivantes.
struct AppStyle: Identifiable, Equatable {
    let id: String
    let name: String
    /// Fonds clairs : l'interface passe en mode clair d'iOS (menus, alertes, clavier).
    var isLight = false

    // MARK: Forme
    /// Facteur appliqué à tous les arrondis de l'interface (`Atelier.corner`) : 1 = arrondis d'origine, 0 = angles
    /// droits (styles Swiss, Neo-Brutalism…), plus de 1 = formes gonflées (Claymorphism).
    var cornerScale: CGFloat = 1

    // MARK: Encres hors palette (valeur de base ; chaque usage garde son opacité)
    /// Texte ou icône posé sur une couleur de fonction pleine (bouton actif, pastille).
    var onAccentInk: Color = .black
    /// Ombre portée des panneaux et fenêtres.
    var shadow: Color = .black
    /// Voile derrière une fenêtre au premier plan.
    var scrim: Color = .black
    /// Contraste maximal sur le fond de l'interface (icône du stylo noir, contour d'une pastille, texte trouvé).
    var contrastInk: Color = .white

    static let atelier = AppStyle(id: "atelier", name: "Atelier")

    static let all: [AppStyle] = [.atelier]

    /// Style en cours (lu par `Atelier`). Changé par `ThemeManager`.
    static var current: AppStyle = .atelier

    var colorScheme: ColorScheme { isLight ? .light : .dark }
}
