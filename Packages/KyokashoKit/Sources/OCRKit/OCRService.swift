// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore

/// Point d'entrée de l'OCR : choisit le moteur, lit le cache, lance un seul OCR à la fois par
/// page/moteur (pas de doublon), enregistre le résultat. Tout se passe hors du fil principal.
public actor OCRService {
    public static let engines: [any OCREngine] = [PDFTextEngine(), VisionOCREngine()]

    private let database: AppDatabase
    private var running: [String: Task<OCRPage, Error>] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: AppDatabase) {
        self.database = database
    }

    public static func engine(_ id: String) -> (any OCREngine)? {
        engines.first { $0.id == id }
    }

    /// Moteur réel pour un choix : `auto` = texte du PDF s'il existe, sinon Vision.
    public nonisolated static func resolve(_ choice: OCREngineChoice, url: URL, pageIndex: Int) -> String {
        switch choice {
        case .pdfText: return OCREngineID.pdfText
        case .vision: return OCREngineID.vision
        case .auto: return PDFTextEngine.hasTextLayer(url: url, pageIndex: pageIndex) ? OCREngineID.pdfText : OCREngineID.vision
        }
    }

    /// Résultat en cache, sans rien calculer.
    public func cached(documentId: String, pageIndex: Int, engine: String) -> OCRPage? {
        guard let record = try? database.ocrResult(documentId: documentId, pageIndex: pageIndex, engine: engine) else { return nil }
        guard let page = try? decoder.decode(OCRPage.self, from: record.json),
              page.version >= OCRPage.currentVersion else { return nil }
        return page
    }

    /// Résultat de la page (cache, sinon calcul + mise en cache).
    public func page(documentId: String, url: URL, pageIndex: Int, engine: String, force: Bool = false) async throws -> OCRPage {
        if !force, let hit = cached(documentId: documentId, pageIndex: pageIndex, engine: engine) { return hit }
        let key = "\(documentId)#\(pageIndex)#\(engine)"
        if let existing = running[key] { return try await existing.value }
        guard let implementation = Self.engine(engine) else { throw OCRError.pageUnavailable }
        let task = Task.detached(priority: .userInitiated) {
            try await implementation.recognize(.pdfPage(url: url, index: pageIndex))
        }
        running[key] = task
        defer { running[key] = nil }
        let result = try await task.value
        let json = try encoder.encode(result)
        try database.save(OCRResultRecord(documentId: documentId, pageIndex: pageIndex, engine: engine,
                                          json: json, durationMs: result.durationMs))
        return result
    }

    /// Annule les OCR en cours d'un document (page quittée, lecteur fermé).
    public func cancelAll(documentId: String) {
        for (key, task) in running where key.hasPrefix(documentId + "#") { task.cancel() }
    }
}
