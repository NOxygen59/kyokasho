// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Langue du texte que le lecteur IA doit privilégier. Les chiffres, symboles et formules restent inchangés.
public enum OCRTargetLanguage: String, CaseIterable, Sendable {
    case japanese
    case automatic

    public var title: String {
        switch self {
        case .japanese: String(localized: "Japonais", bundle: .main)
        case .automatic: String(localized: "Automatique (documents mixtes)", bundle: .main)
        }
    }

    private static func key(_ documentId: String) -> String { "scan.language.\(documentId)" }

    public static func forDocument(_ documentId: String) -> Self {
        Self(rawValue: UserDefaults.standard.string(forKey: key(documentId)) ?? "") ?? .japanese
    }

    public static func set(_ language: Self, forDocument documentId: String) {
        UserDefaults.standard.set(language.rawValue, forKey: key(documentId))
    }

    public static func forget(_ documentId: String) {
        UserDefaults.standard.removeObject(forKey: key(documentId))
    }

    /// Remplacement d'un cours (lot C2, revue R2 P2 n°2) : le choix de langue suit le document
    /// mis à jour, quelle que soit la voie (bascule directe ou reprise au lancement). Même
    /// principe que les modes d'outil : une clé d'arrivée déjà présente n'est **jamais** écrasée,
    /// la clé d'origine est retirée après copie. Rejouable : une fois la clé d'origine retirée,
    /// un nouveau passage ne fait rien.
    public static func remap(from oldId: String, to newId: String) {
        guard oldId != newId, let value = UserDefaults.standard.string(forKey: key(oldId)) else { return }
        if UserDefaults.standard.string(forKey: key(newId)) == nil {
            UserDefaults.standard.set(value, forKey: key(newId))
        }
        forget(oldId)
    }
}
