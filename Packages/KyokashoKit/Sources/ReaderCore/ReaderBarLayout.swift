// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Variantes des barres du lecteur (nouvelle présentation) choisies d'après la largeur de la fenêtre
/// (PLAN-FENETRES-001 : Split View, fenêtre libre). Le choix se fait au calcul, jamais par `ViewThatFits` : sous
/// iOS 16, les variantes écartées gardaient le lecteur fermé en vie (recette 1.6.4, point 13).
///
/// Largeurs en points, mesurées au simulateur le 25/11/2026 (arbre AXe) : bouton Bibliothèque 52, pastille d'onglet
/// 44 + 8 d'espace, onglet titré au moins 232 (titre raccourci à 120), capsule d'actions 269 avec « Étudier » en icône,
/// 169 sans Rechercher ni Signet. Plancher : 343 pt (Bibliothèque, livre, « +N », capsule resserrée) ; Split View ⅓ = 347.
public enum ReaderBarLayout {
    /// Sous cette largeur, le panneau d'étude flottant s'arrête au-dessus de la barre du bas, qui garde toute la
    /// largeur, au lieu de la couper à son bord (AV-FENETRES-001, option A). Avant : à 678 pt (Split View ½) il ne
    /// restait que 216 pt à la barre, dont la partie fixe en demande ≈ 385 ; tout le chrome débordait.
    public static let narrowWindow: CGFloat = 760

    /// Sous cette largeur de barre du bas, « Page vers IA » et « Navigateur à côté » passent dans le menu « … »
    /// (DEC-03 A) : la partie fixe tombe de ≈ 397 à ≈ 273 pt et laisse de la place aux outils défilants.
    public static let aiAndWebInMenuBelow: CGFloat = 600

    /// Fenêtre minimale pour proposer le navigateur à côté : sa colonne (440) et ses marges (3 × 14) doivent laisser
    /// au lecteur la largeur plancher de la barre du haut (343 + 2 × 14). En dessous, le bouton disparaît et un
    /// navigateur ouvert se ferme.
    public static let webPanelMinWindow: CGFloat = 440 + 42 + 371

    /// Disposition de la barre du haut.
    public struct Top: Equatable {
        /// Onglets montrés en tête (le livre affiché en fait toujours partie) ; les autres vont dans « +N ».
        public var visibleTabs: Int
        /// Livre affiché avec son titre (raccourci au besoin, jamais vide) ; sinon en pastille (DEC-01 A).
        public var currentTitle: Bool
        /// Bouton « + » (ouvrir un autre livre en onglet).
        public var newTabButton: Bool
        /// Rechercher et Signet rangés dans « … » (DEC-02 A) ; barre resserrée (espaces réduits).
        public var slim: Bool

        public init(visibleTabs: Int, currentTitle: Bool, newTabButton: Bool, slim: Bool) {
            self.visibleTabs = visibleTabs
            self.currentTitle = currentTitle
            self.newTabButton = newTabButton
            self.slim = slim
        }
    }

    static let pill: CGFloat = 52, titled: CGFloat = 232, capsule: CGFloat = 269, slimCapsule: CGFloat = 169
    /// Bibliothèque, espaces de la barre (3 × 10, ou 3 × 6 resserrée) et espace minimal avant la capsule.
    static let fixed: CGFloat = 90, slimFixed: CGFloat = 70

    /// - Parameters:
    ///   - width: largeur offerte à la barre du haut, marges ôtées.
    ///   - openTabs: livres ouverts en onglets, livre affiché compris.
    ///   - pillsOnlyFrom: à partir de ce nombre d'onglets, le livre affiché reste en pastille même s'il y a la place.
    public static func top(width: CGFloat, openTabs: Int, pillsOnlyFrom: Int, maxTabs: Int = 6) -> Top {
        let tabs = max(openTabs, 1)
        // Resserrée quand même la version à 3 pastilles (livre, « +N », « + ») ne tient pas avec la capsule complète.
        let slim = width < fixed + pill * 3 + capsule
        let base = slim ? slimFixed + slimCapsule : fixed + capsule
        let plus: CGFloat = slim ? 0 : pill
        // Une place est gardée pour « +N » dès qu'il reste des livres à ranger.
        let room = Int((width - base - plus - pill) / pill)
        let visible = min(maxTabs, max(1, tabs <= room + 1 ? tabs : room))
        let more: CGFloat = tabs > visible ? pill : 0
        let titledNeeds = base + plus + more + titled + CGFloat(visible - 1) * pill
        let title = tabs < pillsOnlyFrom && width >= titledNeeds
        return Top(visibleTabs: visible, currentTitle: title, newTabButton: !slim, slim: slim)
    }
}
