// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Toutes les lectures d'un modèle pour un document, en un seul fichier texte (aide au diagnostic).
public enum AIReadingExport {
    public struct Page: Equatable, Sendable {
        public let label: String
        public let text: String

        public init(label: String, text: String) {
            self.label = label
            self.text = text
        }
    }

    public static func text(title: String, reader: String, totalPages: Int, pages: [Page]) -> String {
        var lines = [String(localized: "Kyōkasho : lectures \(reader)", bundle: .main), String(localized: "Document : \(title)", bundle: .main),
                     String(localized: "Pages lues : \(pages.count) sur \(totalPages)", bundle: .main)]
        for page in pages {
            lines += ["", "=== Page \(page.label) ===", page.text.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Écrit dans un dossier temporaire propre à ce partage, comme `MarkdownShareFile`.
    public static func write(_ text: String, title: String, reader: String,
                             in folder: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let directory = folder.appendingPathComponent("partage-lectures-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = (MarkdownShareFile.fileName(for: title) as NSString).deletingPathExtension
        let url = directory.appendingPathComponent("\(base) - lectures \(reader).txt")
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }
}
