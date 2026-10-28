// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Règles de la bande des pages (miniatures en bas du lecteur), sans UIKit pour être testées sur Mac (RET-049, #79).
public enum FilmstripLayout {
    /// Pages à surligner dans la bande : celles qui sont réellement à l'écran.
    ///
    /// - Page simple : la seule page courante. La liste `shown` de PDFKit peut contenir la voisine entrevue en
    ///   défilement continu, qu'on ne surligne pas.
    /// - Double page : les pages de la planche affichée (`shown`, deux pages, ou une seule en couverture ou en
    ///   dernière page impaire). `shown` n'est mis à jour qu'une fois la page posée (≈ 0,35 s) : tant qu'elle
    ///   ne contient pas la page courante, elle décrit l'ancienne planche et on retombe sur la page courante.
    public static func highlightedPages(current: Int, shown: [Int], isDouble: Bool) -> Set<Int> {
        guard isDouble, shown.contains(current) else { return [current] }
        return Set(shown)
    }

    /// Marge droite de la bande pour qu'elle s'arrête au bord du panneau d'étude flottant en portrait.
    /// Le panneau occupe `panelWidth` plus sa marge droite `gap` ; la marge propre de la bande (`gap` de chaque
    /// côté) la sépare ensuite du panneau. Sans ce panneau (paysage, où il a sa propre colonne, ou panneau
    /// détaché/fermé), aucune marge.
    public static func trailingInset(portraitPanelShown: Bool, panelWidth: CGFloat, gap: CGFloat) -> CGFloat {
        portraitPanelShown ? panelWidth + gap : 0
    }
}
