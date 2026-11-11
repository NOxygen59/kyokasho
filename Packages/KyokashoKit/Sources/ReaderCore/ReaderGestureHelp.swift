// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Aide aux gestes du lecteur (FEAT-AIDE, demande de NOxygen59 du 11/11/2026) : la liste de ce que le doigt peut faire
/// sur la page, affichée par `ReaderGestureHelpSheet` depuis le menu « … » du lecteur.
///
/// Contenu sans SwiftUI pour être testé sur Mac. **Chaque ligne décrit un geste réellement branché** ; sa référence
/// dans le code est notée ici. Qui modifie un geste du lecteur met cette liste à jour, sinon l'aide ment :
/// - tourner la page : `ReaderController.handleSwipe` (glisser, sens selon le sens de lecture), flèches ‹ › de la
///   barre (`ReaderScreen.pageArrow`), touches ← → (`ReaderArrowKeys`) ; en défilement continu, PDFKit fait défiler ;
/// - barres : `ReaderController.handleTap` (dernier cas : `barsVisible.toggle()`), flèche `ReaderScreen.restoreBarsButton` ;
/// - zoom : `ReaderController.handleDoubleTap` (réglage `doubleTapZoom`), pincement de PDFKit ; page agrandie, le
///   glisser ne tourne plus la page (`handleSwipe`, garde d'échelle) ;
/// - sélection : `ReaderController.handleLongPress` (mot, puis extension en glissant) ; un toucher l'efface (`handleTap`) ;
/// - dictionnaire : bouton 辞 (`lookupMode`) puis toucher (`handleTap`) ; Maj + survol au curseur (`handleHover`) ;
/// - surligneur : `ReaderController.handleHighlightPan` (bouton surligneur, appui long sur le bouton : couleur) ;
///   toucher un surlignage ouvre « Copier le texte / Supprimer » (`handleTap`, `ReaderScreen`) ;
/// - dessin : bouton crayon (`ReaderController.setDrawing`), toile PencilKit (`InkPageView`, fichier `InkOverlay.swift`).
///
/// Rien n'est enregistré : la liste est recalculée à chaque ouverture d'après le document et ses réglages.
public enum ReaderGestureHelp {
    public struct Item: Identifiable, Equatable, Sendable {
        public enum Kind: String, Sendable, CaseIterable {
            case turnPage, bars, zoom, selectText, lookup, highlight, draw
        }

        public let kind: Kind
        /// Symbole SF (tous disponibles sous iOS 16).
        public let icon: String
        public let title: String
        public let detail: String
        public var id: String { kind.rawValue }
    }

    /// Ce dont dépend la liste : format du document et réglages d'affichage du lecteur.
    public struct Context: Equatable, Sendable {
        /// OCR, sélection et dictionnaire (faux pour une archive CBZ).
        public var textAnalysis: Bool
        /// Barre d'outils de dessin et de surlignage (faux pour une archive CBZ).
        public var annotations: Bool
        /// Défilement continu : la page défile, elle ne se tourne pas.
        public var continuousScroll: Bool
        /// Lecture de droite à gauche : le glisser est inversé.
        public var rightToLeft: Bool
        /// Réglage « double toucher pour zoomer ».
        public var doubleTapZoom: Bool

        public init(textAnalysis: Bool, annotations: Bool, continuousScroll: Bool, rightToLeft: Bool, doubleTapZoom: Bool) {
            self.textAnalysis = textAnalysis
            self.annotations = annotations
            self.continuousScroll = continuousScroll
            self.rightToLeft = rightToLeft
            self.doubleTapZoom = doubleTapZoom
        }
    }

    /// Lignes à afficher, dans l'ordre : d'abord ce qui sert à lire, puis le texte, puis les outils.
    /// Entre 3 (archive CBZ) et 7 lignes : jamais un geste que ce document ne propose pas.
    public static func items(_ context: Context) -> [Item] {
        var items: [Item] = [turnPage(context),
                             Item(kind: .bars, icon: "hand.tap",
                                  title: String(localized: "Afficher ou cacher les barres", bundle: .main),
                                  detail: String(localized: "Touche la page une fois. Barres cachées, la petite flèche en haut de l'écran les ramène aussi.", bundle: .main)),
                             zoom(context)]
        if context.textAnalysis {
            items.append(Item(kind: .selectText, icon: "text.cursor",
                              title: String(localized: "Sélectionner du texte", bundle: .main),
                              detail: String(localized: "Sur une page qui contient du texte, appuie longuement sur un mot, puis glisse sans lever le doigt pour étendre la sélection. Un toucher ailleurs l'efface.", bundle: .main)))
            items.append(Item(kind: .lookup, icon: "character.book.closed",
                              title: String(localized: "Chercher un mot dans le dictionnaire", bundle: .main),
                              detail: String(localized: "Active 辞 dans la barre d'outils, puis touche un mot de la page. Avec une souris ou un trackpad, tiens Maj et passe le curseur sur le mot.", bundle: .main)))
        }
        if context.textAnalysis && context.annotations {
            items.append(Item(kind: .highlight, icon: "highlighter",
                              title: String(localized: "Surligner", bundle: .main),
                              detail: String(localized: "Active le surligneur dans la barre d'outils, puis glisse sur le texte. Un appui long sur ce bouton change la couleur ; toucher un surlignage permet de le copier ou de le supprimer.", bundle: .main)))
        }
        if context.annotations {
            items.append(Item(kind: .draw, icon: "pencil.tip",
                              title: String(localized: "Écrire sur la page", bundle: .main),
                              detail: String(localized: "Active le crayon dans la barre d'outils pour dessiner avec l'Apple Pencil. Le bouton main revient à la lecture.", bundle: .main)))
        }
        return items
    }

    private static func turnPage(_ context: Context) -> Item {
        let detail: String
        if context.continuousScroll {
            detail = String(localized: "Fais défiler les pages avec le doigt. Les flèches ‹ › de la barre et les touches ← → d'un clavier changent aussi de page.", bundle: .main)
        } else if context.rightToLeft {
            detail = String(localized: "Page affichée en entier, glisse d'un doigt vers la droite pour avancer, vers la gauche pour revenir (lecture de droite à gauche). Les flèches ‹ › de la barre et les touches ← → d'un clavier changent aussi de page.", bundle: .main)
        } else {
            detail = String(localized: "Page affichée en entier, glisse d'un doigt vers la gauche pour avancer, vers la droite pour revenir. Les flèches ‹ › de la barre et les touches ← → d'un clavier changent aussi de page.", bundle: .main)
        }
        return Item(kind: .turnPage, icon: "hand.draw", title: String(localized: "Tourner la page", bundle: .main), detail: detail)
    }

    private static func zoom(_ context: Context) -> Item {
        let detail = context.doubleTapZoom
            ? String(localized: "Touche deux fois pour agrandir l'endroit touché, encore deux fois pour revoir la page entière. Tu peux aussi pincer. Page agrandie, glisser déplace la page au lieu de la tourner.", bundle: .main)
            : String(localized: "Pince avec deux doigts pour agrandir ou réduire. Page agrandie, glisser déplace la page au lieu de la tourner.", bundle: .main)
        return Item(kind: .zoom, icon: "plus.magnifyingglass", title: String(localized: "Zoomer", bundle: .main), detail: detail)
    }
}
