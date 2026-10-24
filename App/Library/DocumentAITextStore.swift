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
        return reader != "fr" && OCRTargetLanguage.forDocument(documentId) == .japanese
            ? JapaneseOCRText.normalize(text) : text
    }

    static func write(_ text: String, documentId: String, reader: String, page: Int) throws {
        let target = url(documentId: documentId, reader: reader, page: page)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: target, atomically: true, encoding: .utf8)
        if reader == ModelSpec.ovisocr2.id {
            try? FileManager.default.removeItem(at: url(documentId: documentId, reader: "fr", page: page))
        }
    }
}
