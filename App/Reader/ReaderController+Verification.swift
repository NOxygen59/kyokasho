// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import GLMOCRKit
import OCRKit
import PDFKit
import PencilKit
import ReaderCore
import UIKit

/// `ReaderController` : vérification par OvisOCR2.
extension ReaderController {
    // MARK: Vérification par OvisOCR2 (à la demande)

    struct PageVerification: Identifiable {
        var id: Int { source }
        let source: Int
        /// Moteur du résultat OCR vérifié (les propositions ne valent que pour lui).
        var engine: String?
        var suggestions: [OCRReferenceDiff.Suggestion]
        var error: String?
    }

    enum VerifyState: Equatable { case idle, running(done: Int, total: Int), done }

    var verifyKey: String { "verify|\(document.id)" }

    /// Compare les pages affichées ; un rescan forcé relit seulement la page choisie dans le panneau.
    /// Rien n'est changé sans accord ; le modèle est libéré à la fin.
    func verifyShownPages(force: Bool = false) {
        guard OvisOCR2Reader().isAvailable, !AITaskCenter.shared.isRunning(verifyKey) else { return }
        let sources = force ? [focusSource] : shownSources
        let url = fileURL, service = model.ocr, documentId = document.id
        let focused = focusSource, focusedPage = ocrPage, engines = preferredEngines()
        verifications = []
        verifyState = .running(done: 0, total: sources.count)
        // Tâche de l'app : continue si on change de page ou ferme le lecteur (le Markdown lu reste gardé).
        AITaskCenter.shared.run(verifyKey, title: "Vérification OvisOCR2", modelId: ModelSpec.ovisocr2.id, activity: "vérification") { [weak self] id in
            defer { if let self, case .running = self.verifyState { self.verifyState = Task.isCancelled ? .idle : .done } }
            for (k, source) in sources.enumerated() {
                AITaskCenter.shared.setProgress(id, done: k, total: sources.count)
                guard !Task.isCancelled else { break }
                var result = PageVerification(source: source, suggestions: [])
                // Lecteur fermé entre-temps : on continue avec ce qui a été noté au départ (le Markdown est gardé).
                var ocr: OCRPage? = source == focused ? focusedPage : nil
                for engine in engines where ocr == nil {
                    ocr = await service.cached(documentId: documentId, pageIndex: source, engine: engine)
                }
                if ocr == nil, let engine = await self?.scanEngine(source: source) {
                    ocr = try? await service.page(documentId: documentId, url: url, pageIndex: source, engine: engine)
                }
                result.engine = ocr?.engine
                if let ocr {
                    do {
                        let markdown: String
                        // Page déjà lue par OvisOCR2 (scan à l'ouverture, mise en page IA, analyse) : même modèle,
                        // même page, température 0 → même texte ; réutilisé au lieu de ≈ 20 à 40 s de lecture.
                        if !force, let known = DocumentAITextStore.read(documentId: documentId, reader: ModelSpec.ovisocr2.id, page: source), !known.isEmpty {
                            markdown = known
                            Diagnostics.log("OvisOCR2 page \(source) : déjà lue (\(markdown.count) caractères)", "verif")
                            AITaskCenter.shared.log(id, "p. \(source + 1) : lecture OvisOCR2 déjà faite, réutilisée")
                        } else {
                            AITaskCenter.shared.log(id, "p. \(source + 1) : OvisOCR2 lit la page (≈ 20 à 40 s)…")
                            let rotation = await service.additionalRotation(documentId: documentId, pageIndex: source)
                            markdown = try await Diagnostics.measure("OvisOCR2 page \(source)", "verif") {
                                try await OvisOCR2Reader(language: OCRTargetLanguage.forDocument(documentId))
                                    .read(.pdfPage(url: url, index: source, additionalRotation: rotation),
                                                                maxTokens: DocumentAnalysisService.tokenBudget(ocr))
                            }
                            // Arrêtée : texte partiel, jamais gardé.
                            try Task.checkCancellation()
                            Diagnostics.log("OvisOCR2 page \(source) : \(markdown.count) caractères lus", "verif")
                            // Gardé : sert aussi à la vue « Mise en page IA » du panneau Texte.
                            try DocumentAITextStore.write(markdown, documentId: documentId, reader: ModelSpec.ovisocr2.id, page: source)
                            DocumentAnalysisService.shared.invalidatePage(source, documentId: documentId)
                            NotificationCenter.default.post(name: .aiPageRead,
                                                            object: DocumentScan.PageRead(documentId: documentId, page: source))
                        }
                        result.suggestions = OCRReferenceDiff.suggestions(ocr, reference: markdown)
                        Diagnostics.log("page \(source) : \(result.suggestions.count) différence(s)", "verif")
                        AITaskCenter.shared.log(id, "p. \(source + 1) : comparée à l'OCR, \(result.suggestions.count) différence(s)")
                    } catch {
                        result.error = error.localizedDescription
                        AITaskCenter.shared.log(id, "p. \(source + 1) : erreur — \(error.localizedDescription)")
                    }
                } else {
                    result.error = "Page pas encore lue par l'OCR."
                    AITaskCenter.shared.log(id, "p. \(source + 1) : pas encore lue par l'OCR, ignorée")
                }
                guard !Task.isCancelled else { break }
                self?.verifications.append(result)
                self?.verifyState = .running(done: k + 1, total: sources.count)
            }
        }
    }

    /// Arrêt confirmé deux fois (feuille de vérification). Le modèle est libéré par inactivité (`GLMModel`).
    func cancelVerification() {
        AITaskCenter.shared.cancel(key: verifyKey)
        verifyState = .idle
    }

    /// Propositions acceptées : chaque ligne prend le texte d'OvisOCR2 (marquée corrigée, comme à la main),
    /// **seulement** si elle n'a pas changé depuis la vérification. Appliquées à la suite, page relue à chaque fois.
    func acceptSuggestions(_ suggestions: [OCRReferenceDiff.Suggestion], source: Int) {
        guard let engine = verifications.first(where: { $0.source == source })?.engine else { return }
        suggestions.forEach { dropSuggestion($0, source: source) }
        let previous = acceptChain, documentId = document.id, service = model.ocr
        acceptChain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let live = source == self.focusSource && self.ocrPage?.engine == engine ? self.ocrPage : nil
            var found = live
            if found == nil { found = await service.cached(documentId: documentId, pageIndex: source, engine: engine) }
            guard var page = found else { return }
            var changed = false
            for s in suggestions where page.lines.indices.contains(s.line) {
                let now = page.lines[s.line].text.filter { !$0.isWhitespace }
                guard now == s.current.filter({ !$0.isWhitespace }) else { continue }  // changée entre-temps
                page.lines[s.line] = Self.corrected(page.lines[s.line], text: s.proposed)
                changed = true
            }
            guard changed else { return }
            do {
                try await service.store(page, documentId: documentId, pageIndex: source)
            } catch {
                self.loadError = "Correction non enregistrée : \(error.localizedDescription)"
                return
            }
            self.showOCR(page, source: source)
            if source == self.focusSource, self.ocrPage?.engine == engine { self.ocrPage = page }
            self.wordStartMemo.removeAll()
        }
    }

    func dropSuggestion(_ suggestion: OCRReferenceDiff.Suggestion, source: Int) {
        guard let i = verifications.firstIndex(where: { $0.source == source }) else { return }
        verifications[i].suggestions.removeAll { $0.line == suggestion.line }
    }

    static func corrected(_ line: OCRLine, text: String) -> OCRLine {
        line.acceptingCorrection(text)
    }

    /// Correction à la main d'une ligne (gardée : la relecture automatique n'y touche plus).
    func correctOCRLine(_ index: Int, text: String) {
        guard var page = ocrPage, page.lines.indices.contains(index) else { return }
        let new = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty else { return }
        var line = page.lines[index]
        if new.count != line.charBoxes.count {
            line.charBoxes = CharacterLayout.proportional(new, in: line.box, vertical: line.vertical)
            line.measuredCharBoxes = false
        }
        line.text = new
        line.edited = true
        line.doubt = []
        page.lines[index] = line
        ocrPage = page
        showOCR(page, source: focusSource)
        wordStartMemo.removeAll()
        let source = focusSource, documentId = document.id, service = model.ocr
        Task { try? await service.store(page, documentId: documentId, pageIndex: source) }
    }
}
