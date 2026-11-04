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

    /// Lecture OvisOCR2 corrigée par l'utilisateur, à côté du fichier du modèle, qui n'est jamais réécrit :
    /// même forme de nom, donc suivie par les décalages de pages, les sauvegardes et les paquets.
    static let correctedReader = "ovisedit"

    /// Nombre de pages lues par ce modèle pour ce document.
    static func pageCount(documentId: String, reader: String) -> Int {
        let directory = folder.appendingPathComponent(documentId, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix(reader + "-") && $0.hasSuffix(".md") }.count
    }

    static func hasCorrection(documentId: String, page: Int) -> Bool {
        FileManager.default.fileExists(atPath: url(documentId: documentId, reader: correctedReader, page: page).path)
    }

    static func writeCorrection(_ text: String, documentId: String, page: Int) throws {
        let target = url(documentId: documentId, reader: correctedReader, page: page)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: target, atomically: true, encoding: .utf8)
    }

    /// Retour à la lecture d'OvisOCR2, sans rien relancer.
    static func removeCorrection(documentId: String, page: Int) {
        try? FileManager.default.removeItem(at: url(documentId: documentId, reader: correctedReader, page: page))
    }

    static func read(documentId: String, reader: String, page: Int) -> String? {
        if reader == ModelSpec.ovisocr2.id,
           let corrected = try? String(contentsOf: url(documentId: documentId, reader: correctedReader, page: page), encoding: .utf8) {
            return corrected
        }
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

    /// Une rotation change l'image donnée aux modèles : toutes les lectures et traductions de ces pages sont périmées.
    static func removePages(documentId: String, pages: Set<Int>) throws {
        guard !pages.isEmpty else { return }
        let directory = folder.appendingPathComponent(documentId, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let suffixes = pages.map { "-\($0).md" }
        // Les corrections de l'utilisateur ne se recalculent pas : elles restent, comme celles de l'OCR.
        for name in names where suffixes.contains(where: name.hasSuffix) && !name.hasPrefix(correctedReader + "-") {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
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
