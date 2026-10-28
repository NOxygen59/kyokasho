// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Position enregistrée du panneau d'étude (`study.panelMode`) après le retrait du bouton « − » (RET-023, #38).
///
/// Le panneau ne se réduit plus en pastille : × le masque, et les trois positions restent (à droite, fenêtre, plein
/// écran). Un panneau resté « réduit » d'une version précédente reprend sa dernière position, sinon « à droite ».
public enum StudyPanelModeMigration {
    public static let removed = "minimized"
    public static let fallback = "docked"

    /// Valeur à enregistrer à la place de `mode`, ou `nil` si rien ne change.
    public static func migrated(mode: String?, restore: String?) -> String? {
        guard mode == removed else { return nil }
        if let restore, restore != removed { return restore }
        return fallback
    }
}
