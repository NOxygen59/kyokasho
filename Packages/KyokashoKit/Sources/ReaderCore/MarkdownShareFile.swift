// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Fichier `.md` écrit **avant** d'ouvrir la fenêtre de partage (recette 1.3.2 (61) : « Markdown » n'ouvrait rien).
///
/// L'ancien bouton passait par un `ShareLink` SwiftUI qui fabriquait le fichier seulement au moment du partage, avec
/// un type `.md` qu'iOS 16 ne déclare pas : sur l'iPad, la fenêtre de partage ne s'ouvrait pas. Un vrai fichier sur
/// disque, partagé comme le journal (qui fonctionne), évite les deux.
public enum MarkdownShareFile {
    /// Nom de fichier sûr : sans « / » ni « : », sans blancs en bord, jamais vide.
    public static func fileName(for title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Notes" : cleaned) + ".md"
    }

    /// Écrit `text` dans un dossier temporaire propre à ce partage et renvoie l'adresse du fichier.
    public static func write(_ text: String, title: String, in folder: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let directory = folder.appendingPathComponent("partage-markdown-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(for: title))
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }
}
