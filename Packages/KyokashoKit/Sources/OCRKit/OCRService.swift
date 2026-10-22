// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore

/// Point d'entrée de l'OCR : choisit le moteur, lit le cache, lance un seul OCR à la fois par
/// page/moteur (pas de doublon), enregistre le résultat. Tout se passe hors du fil principal.
public actor OCRService {
    /// Moteurs connus. L'app ajoute ceux qui ont besoin d'un modèle (ONNX, IA) avec `register`.
    public nonisolated static var engines: [any OCREngine] { registry.withLock { $0 } }
    private nonisolated static let registry = LockedValue<[any OCREngine]>([PDFTextEngine(), VisionOCREngine()])

    public nonisolated static func register(_ engine: any OCREngine) {
        registry.withLock { list in
            list.removeAll { $0.id == engine.id }
            list.append(engine)
        }
    }

    private let database: AppDatabase
    private var running: [String: Task<OCRPage, Error>] = [:]
    /// Relecture appliquée à chaque nouveau résultat avant sa mise en cache (dictionnaire, posée par l'app).
    private var postProcess: (@Sendable (OCRPage) async -> OCRPage)?

    public func setPostProcess(_ process: (@Sendable (OCRPage) async -> OCRPage)?) { postProcess = process }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: AppDatabase, postProcess: (@Sendable (OCRPage) async -> OCRPage)? = nil) {
        self.database = database
        self.postProcess = postProcess
    }

    public nonisolated static func engine(_ id: String) -> (any OCREngine)? {
        engines.first { $0.id == id }
    }

    /// Moteur réel pour un choix : `auto` = texte du PDF s'il existe, sinon Vision.
    public nonisolated static func resolve(_ choice: OCREngineChoice, url: URL, pageIndex: Int) -> String {
        switch choice {
        case .pdfText: return OCREngineID.pdfText
        case .vision: return OCREngineID.vision
        case .ppocr5: return OCREngineID.ppocr5
        case .ndlocr: return OCREngineID.ndlocr
        case .glmocr: return OCREngineID.glmocr
        case .auto:
            if PDFTextEngine.hasTextLayer(url: url, pageIndex: pageIndex) { return OCREngineID.pdfText }
            // Scan : NDLOCR (fait pour les livres japonais), sinon PP-OCRv5, sinon Apple Vision.
            for id in [OCREngineID.ndlocr, OCREngineID.ppocr5] where engine(id)?.isAvailable == true { return id }
            return OCREngineID.vision
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
        let process = postProcess
        // Relecture dans la même tâche : un second appel pour la même page reçoit le résultat déjà relu.
        let task = Task.detached(priority: .userInitiated) {
            var result = try await implementation.recognize(.pdfPage(url: url, index: pageIndex))
            if result.engine != OCREngineID.pdfText, let process { result = await process(result) }
            return result
        }
        running[key] = task
        defer { running[key] = nil }
        let result = try await task.value
        let json = try encoder.encode(result)
        try database.save(OCRResultRecord(documentId: documentId, pageIndex: pageIndex, engine: engine,
                                          json: json, durationMs: result.durationMs))
        return result
    }

    /// Remplace le résultat en cache (relecture par l'IA, correction à la main).
    public func store(_ page: OCRPage, documentId: String, pageIndex: Int) throws {
        try database.save(OCRResultRecord(documentId: documentId, pageIndex: pageIndex, engine: page.engine,
                                          json: try encoder.encode(page), durationMs: page.durationMs))
    }

    /// Pages (source) dont le texte OCR contient `query`, avec un extrait autour.
    /// Un seul résultat par page et par moteur préféré (premier moteur de `engines` qui a la page).
    // FDR-6.2 : décode toutes les pages → index FTS5 (GRDB) rempli à l'enregistrement. Voir § 6 étape 6.
    public func search(_ query: String, documentId: String, engines: [String]) -> [(page: Int, context: String)] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let records = try? database.ocrResults(documentId: documentId) else { return [] }
        var bestByPage: [Int: OCRPage] = [:]
        for record in records {
            guard let rank = engines.firstIndex(of: record.engine),
                  let page = try? decoder.decode(OCRPage.self, from: record.json),
                  page.version >= OCRPage.currentVersion else { continue }
            if let current = bestByPage[record.pageIndex], let currentRank = engines.firstIndex(of: current.engine),
               currentRank <= rank { continue }
            bestByPage[record.pageIndex] = page
        }
        var results: [(Int, String)] = []
        for (pageIndex, page) in bestByPage.sorted(by: { $0.key < $1.key }) {
            let text = page.lines.map(\.text).joined()
            guard let range = text.range(of: needle, options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive]) else { continue }
            let start = text.index(range.lowerBound, offsetBy: -15, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: 25, limitedBy: text.endIndex) ?? text.endIndex
            results.append((pageIndex, String(text[start..<end])))
        }
        return results
    }

    /// Annule les OCR en cours d'un document (page quittée, lecteur fermé).
    public func cancelAll(documentId: String) {
        for (key, task) in running where key.hasPrefix(documentId + "#") { task.cancel() }
    }
}

/// Valeur protégée par un verrou (registre de moteurs partagé entre fils).
final class LockedValue<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&value) }
}
