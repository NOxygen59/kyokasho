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
    @Published private(set) var correctionsDone: Int?

    nonisolated static var folder: URL {
        DocumentAITextStore.folder
    }
    nonisolated static func rawURL(_ id: String, _ reader: String, _ page: Int) -> URL {
        DocumentAITextStore.url(documentId: id, reader: reader, page: page)
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
    func setCorrectionError(_ message: String?) { lastError = message }

    func update(_ id: String, _ change: (inout DocumentAnalysis) -> Void) {
        guard var r = report(for: id) else { return }
        change(&r)
        save(r)
    }

    /// Pages insérées avant celles du document (`PageShift`) : rapport renuméroté de `offset`.
    func shiftReport(_ id: String, by offset: Int) {
        guard offset != 0 else { return }
        update(id) { r in
            r.pages = Dictionary(uniqueKeysWithValues: r.pages.map { page, value in
                var value = value
                value.source = page + offset
                return (page + offset, value)
            })
        }
    }

    /// Le protocole PageShift installe un rapport final sur disque : oublier uniquement son cache.
    func reloadAfterPageShift(_ id: String) {
        cache[id] = nil
        revision += 1
    }

    /// Une nouvelle lecture brute rend le vote précédent de cette page périmé.
    func invalidatePage(_ source: Int, documentId: String) {
        update(documentId) { $0.pages[source] = nil }
    }

    /// Les votes reposent sur les résultats OCR : vider ce cache rend tous les votes précédents périmés.
    /// Les lectures OvisOCR2 et les traductions restent enregistrées.
    func invalidateReports(for documentIds: [String]) {
        correctionsDone = nil
        for id in documentIds where report(for: id) != nil {
            update(id) { $0.pages.removeAll() }
        }
    }

    func forget(_ id: String) {
        cache[id] = nil
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent("\(id).json"))
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(id, isDirectory: true))
        revision += 1
    }

    static let useQwenKey = "analysis.useQwen"

    /// Modèles qui liront le document en plus de l'OCR habituel (le plus lourd en dernier). Qwen3-VL-4B seulement
    /// si l'option est cochée : sur le manuel de l'utilisateur (22/10) il lit moins bien qu'OvisOCR2 (襖 → 桜) pour
    /// deux fois plus de mémoire (4 Go contre 2,1 Go) et de temps.
    static var readers: [String] {
        var list: [String] = []
        if OvisOCR2Reader().isAvailable { list.append(ModelSpec.ovisocr2.id) }
        if GLMOCREngine().isAvailable { list.append(OCREngineID.glmocr) }
        if Qwen3VLReader().isAvailable, UserDefaults.standard.bool(forKey: useQwenKey) { list.append(ModelSpec.qwen3vl4b.id) }
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
                            try? DocumentAITextStore.write(text, documentId: id, reader: reader, page: p)
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
                        r[reader] = DocumentAITextStore.read(documentId: id, reader: reader, page: p)
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

    /// Traduit en français (Qwen3-VL, hors ligne) toutes les pages déjà mises en page par OvisOCR2 et pas encore
    /// traduites ; même écran de progression que l'analyse (reprise possible).
    func translateAll(_ document: LibraryDocument) {
        guard progress == nil, Qwen3VLReader().isAvailable else { return }
        let id = document.id
        let pages = (0..<document.pageCount).filter {
            FileManager.default.fileExists(atPath: Self.rawURL(id, ModelSpec.ovisocr2.id, $0).path)
                && !FileManager.default.fileExists(atPath: Self.rawURL(id, "fr", $0).path)
        }
        guard !pages.isEmpty else { return }
        progress = Progress(documentId: id, phase: "Traduction (Qwen3-VL)", done: 0, total: pages.count, phaseStarted: Date())
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task { [weak self] in
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                self?.progress = nil
            }
            for (k, p) in pages.enumerated() {
                guard !Task.isCancelled else { break }
                guard let md = DocumentAITextStore.read(documentId: id, reader: ModelSpec.ovisocr2.id, page: p) else { continue }
                do {
                    let fr = try await Diagnostics.measure("traduction p. \(p)", "traduction") { try await Qwen3VLReader().translate(markdown: md, glossary: DomainLexicon.shared.glossary) }
                    try? DocumentAITextStore.write(fr, documentId: id, reader: "fr", page: p)
                } catch {
                    self?.lastError = "Traduction page \(p + 1) : \(error.localizedDescription)"
                }
                self?.step(done: k + 1)
            }
            await Qwen3VLReader().unload()
        }
    }

    /// Pages traduites / pages mises en page par OvisOCR2.
    static func translationCount(_ document: LibraryDocument) -> (done: Int, total: Int) {
        let laid = (0..<document.pageCount).filter { FileManager.default.fileExists(atPath: rawURL(document.id, ModelSpec.ovisocr2.id, $0).path) }
        return (laid.filter { FileManager.default.fileExists(atPath: rawURL(document.id, "fr", $0).path) }.count, laid.count)
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
        case ModelSpec.ovisocr2.id:
            return try await OvisOCR2Reader(language: OCRTargetLanguage.forDocument(documentId))
                .read(.pdfPage(url: url, index: page), maxTokens: maxTokens)
        case ModelSpec.qwen3vl4b.id:
            return try await Qwen3VLReader(language: OCRTargetLanguage.forDocument(documentId))
                .read(.pdfPage(url: url, index: page), maxTokens: maxTokens)
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
    static func preferred(_ candidates: [String], dictionary: DictionaryModel) async -> String? {
        guard await dictionary.hasTermDictionaries else { return nil }
        var scored: [(String, Int)] = []
        let terms = DomainLexicon.terms
        for text in candidates {
            // Termes du lexique du domaine comptés comme connus.
            let segments = OCRProofreader.addingTerms(terms, to: await dictionary.segment(text).map { (length: $0.text.count, known: $0.term != nil) }, in: text)
            scored.append((text, OCRProofreader.unknown(Array(text), segments).count))
        }
        let best = scored.map(\.1).min() ?? 0
        let winners = scored.filter { $0.1 == best }
        return winners.count == 1 ? winners[0].0 : nil
    }

    /// Accepte les différences déjà lues par Ovis sur tout le livre, sans lancer de nouvelle IA.
    /// Les corrections manuelles et les lignes mathématiques restent intactes.
    func applyOvisToDocument(_ document: LibraryDocument, model: AppModel) {
        guard progress == nil else { return }
        let id = document.id
        let url = model.storage.url(for: id)
        let choice = model.settings(for: document).ocrEngine
        let ocr = model.ocr
        correctionsDone = nil
        lastError = nil
        progress = Progress(documentId: id, phase: "Corrections OvisOCR2", done: 0,
                            total: document.pageCount, phaseStarted: Date())
        Diagnostics.log("Corrections OvisOCR2 : début de \(document.pageCount) pages", "analyse")
        task = Task { [weak self] in
            defer { self?.progress = nil }
            var total = 0
            for source in 0..<document.pageCount {
                guard !Task.isCancelled, let self else { return }
                defer { self.step(done: source + 1) }
                guard let reference = DocumentAITextStore.read(documentId: id, reader: ModelSpec.ovisocr2.id, page: source),
                      !reference.isEmpty else { continue }
                let preferred = await Task.detached { OCRService.resolve(choice, url: url, pageIndex: source) }.value
                let engines = [preferred, OCREngineID.vision, OCREngineID.ndlocr, OCREngineID.ppocr5]
                var cachedPage: OCRPage?
                // Le choix de moteur peut avoir changé depuis l'import : chercher un cache existant.
                for engine in engines where cachedPage == nil {
                    cachedPage = await ocr.cached(documentId: id, pageIndex: source, engine: engine)
                }
                guard var page = cachedPage else { continue }
                let snapshot = page
                let suggestions = await Task.detached(priority: .userInitiated) {
                    OCRReferenceDiff.suggestions(snapshot, reference: reference)
                }.value
                var changed = 0
                for suggestion in suggestions where page.lines.indices.contains(suggestion.line) {
                    let line = page.lines[suggestion.line]
                    guard line.edited != true,
                          !Self.looksMathematical(line.text), !Self.looksMathematical(suggestion.proposed) else { continue }
                    page.lines[suggestion.line] = ReaderController.corrected(line, text: suggestion.proposed)
                    changed += 1
                }
                guard changed > 0 else { continue }
                do {
                    try await ocr.store(page, documentId: id, pageIndex: source)
                    total += changed
                    self.invalidatePage(source, documentId: id)
                } catch {
                    self.lastError = "Page \(document.pageLabel(source)) : \(error.localizedDescription)"
                    Diagnostics.error(error.localizedDescription, "corrections OvisOCR2 p. \(document.pageLabel(source))")
                }
            }
            self?.correctionsDone = total
            Diagnostics.log("Corrections OvisOCR2 : \(total) lignes enregistrées", "analyse")
        }
    }

    private static func looksMathematical(_ text: String) -> Bool {
        text.contains(where: { "=∝√∑∫±≤≥≈^_{}\\".contains($0) })
            || text.contains("\\frac") || text.contains("\\sqrt")
    }

}
