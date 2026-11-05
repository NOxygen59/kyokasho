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
    /// Une ligne pour le choix du style.
    var summary = ""
    /// Palette proposée avec le style (identifiant d'un `Theme`) ; l'utilisateur peut la remplacer ensuite.
    var defaultTheme = "atelier"

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
    /// Fond des panneaux (`AtelierPanel`) : plein (d'origine) ou verre flouté (Glassmorphism, plus coûteux en GPU).
    enum PanelFill: Equatable { case solid, glass }
    var panelFill: PanelFill = .solid
    /// Bord des panneaux : trait fin (d'origine), encre pleine (Neo-Brutalism) ou néon de la couleur de lecture.
    enum PanelEdge: Equatable { case hairline, ink, glow, doubleLine }
    var panelEdge: PanelEdge = .hairline
    /// Silhouette des panneaux d'interface ; aucune incidence sur les pages et zones OCR.
    enum PanelShape: Equatable { case rounded, organic, chamfered }
    var panelShape: PanelShape {
        switch id {
        case "wabisabi": return .organic
        case "cyberpunk": return .chamfered
        default: return .rounded
        }
    }

    // MARK: Voile
    /// Voile derrière une fenêtre au premier plan (les encres claires ou foncées viennent de la palette, `Theme`).
    var scrim: Color = .black

    static let atelier = AppStyle(id: "atelier", name: String(localized: "Atelier"), summary: String(localized: "Panneaux flottants, arrondis doux"))

    // Premier lot de styles (S2, 29/10/2026) : cinq styles très différents pour éprouver les jetons.
    static let brutalism = AppStyle(id: "brutalism", name: "Neo-Brutalism", summary: String(localized: "Angles droits, traits épais, ombres dures"),
                                    defaultTheme: "brutal", cornerScale: 0, fontDesign: .monospaced,
                                    shadowKind: .hard(offset: 5), borderScale: 2.5, usesMaterials: false, panelEdge: .ink)
    static let glass = AppStyle(id: "glass", name: String(localized: "Glassmorphism"), summary: String(localized: "Verre flouté, formes arrondies"),
                                defaultTheme: "clair", cornerScale: 1.2, panelFill: .glass)
    static let synthwave = AppStyle(id: "synthwave", name: String(localized: "Synthwave"), summary: String(localized: "Nuit violette, bords néon"),
                                    defaultTheme: "synthwave", cornerScale: 0.5, fontDesign: .rounded,
                                    usesMaterials: false, panelEdge: .glow)
    static let swiss = AppStyle(id: "swiss", name: String(localized: "Swiss Design"), summary: String(localized: "Grille nette, angles droits, sans ombre"),
                                defaultTheme: "swiss", cornerScale: 0, shadowKind: .none, usesMaterials: false)
    static let wabiSabi = AppStyle(id: "wabisabi", name: "Wabi-Sabi", summary: String(localized: "Tons de terre, serif, formes douces"),
                                   defaultTheme: "terre", cornerScale: 1.35, fontDesign: .serif)

    // S3 à S5 : styles doux, typographiques, numériques et artisanaux. Ils réemploient les jetons éprouvés ; les
    // ornements dessinés et la disposition Bento restent des lots séparés afin de ne pas mêler apparence et structure.
    static let clay = AppStyle(id: "clay", name: String(localized: "Claymorphism"), summary: String(localized: "Volumes pastel, formes généreuses"),
                               defaultTheme: "clair", cornerScale: 1.6, fontDesign: .rounded,
                               borderScale: 0.7, usesMaterials: false)
    static let neumorphism = AppStyle(id: "neumorphism", name: String(localized: "Neumorphism"), summary: String(localized: "Relief doux, surfaces ton sur ton"),
                                      defaultTheme: "clair", cornerScale: 1.3, borderScale: 0.5, usesMaterials: false)
    static let ethereal = AppStyle(id: "ethereal", name: String(localized: "Ethereal"), summary: String(localized: "Verre léger, courbes aériennes"),
                                   defaultTheme: "sakura", cornerScale: 1.5, fontDesign: .serif,
                                   borderScale: 0.6, panelFill: .glass)
    static let minimalism = AppStyle(id: "minimalism", name: String(localized: "Minimalism"), summary: String(localized: "Formes sobres, aucun relief superflu"),
                                     defaultTheme: "clair", cornerScale: 0.6, shadowKind: .none,
                                     borderScale: 0.6, usesMaterials: false)

    static let editorial = AppStyle(id: "editorial", name: String(localized: "Editorial Design"), summary: String(localized: "Hiérarchie nette, serif éditoriale"),
                                    defaultTheme: "clair", cornerScale: 0.2, fontDesign: .serif,
                                    shadowKind: .none, borderScale: 0.7, usesMaterials: false)
    static let luxury = AppStyle(id: "luxury", name: String(localized: "Luxury Typography"), summary: String(localized: "Encre et or, typographie élégante"),
                                 defaultTheme: "encre", cornerScale: 0.3, fontDesign: .serif,
                                 shadowKind: .none, borderScale: 1.2, usesMaterials: false, panelEdge: .doubleLine)
    static let victorian = AppStyle(id: "victorian", name: String(localized: "Victorian"), summary: String(localized: "Sépia, cadres d'encre, serif classique"),
                                    defaultTheme: "sepia", cornerScale: 0.2, fontDesign: .serif,
                                    borderScale: 1.5, usesMaterials: false, panelEdge: .ink)
    static let maximalism = AppStyle(id: "maximalism", name: String(localized: "Maximalism"), summary: String(localized: "Couleurs fortes, relief et bord lumineux"),
                                     defaultTheme: "braise", cornerScale: 1.2, fontDesign: .rounded,
                                     borderScale: 2, usesMaterials: false, panelEdge: .glow)

    static let cybercore = AppStyle(id: "cybercore", name: String(localized: "Cybercore"), summary: String(localized: "Terminal sombre, lignes techniques"),
                                    defaultTheme: "foret", cornerScale: 0.3, fontDesign: .monospaced,
                                    borderScale: 1.4, usesMaterials: false, panelEdge: .glow)
    static let cyberpunk = AppStyle(id: "cyberpunk", name: String(localized: "Cyberpunk"), summary: String(localized: "Angles vifs, néon et ombres franches"),
                                    defaultTheme: "lagon", cornerScale: 0.2, fontDesign: .monospaced,
                                    shadowKind: .hard(offset: 4), borderScale: 1.7, usesMaterials: false, panelEdge: .glow)
    static let y2k = AppStyle(id: "y2k", name: String(localized: "Y2K Aesthetic"), summary: String(localized: "Bulles chromées, verre et couleur"),
                             defaultTheme: "lagon", cornerScale: 1.4, fontDesign: .rounded,
                             borderScale: 1.2, panelFill: .glass, panelEdge: .glow)
    static let pixel = AppStyle(id: "pixel", name: String(localized: "Pixel Art"), summary: String(localized: "Angles carrés, grille et ombres décalées"),
                               defaultTheme: "foret", cornerScale: 0, fontDesign: .monospaced,
                               shadowKind: .hard(offset: 4), borderScale: 2, usesMaterials: false, panelEdge: .ink)

    static let scrapbook = AppStyle(id: "scrapbook", name: String(localized: "Scrapbook"), summary: String(localized: "Papier découpé, couches et contraste"),
                                    defaultTheme: "sepia", cornerScale: 0.6, fontDesign: .serif,
                                    shadowKind: .hard(offset: 3), borderScale: 1.5, usesMaterials: false)
    static let sketch = AppStyle(id: "sketch", name: String(localized: "Conceptual Sketch"), summary: String(localized: "Trait d'étude, papier clair, chasse fixe"),
                                defaultTheme: "clair", cornerScale: 0.4, fontDesign: .monospaced,
                                shadowKind: .none, borderScale: 1.5, usesMaterials: false, panelEdge: .ink)
    static let bohemian = AppStyle(id: "bohemian", name: String(localized: "Bohemian"), summary: String(localized: "Terre chaude, serif et formes libres"),
                                   defaultTheme: "terre", cornerScale: 1.2, fontDesign: .serif,
                                   shadowKind: .hard(offset: 2), borderScale: 0.8, usesMaterials: false)
    static let surrealism = AppStyle(id: "surrealism", name: String(localized: "Surrealism"), summary: String(localized: "Courbes oniriques et profondeur vitrée"),
                                     defaultTheme: "soir", cornerScale: 1.5, fontDesign: .serif,
                                     borderScale: 0.8, panelFill: .glass)
    static let bento = AppStyle(id: "bento", name: String(localized: "Bento Grid"), summary: String(localized: "Tuiles claires et panneaux compacts"),
                               defaultTheme: "clair", cornerScale: 1.1, shadowKind: .none,
                               borderScale: 0.8, usesMaterials: false)

    static let all: [AppStyle] = [
        .atelier, .brutalism, .glass, .synthwave, .swiss, .wabiSabi,
        .clay, .neumorphism, .ethereal, .minimalism,
        .editorial, .luxury, .victorian, .maximalism,
        .cybercore, .cyberpunk, .y2k, .pixel,
        .scrapbook, .sketch, .bohemian, .surrealism, .bento,
    ]

    /// Huit univers principaux. `all` conserve les anciens identifiants pour relire les choix déjà enregistrés.
    /// Retirer un doublon du sélecteur ne réécrit jamais les préférences existantes.
    static let featured: [AppStyle] = [.atelier, .wabiSabi, .swiss, .brutalism, .glass, .synthwave, .cyberpunk, .luxury]

    /// Signature du style dans les aperçus ; indépendante du symbole de sa palette.
    var symbol: String {
        switch id {
        case "glass": return "square.on.square"
        case "clay": return "square.3.layers.3d"
        case "neumorphism": return "circle.inset.filled"
        case "ethereal": return "sparkles"
        case "minimalism": return "minus"
        case "editorial": return "text.alignleft"
        case "luxury": return "diamond"
        case "victorian": return "seal"
        case "maximalism": return "circle.hexagongrid.fill"
        case "cybercore": return "cpu"
        case "cyberpunk": return "bolt.fill"
        case "y2k": return "sparkle"
        case "pixel": return "square.grid.3x3.fill"
        case "scrapbook": return "scissors"
        case "sketch": return "pencil.tip"
        case "bohemian": return "sun.max"
        case "surrealism": return "moon.stars"
        case "bento": return "rectangle.grid.2x2"
        default: return Theme.all.first { $0.id == defaultTheme }?.symbol ?? "circle"
        }
    }

    /// Style en cours (lu par `Atelier`). Changé par `ThemeManager`.
    static var current: AppStyle = .atelier
}
