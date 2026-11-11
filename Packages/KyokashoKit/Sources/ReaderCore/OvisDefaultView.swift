// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// OvisOCR2 par défaut dans le panneau Texte (RET-024, #39, décision de NOxygen59 du 28/10) : la vue « Mise en page
/// IA » (lecture OvisOCR2) remplace une seule fois l'affichage d'office, puis le choix de l'utilisateur est respecté.
///
/// Rien ne se lance tout seul : une page sans lecture OvisOCR2 montre le bouton « Mettre en page avec OvisOCR2 »
/// (une lecture coûte environ 30 s de calcul et de la batterie, RET-017).
public enum OvisDefaultView {
    public static let appliedKey = "study.ovisDefaultApplied"

    /// `true` : passer le panneau en « Mise en page IA » maintenant (une fois, et seulement si OvisOCR2 est installé ;
    /// sans modèle, on réessaiera après son téléchargement).
    public static func shouldSwitch(ovisInstalled: Bool, alreadyApplied: Bool) -> Bool {
        ovisInstalled && !alreadyApplied
    }
}
