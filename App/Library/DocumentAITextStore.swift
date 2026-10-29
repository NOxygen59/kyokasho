// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit

/// Un seul emplacement pour les lectures IA d'un document. Le texte enregistré reste celui du
/// modèle ; les corrections de présentation sont appliquées à la lecture, sans modifier l'original.
enum DocumentAITextStore {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Analysis", isDirectory: true)
    }

    static func url(documentId: String, reader: String, page: Int) -> URL {
        folder.appendingPathComponent(documentId, isDirectory: true)
            .appendingPathComponent("\(reader)-\(page).md")
    }

    static func read(documentId: String, reader: String, page: Int) -> String? {
        guard let text = try? String(contentsOf: url(documentId: documentId, reader: reader, page: page), encoding: .utf8) else { return nil }
        // Une traduction (français, anglais) n'est pas du japonais : jamais normalisée comme tel.
        return !AIPageFile.translationReaders.contains(reader) && OCRTargetLanguage.forDocument(documentId) == .japanese
            ? JapaneseOCRText.normalize(text) : text
    }

    static func write(_ text: String, documentId: String, reader: String, page: Int) throws {
        let target = url(documentId: documentId, reader: reader, page: page)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: target, atomically: true, encoding: .utf8)
        if reader == ModelSpec.ovisocr2.id {
            // Page relue : ses traductions ne correspondent plus, quelle que soit leur langue.
            for language in AIPageFile.translationReaders {
                try? FileManager.default.removeItem(at: url(documentId: documentId, reader: language, page: page))
            }
        }
    }

    /// Supprime toutes les traductions d'un document dans une langue (`fr` ou `en`), et seulement elles : les
    /// lectures des modèles et l'autre langue restent. Renvoie le nombre de pages supprimées.
    @discardableResult
    static func removeTranslation(documentId: String, reader: String) throws -> Int {
        guard AIPageFile.translationReaders.contains(reader) else { return 0 }
        let directory = folder.appendingPathComponent(documentId, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names where AIPageFile.page(of: name, reader: reader) != nil {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            removed += 1
        }
        return removed
    }
}
