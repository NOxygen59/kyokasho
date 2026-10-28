// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Réglage « fond des pages » enregistré (`reader.pageTone`) : valeurs retirées, remplacées au lancement (RET-027, #42).
public enum PageToneMigration {
    /// « Sombre intelligent (expérimental) » est retiré : qui l'utilisait passe à « Sombre (inversé) », le plus proche.
    public static let replacements = ["smartDark": "dark"]

    /// Valeur à enregistrer à la place de `stored`, ou `nil` si rien ne change.
    public static func migrated(_ stored: String?) -> String? {
        stored.flatMap { replacements[$0] }
    }
}
