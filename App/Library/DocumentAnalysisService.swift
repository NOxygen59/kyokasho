// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GLMOCRKit
import OCRKit
import ReaderCore
import SwiftUI
import UIKit

/// « Analyser le document entier » : 1) OCR habituel de chaque page, 2) lecture de chaque page par OvisOCR2,
/// GLM-OCR puis Qwen3-VL-4B (ceux qui sont installés ; un modèle à la fois pour la mémoire, le plus lourd en
/// dernier), 3) vote ligne par ligne → fiabilité et choix conseillés. Rapport : `Analysis/<id>.json` ; lectures
/// brutes : `Analysis/<id>/<lecteur>-<page>.md` (une analyse arrêtée reprend là où elle s'était arrêtée).
/// Lourd par choix : l'écran reste allumé, l'app doit rester ouverte.
@MainActor
final class DocumentAnalysisService: ObservableObject {
    static let shared = DocumentAnalysisService()

    struct Progress: Equatable {
        var documentId: String
        var phase: String
        var done: Int
        var total: Int
        var phaseStarted: Date
        var cancelling = false
    }

    @Published private(set) var progress: Progress?
    /// Change à chaque enregistrement d'un rapport (les vues relisent `report(for:)`).
    @Published private(set) var revision = 0
    @Published private(set) var lastError: String?
    /// Cache de lecture, **pas** publié : `report(for:)` peut être appelé pendant l'affichage.
    private var cache: [String: DocumentAnalysis] = [:]
    private var task: Task<Void, Never>?

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Analysis", isDirectory: true)
    }
    private static func rawURL(_ id: String, _ reader: String, _ page: Int) -> URL {
        folder.appendingPathComponent(id, isDirectory: true).appendingPathComponent("\(reader)-\(page).md")
    }

    func report(for id: String) -> DocumentAnalysis? {
        if let r = cache[id] { return r }
        let url = Self.folder.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url), let r = try? JSONDecoder().decode(DocumentAnalysis.self, from: data) else { return nil }
        cache[id] = r
        return r
    }

    private func save(_ r: DocumentAnalysis) {
        cache[r.documentId] = r
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(r) {
            try? data.write(to: Self.folder.appendingPathComponent("\(r.documentId).json"), options: .atomic)
        }
        revision += 1
    }

    /// Relit le rapport enregistré, le modifie et le réenregistre (jamais une copie périmée).
    private func update(_ id: String, _ change: (inout DocumentAnalysis) -> Void) {
        guard var r = report(for: id) else { return }
        change(&r)
        save(r)
    }

    func forget(_ id: String) {
        cache[id] = nil
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent("\(id).json"))
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(id, isDirectory: true))
        revision += 1
    }

    /// Modèles qui liront le document en plus de l'OCR habituel (le plus lourd en dernier).
    static var readers: [String] {
        var list: [String] = []
        if OvisOCR2Reader().isAvailable { list.append(ModelSpec.ovisocr2.id) }
        if GLMOCREngine().isAvailable { list.append(OCREngineID.glmocr) }
        if Qwen3VLReader().isAvailable { list.append(ModelSpec.qwen3vl4b.id) }
        return list
    }

    func start(_ document: LibraryDocument, model: AppModel) {
        guard progress == nil else { return }
        lastError = nil
        let id = document.id
        let url = model.storage.url(for: id)
        let choice = model.settings(for: document).ocrEngine
        let service = model.ocr
        let dictionary = model.dictionary
        let pages = Array(0..<document.pageCount)
        let readers = Self.readers
        if report(for: id) == nil { save(DocumentAnalysis(documentId: id)) }
        update(id) { $0.engines = readers }
        progress = Progress(documentId: id, phase: "Lecture OCR", done: 0, total: pages.count, phaseStarted: Date())
        UIApplication.shared.isIdleTimerDisabled = true
        Diagnostics.log("analyse \(document.title) : \(pages.count) pages, lecteurs \(readers)", "analyse")

        task = Task { [weak self] in
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                self?.progress = nil
            }
            // 1. OCR habituel (en cache le plus souvent).
            var base: [Int: OCRPage] = [:]
            var errors: [Int: String] = [:]
            for p in pages {
                guard !Task.isCancelled, let self else { return }
                let engine = await Task.detached { OCRService.resolve(choice, url: url, pageIndex: p) }.value
                do { base[p] = try await service.page(documentId: id, url: url, pageIndex: p, engine: engine) }
                catch { errors[p] = "OCR : \(error.localizedDescription)" }
                self.step(done: p + 1)
            }
            // 2. Chaque modèle lit toutes les pages, l'un après l'autre (un seul modèle en mémoire).
            for reader in readers {
                guard let self, !Task.isCancelled else { return }
                self.phase("Lecture \(Self.name(reader))", total: pages.count)
                for p in pages {
                    guard !Task.isCancelled else { break }
                    let file = Self.rawURL(id, reader, p)
                    if let b = base[p], b.engine != OCREngineID.pdfText, !FileManager.default.fileExists(atPath: file.path) {
                        do {
                            let budget = Self.tokenBudget(b)
                            let text = try await Diagnostics.measure("\(reader) p. \(p) (≤ \(budget) jetons)", "analyse") {
                                try await Self.read(reader, url: url, page: p, maxTokens: budget, service: service, documentId: id)
                            }
                            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try? text.write(to: file, atomically: true, encoding: .utf8)
                        } catch {
                            errors[p] = "\(Self.name(reader)) : \(error.localizedDescription)"
                        }
                    }
                    self.step(done: p + 1)
                }
                await Self.unload(reader)
            }
            // 3. Vote (calcul lourd : hors du fil principal).
            guard let self, !Task.isCancelled else { return }
            self.phase("Vote", total: pages.count)
            for p in pages {
                guard !Task.isCancelled else { return }
                var page: DocumentAnalysis.Page
                if let b = base[p], b.engine != OCREngineID.pdfText {
                    let readings = readers.reduce(into: [String: String]()) { r, reader in
                        r[reader] = try? String(contentsOf: Self.rawURL(id, reader, p), encoding: .utf8)
                    }
                    page = await Task.detached {
                        await DocumentAnalysis.vote(source: p, base: b, readings: readings) { candidates in
                            await DocumentAnalysisService.preferred(candidates, dictionary: dictionary)
                        }
                    }.value
                } else {
                    page = .init(source: p, baseEngine: base[p]?.engine ?? "")
                }
                page.error = errors[p]
                self.update(id) { report in
                    // Désaccords déjà réglés (appliqués ou « garder tel quel ») : ils le restent.
                    let settled = Set(report.pages[p]?.disagreements.filter(\.settled).map(\.line) ?? [])
                    for i in page.disagreements.indices where settled.contains(page.disagreements[i].line) {
                        page.disagreements[i].settled = true
                    }
                    report.pages[p] = page
                    report.date = Date()
                }
                self.step(done: p + 1)
            }
            if let r = self.report(for: id) {
                Diagnostics.log("analyse finie : fiabilité \(Int(r.reliability * 100)) %, \(r.openDisagreements) désaccord(s), \(r.errorPages) page(s) en erreur", "analyse")
            }
        }
    }

    /// Arrête après la lecture en cours (le modèle n'est libéré qu'une fois la lecture vraiment finie).
    func cancel() {
        guard let task else { return }
        progress?.cancelling = true
        task.cancel()
        Task {
            await task.value
            for reader in [ModelSpec.ovisocr2.id, OCREngineID.glmocr, ModelSpec.qwen3vl4b.id] { await Self.unload(reader) }
        }
    }

    private func step(done: Int) { progress?.done = done }

    private func phase(_ name: String, total: Int) {
        progress?.phase = name
        progress?.done = 0
        progress?.total = total
        progress?.phaseStarted = Date()
    }

    nonisolated static func name(_ engine: String) -> String {
        switch engine {
        case ModelSpec.ovisocr2.id: return "OvisOCR2"
        case OCREngineID.glmocr: return "GLM-OCR"
        case ModelSpec.qwen3vl4b.id: return "Qwen3-VL-4B"
        case "ocr": return "OCR"
        default: return OCREngineID.displayName(engine)
        }
    }

    /// Lecture d'une page par un modèle → texte (Markdown pour OvisOCR2 / Qwen3-VL, lignes pour GLM-OCR).
    /// Longueur maximale d'une lecture : ≈ deux fois le texte que l'OCR a trouvé (Markdown compris). Évite qu'un
    /// modèle qui boucle remplisse la mémoire jusqu'à 4096 jetons.
    static func tokenBudget(_ page: OCRPage) -> Int {
        let chars = page.lines.reduce(0) { $0 + $1.text.count }
        return min(4096, max(384, chars * 2 + 256))
    }

    private static func read(_ reader: String, url: URL, page: Int, maxTokens: Int, service: OCRService, documentId: String) async throws -> String {
        switch reader {
        case ModelSpec.ovisocr2.id: return try await OvisOCR2Reader().read(.pdfPage(url: url, index: page), maxTokens: maxTokens)
        case ModelSpec.qwen3vl4b.id: return try await Qwen3VLReader().read(.pdfPage(url: url, index: page), maxTokens: maxTokens)
        default:
            let glm = try await service.page(documentId: documentId, url: url, pageIndex: page, engine: OCREngineID.glmocr)
            return glm.lines.map(\.text).joined(separator: "\n")
        }
    }

    private static func unload(_ reader: String) async {
        switch reader {
        case ModelSpec.ovisocr2.id: await OvisOCR2Reader().unload()
        case ModelSpec.qwen3vl4b.id: await Qwen3VLReader().unload()
        default: await GLMOCREngine.unload()
        }
    }

    /// Égalité : le texte avec le moins de caractères hors dictionnaire ; `nil` si personne ne se détache.
    // FDR-S : compter aussi les mots du lexique du domaine comme connus.
    static func preferred(_ candidates: [String], dictionary: DictionaryModel) async -> String? {
        guard await dictionary.hasTermDictionaries else { return nil }
        var scored: [(String, Int)] = []
        for text in candidates {
            let segments = await dictionary.segment(text).map { (length: $0.text.count, known: $0.term != nil) }
            scored.append((text, OCRProofreader.unknown(Array(text), segments).count))
        }
        let best = scored.map(\.1).min() ?? 0
        let winners = scored.filter { $0.1 == best }
        return winners.count == 1 ? winners[0].0 : nil
    }

    /// Applique des choix dans le résultat OCR du document : seulement sur une ligne pas encore réglée et dont
    /// le texte n'a pas changé depuis l'analyse ; marquée réglée **après** l'enregistrement réussi.
    func apply(_ choices: [(source: Int, line: Int, text: String)], documentId: String, service: OCRService) async {
        guard let report = report(for: documentId) else { return }
        for source in Set(choices.map(\.source)).sorted() {
            guard let info = report.pages[source],
                  var page = await service.cached(documentId: documentId, pageIndex: source, engine: info.baseEngine) else { continue }
            var done: [Int] = []
            for c in choices where c.source == source && page.lines.indices.contains(c.line) {
                guard let vote = info.disagreements.first(where: { $0.line == c.line }), !vote.settled,
                      page.lines[c.line].text == vote.base else { continue }
                page.lines[c.line] = ReaderController.corrected(page.lines[c.line], text: c.text)
                done.append(c.line)
            }
            guard !done.isEmpty else { continue }
            do {
                try await service.store(page, documentId: documentId, pageIndex: source)
            } catch {
                lastError = "Page \(source + 1) non enregistrée : \(error.localizedDescription)"
                continue
            }
            update(documentId) { r in
                for line in done {
                    guard let i = r.pages[source]?.disagreements.firstIndex(where: { $0.line == line && !$0.settled }) else { continue }
                    r.pages[source]?.disagreements[i].settled = true
                    r.pages[source]?.confirmed += 1
                }
            }
        }
    }

    func dismiss(source: Int, line: Int, documentId: String) {
        update(documentId) { r in
            guard let i = r.pages[source]?.disagreements.firstIndex(where: { $0.line == line && !$0.settled }) else { return }
            r.pages[source]?.disagreements[i].settled = true
            // Tu as tranché : la ligne compte comme sûre.
            r.pages[source]?.confirmed += 1
        }
    }
}
