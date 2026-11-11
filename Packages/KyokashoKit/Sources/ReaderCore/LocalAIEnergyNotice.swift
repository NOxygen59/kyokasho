// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Avertissement de l'accueil sur la consommation de l'IA locale (RET-018, #21).
///
/// Rien sans modèle MLX installé. Sinon, l'avertissement s'affiche jusqu'à « Compris », puis revient seulement
/// quand une IA locale travaille alors que l'iPad est sur batterie (60 % perdus en 1 h 30 observés, RET-017).
public enum LocalAIEnergyNotice: Equatable, Sendable {
    case hidden
    /// Explication générale, avec le bouton « Compris ».
    case general
    /// Une IA locale travaille sur batterie : rappel court, sans bouton.
    case activeOnBattery

    public static func state(modelInstalled: Bool, acknowledged: Bool, aiActive: Bool, onBattery: Bool) -> Self {
        guard modelInstalled else { return .hidden }
        if aiActive && onBattery { return .activeOnBattery }
        return acknowledged ? .hidden : .general
    }
}
