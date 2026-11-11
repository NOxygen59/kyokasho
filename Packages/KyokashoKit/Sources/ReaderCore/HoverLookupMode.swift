// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Survol au curseur sur la page PDF (RET-021, #24), sans UIKit pour être testé sur Mac.
///
/// Deux façons d'avoir le dictionnaire au survol :
/// - le bouton « Dictionnaire au survol » de la barre, comme avant : survol permanent ;
/// - **Maj tenue**, même bouton éteint : survol « push to talk », comme dans le panneau Texte (#13, PR #57).
///   Relâcher Maj ferme alors la bulle ouverte par Maj.
public enum HoverLookupMode {
    /// Le survol cherche-t-il un mot ? `drawing` : mode écriture, jamais.
    public static func isActive(toggleOn: Bool, shiftHeld: Bool, drawing: Bool) -> Bool {
        !drawing && (toggleOn || shiftHeld)
    }

    /// Une recherche lancée au survol l'a-t-elle été seulement grâce à Maj ?
    public static func opensWithShiftOnly(toggleOn: Bool, shiftHeld: Bool) -> Bool {
        !toggleOn && shiftHeld
    }

    /// Maj relâchée : fermer la bulle si elle a été ouverte par Maj seule et que le survol permanent reste éteint.
    public static func closesOnShiftRelease(toggleOn: Bool, openedByShiftOnly: Bool, bubbleOpen: Bool) -> Bool {
        bubbleOpen && openedByShiftOnly && !toggleOn
    }
}
