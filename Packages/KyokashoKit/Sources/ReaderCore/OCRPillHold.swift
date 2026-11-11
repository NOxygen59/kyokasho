// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Pastille du moteur OCR à côté du numéro de page (« Apple Vision », « NDLOCR-Lite »…), sans UIKit pour être testée
/// sur Mac (RET-041, #60).
///
/// À chaque page posée, le lecteur efface le résultat OCR de l'ancienne page (`ocrPage = nil`) puis le recharge depuis
/// le cache quelques millisecondes plus tard. Affichée telle quelle, la pastille disparaissait puis revenait : la capsule
/// du titre changeait de largeur une fraction de seconde à chaque page. La pastille garde donc le dernier moteur
/// pendant ``holdDelay`` et ne s'efface que si aucun résultat n'arrive entre-temps.
public enum OCRPillHold {
    /// Attente avant d'effacer la pastille : couvre la pose de la page et la lecture du cache, sans laisser
    /// longtemps un moteur affiché sur une page qui n'a pas d'OCR.
    public static let holdDelay: TimeInterval = 1.0

    public enum Step: Equatable {
        /// Afficher ce moteur tout de suite (et annuler un effacement en attente).
        case show(String)
        /// Garder le moteur affiché, puis l'effacer après ``holdDelay`` si rien n'arrive.
        case holdThenClear
        /// Rien à changer.
        case keep
    }

    /// Décision quand le moteur du résultat OCR courant passe à `incoming` alors que la pastille montre `shown`.
    public static func step(shown: String?, incoming: String?) -> Step {
        if let incoming { return .show(incoming) }
        return shown == nil ? .keep : .holdThenClear
    }
}
