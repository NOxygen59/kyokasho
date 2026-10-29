// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Noms des fichiers de lecture IA d'un document (`Analysis/<document>/<lecteur>-<page>.md`) : lectures des modèles
/// (`ovisocr2-3.md`…) et traductions des pages (`fr-3.md`, `en-3.md`). Un seul endroit décide quel fichier est une
/// traduction, pour qu'une suppression de traduction ne touche jamais une lecture.
public enum AIPageFile {
    /// Lecteurs dont le texte est une traduction (pas du japonais) : ni normalisé comme du japonais, ni gardé quand la
    /// page est relue (il ne correspondrait plus).
    public static let translationReaders: Set<String> = ["fr", "en"]

    public static func name(reader: String, page: Int) -> String { "\(reader)-\(page).md" }

    /// Page d'un fichier de ce lecteur exactement (`en-12.md` → 12) ; `nil` pour tout autre fichier.
    public static func page(of fileName: String, reader: String) -> Int? {
        let prefix = reader + "-"
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(".md") else { return nil }
        let digits = fileName.dropFirst(prefix.count).dropLast(3)
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }
}
