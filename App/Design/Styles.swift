// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Style de l'app (chantier des styles, S1) : forme, typographie, relief, bordure, voile. Les couleurs, y compris
/// clair ou sombre, viennent de la palette (`Theme`, variantes nuit, clair, sépia). Il se combine avec une palette (`Theme`) : décision de NOxygen59 du 29/10/2026.
/// Le style habille toute l'app, lecteur compris, jamais les pages du manuel (PDF, papier, encre des notes, exports).
///
/// S1 : un seul style, « Atelier », dont chaque valeur reprend exactement l'ancienne valeur écrite en dur.
/// Ajouter un style ne doit donc rien changer aux autres ; les 22 styles demandés viennent aux étapes S2 et suivantes.
struct AppStyle: Identifiable, Equatable {
    let id: String
    let name: String
    // MARK: Forme
    /// Facteur appliqué à tous les arrondis de l'interface (`Atelier.corner`) : 1 = arrondis d'origine, 0 = angles
    /// droits (styles Swiss, Neo-Brutalism…), plus de 1 = formes gonflées (Claymorphism).
    var cornerScale: CGFloat = 1

    // MARK: Typographie
    /// Famille du texte latin de l'interface (`Atelier.font`, et les styles de texte iOS à partir d'iOS 16.1).
    var fontDesign: Font.Design = .default

    // MARK: Relief et bordure
    /// Ombres portées : douces (valeurs d'origine), dures et décalées (Neo-Brutalism), ou aucune (Swiss, Minimalism).
    enum ShadowKind: Equatable { case soft, hard(offset: CGFloat), none }
    var shadowKind: ShadowKind = .soft
    /// Facteur des épaisseurs de bordure de l'interface (`Atelier.border`) : 1 = d'origine.
    var borderScale: CGFloat = 1
    /// Matières floutées d'iOS (pilules, fenêtres d'avertissement). `false` : fond plein du panneau à la place.
    var usesMaterials = true

    // MARK: Voile
    /// Voile derrière une fenêtre au premier plan (les encres claires ou foncées viennent de la palette, `Theme`).
    var scrim: Color = .black

    static let atelier = AppStyle(id: "atelier", name: "Atelier")

    static let all: [AppStyle] = [.atelier]

    /// Style en cours (lu par `Atelier`). Changé par `ThemeManager`.
    static var current: AppStyle = .atelier
}
