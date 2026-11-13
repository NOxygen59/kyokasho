// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import UIKit

/// Mode propriétaire (PLAN-MODLOC-001, E1 ; DEC-02 et DEC-03 = A, décidés par NOxygen59 le 13/11/2026) : trois touchers
/// rapides sur la carte « Temps de lecture » de l'accueil le basculent. Verrouillé (par défaut), **tout** le chat est
/// caché (onglet du panneau d'étude, « Discuter du livre », réglages du chat, modèle de chat dans les listes) ainsi que
/// l'import d'un modèle local. Rien n'est effacé en verrouillant : conversations, réglages et modèles restent en place.
/// Valeur dans les préférences de l'app (donc dans la sauvegarde) ; chaque écran la lit par `@AppStorage`.
enum OwnerMode {
    static let unlockedKey = "owner.unlocked"

    /// Bascule le mode et le signale seulement par une vibration (aucun texte à l'écran, DEC-01).
    @MainActor
    static func toggle() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: unlockedKey), forKey: unlockedKey)
        UINotificationFeedbackGenerator().notificationOccurred(defaults.bool(forKey: unlockedKey) ? .success : .warning)
    }
}
