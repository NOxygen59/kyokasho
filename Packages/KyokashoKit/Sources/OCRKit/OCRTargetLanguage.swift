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
}
