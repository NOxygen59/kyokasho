// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore

/// Point d'entrée de l'OCR : choisit le moteur, lit le cache, lance un seul OCR à la fois par
/// page/moteur (pas de doublon), enregistre le résultat. Tout se passe hors du fil principal.
public actor OCRService {
    /// Émis uniquement après un `store` réussi. userInfo : documentId, pageIndex, engine.
    /// L'observateur UI doit rejoindre le fil principal et relire le cache, jamais réécrire le résultat.
    public nonisolated static let cacheUpdated = Notification.Name("kyokasho.ocrCacheUpdated")

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
    /// Un changement de pagination interdit les lectures et écritures sur les anciens index.
    private var documentsBeingReplaced: [String: Int] = [:]
    private var documentGeneration: [String: UInt64] = [:]
    /// Relecture appliquée à chaque nouveau résultat avant sa mise en cache (dictionnaire, posée par l'app).
    private var postProcess: (@Sendable (OCRPage) async -> OCRPage)?

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
        guard let stored = try? decoder.decode(OCRPage.self, from: record.json),
              let page = stored.readable(atAdditionalRotation: additionalRotation(documentId: documentId, pageIndex: pageIndex))
        else { return nil }
        var fixed = OCRTargetLanguage.forDocument(documentId) == .japanese ? JapaneseOCRText.normalize(page) : page
        fixed.lines = fixed.lines.map { $0.downgradingDuplicateBoxes() }
        return fixed
    }

    public func additionalRotation(documentId: String, pageIndex: Int) -> Int {
        (try? database.pageTransforms(documentId: documentId)[pageIndex]?.rotation) ?? 0
    }

    /// Résultat de la page (cache, sinon calcul + mise en cache).
    public func page(documentId: String, url: URL, pageIndex: Int, engine: String, force: Bool = false) async throws -> OCRPage {
        guard documentsBeingReplaced[documentId] == nil else { throw CancellationError() }
        let generation = documentGeneration[documentId, default: 0]
        if !force, let hit = cached(documentId: documentId, pageIndex: pageIndex, engine: engine) { return hit }
        let rotation = additionalRotation(documentId: documentId, pageIndex: pageIndex)
        let key = "\(documentId)#\(pageIndex)#\(engine)#r\(rotation)"
        if let existing = running[key] {
            let result = try await existing.value
            guard documentsBeingReplaced[documentId] == nil,
                  documentGeneration[documentId, default: 0] == generation,
                  !Task.isCancelled else { throw CancellationError() }
            return result
        }
        guard let implementation = Self.engine(engine) else { throw OCRError.pageUnavailable }
        let process = postProcess
        let japanese = OCRTargetLanguage.forDocument(documentId) == .japanese
        // Relecture dans la même tâche : un second appel pour la même page reçoit le résultat déjà relu.
        let task = Task.detached(priority: .userInitiated) {
            var result = try await implementation.recognize(.pdfPage(url: url, index: pageIndex,
                                                                      additionalRotation: rotation))
            if japanese { result = JapaneseOCRText.normalize(result) }
            if result.engine != OCREngineID.pdfText, let process { result = await process(result) }
            if japanese { result = JapaneseOCRText.normalize(result) }
            return result
        }
        running[key] = task
        defer { running[key] = nil }
        let result = try await task.value
        // La tâche détachée peut terminer même si son appelant a été annulé pendant PageShift.
        guard documentsBeingReplaced[documentId] == nil,
              documentGeneration[documentId, default: 0] == generation,
              !Task.isCancelled else { throw CancellationError() }
        let json = try encoder.encode(result)
        try database.save(OCRResultRecord(documentId: documentId, pageIndex: pageIndex, engine: engine,
                                          json: json, durationMs: result.durationMs))
        return result
    }

    /// Génération des index de pages du document : change à chaque ajout ou suppression de pages (`beginPageMutation`).
    /// À capturer au début d'un travail qui écrira dans le cache, puis à passer à `store(expectedGeneration:)`.
    public func generation(documentId: String) -> UInt64 {
        documentGeneration[documentId, default: 0]
    }

    /// Remplace le résultat en cache (relecture par l'IA, correction à la main).
    /// - Parameters:
    ///   - expectedGeneration: génération capturée au début du travail. Si les pages ont changé depuis, l'index
    ///     `pageIndex` peut désigner une autre page : l'écriture est refusée (`CancellationError`), sans notification
    ///     (étape 2 de la reconstruction de l'OCR ; revue Codex de d87e048, §2). `nil` : refus seulement pendant le
    ///     changement de pages, comme avant.
    public func store(_ page: OCRPage, documentId: String, pageIndex: Int, expectedGeneration: UInt64? = nil) throws {
        guard documentsBeingReplaced[documentId] == nil else { throw CancellationError() }
        if let expectedGeneration, documentGeneration[documentId, default: 0] != expectedGeneration {
            throw CancellationError()
        }
        let normalized = OCRTargetLanguage.forDocument(documentId) == .japanese ? JapaneseOCRText.normalize(page) : page
        try database.save(OCRResultRecord(documentId: documentId, pageIndex: pageIndex, engine: normalized.engine,
                                          json: try encoder.encode(normalized), durationMs: normalized.durationMs))
        NotificationCenter.default.post(name: Self.cacheUpdated, object: nil,
                                        userInfo: ["documentId": documentId, "pageIndex": pageIndex, "engine": normalized.engine])
    }

    /// Pages (source) dont le texte OCR contient `query`, avec un extrait autour.
    /// Un seul résultat par page et par moteur préféré (premier moteur de `engines` qui a la page).
    // FDR-6.2 : décode toutes les pages → index FTS5 (GRDB) rempli à l'enregistrement. Voir § 6 étape 6.
    public func search(_ query: String, documentId: String, engines: [String]) -> [(page: Int, context: String)] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let records = try? database.ocrResults(documentId: documentId) else { return [] }
        let japanese = OCRTargetLanguage.forDocument(documentId) == .japanese
        var bestByPage: [Int: OCRPage] = [:]
        for record in records {
            guard let rank = engines.firstIndex(of: record.engine),
                  let stored = try? decoder.decode(OCRPage.self, from: record.json),
                  let page = stored.readable(atAdditionalRotation: additionalRotation(documentId: documentId, pageIndex: record.pageIndex))
            else { continue }
            if let current = bestByPage[record.pageIndex], let currentRank = engines.firstIndex(of: current.engine),
               currentRank <= rank { continue }
            bestByPage[record.pageIndex] = japanese ? JapaneseOCRText.normalize(page) : page
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

    /// Ferme l'entrée puis attend les moteurs déjà démarrés. Un moteur ignorant l'annulation ne
    /// peut plus enregistrer son résultat, car `page` contrôle encore l'état avant l'écriture.
    public func beginPageMutation(documentId: String) async {
        documentsBeingReplaced[documentId, default: 0] += 1
        documentGeneration[documentId, default: 0] &+= 1
        let tasks = running.filter { $0.key.hasPrefix(documentId + "#") }.map(\.value)
        tasks.forEach { $0.cancel() }
        for task in tasks { _ = await task.result }
    }

    public func endPageMutation(documentId: String) {
        guard let count = documentsBeingReplaced[documentId] else { return }
        if count == 1 { documentsBeingReplaced[documentId] = nil }
        else { documentsBeingReplaced[documentId] = count - 1 }
    }
}

/// Valeur protégée par un verrou (registre de moteurs partagé entre fils).
final class LockedValue<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&value) }
}
