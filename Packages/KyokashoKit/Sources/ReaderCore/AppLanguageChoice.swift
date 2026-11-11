// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Faut-il relancer l'app pour voir la langue choisie ? Seulement si elle diffère de celle déjà affichée.
public enum AppLanguageChoice {
    /// - Parameters:
    ///   - selected: choix de l'utilisateur, vide pour « Système ».
    ///   - running: langue de l'interface affichée, comme « fr », « en » ou « zh-Hans ».
    ///   - system: langue que l'app prendrait avec le choix « Système ».
    public static func needsRelaunch(selected: String, running: String, system: String) -> Bool {
        base(selected.isEmpty ? system : selected) != base(running)
    }

    /// « en-US » et « en » désignent la même interface ; « zh-Hans » reste distinct de « zh-Hant ».
    private static func base(_ language: String) -> String {
        language.hasPrefix("zh") ? language : String(language.prefix { $0 != "-" && $0 != "_" })
    }
}
