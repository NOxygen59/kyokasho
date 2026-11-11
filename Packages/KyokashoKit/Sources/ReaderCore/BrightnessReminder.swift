// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Rappel de luminosité en lecture (choix de NOxygen59 du 11/11/2026, idée IDE-002 de l'audit).
///
/// Pourquoi : sur le relevé de batterie de l'iPad de NOxygen59 (12 jours, analysé le 10/11/2026), la lecture simple a
/// coûté 36 points de batterie par heure au-dessus de 90 % de luminosité, contre 13 à 60 % ou moins. C'est l'écran, pas
/// l'app, qui explique l'essentiel : le rappel le dit une fois, sans rien régler à la place de l'utilisateur.
///
/// Décision pure, sans UIKit, testée sur Mac. Les deux débits sont des **mesures de cet iPad**, pas des valeurs
/// générales : à remettre à jour si un nouveau relevé les contredit.
public enum BrightnessReminder {
    /// Au-dessus : tranche « > 90 % » du relevé (`EnergyLog.BrightnessBand.high`).
    public static let threshold = 0.90
    /// Points de batterie par heure mesurés en lecture, luminosité > 90 %.
    public static let measuredHighRate = 36
    /// Points de batterie par heure mesurés en lecture, luminosité ≤ 60 %.
    public static let measuredLowRate = 13
    /// Réglage « Rappel de luminosité » (allumé tant que rien n'est réglé).
    public static let enabledKey = "reader.brightnessReminder"

    /// Faut-il montrer le rappel ?
    /// - Parameters:
    ///   - brightness: réglage de l'écran, 0…1 ; négatif si iOS ne le donne pas.
    ///   - onBattery: appareil débranché. Branché ou état inconnu : rien, la batterie n'est pas en jeu.
    ///   - enabled: réglage de l'utilisateur.
    ///   - dismissed: rappel déjà fermé depuis le lancement de l'app (une fois par séance, jamais insistant).
    public static func shouldShow(brightness: Double, onBattery: Bool, enabled: Bool, dismissed: Bool) -> Bool {
        enabled && !dismissed && onBattery && brightness > threshold
    }

    /// Luminosité affichée, en pour cent entiers (bornée à 0…100).
    public static func percent(_ brightness: Double) -> Int {
        Int((min(max(brightness, 0), 1) * 100).rounded())
    }
}
