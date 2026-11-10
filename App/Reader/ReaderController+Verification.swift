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
        let focused = focusSource, focusedPage = ocrPage
        verifications = []
        verifyState = .running(done: 0, total: sources.count)
        // Tâche de l'app : continue si on change de page ou ferme le lecteur (le Markdown lu reste gardé).
        AITaskCenter.shared.run(verifyKey, title: String(localized: "Vérification OvisOCR2"), modelId: ModelSpec.ovisocr2.id, activity: "vérification") { [weak self] id in
            defer { if let self, case .running = self.verifyState { self.verifyState = Task.isCancelled ? .idle : .done } }
            for (k, source) in sources.enumerated() {
                AITaskCenter.shared.setProgress(id, done: k, total: sources.count)
                guard !Task.isCancelled else { break }
                var result = PageVerification(source: source, suggestions: [])
                // Lecteur fermé entre-temps : on continue avec ce qui a été noté au départ (le Markdown est gardé).
                var ocr: OCRPage? = source == focused ? focusedPage : nil
                // Même règle que le lecteur (OCR retenu de la page) ; lecteur fermé : ordre Auto des lectures faites.
                let engines = await self?.preferredEngines(source: source)
                    ?? OCRSelectionPolicy.cacheOrder(choice: .auto, pinned: nil, hasTextLayer: false)
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
                            AITaskCenter.shared.log(id, String(localized: "p. \(source + 1) : lecture OvisOCR2 déjà faite, réutilisée"))
                        } else {
                            AITaskCenter.shared.log(id, String(localized: "p. \(source + 1) : OvisOCR2 lit la page (≈ 20 à 40 s)…"))
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
                        AITaskCenter.shared.log(id, String(localized: "p. \(source + 1) : comparée à l'OCR, \(result.suggestions.count) différence(s)"))
                    } catch {
                        result.error = error.localizedDescription
                        AITaskCenter.shared.log(id, String(localized: "p. \(source + 1) : erreur — \(error.localizedDescription)"))
                    }
                } else {
                    result.error = String(localized: "Page pas encore lue par l'OCR.")
                    AITaskCenter.shared.log(id, String(localized: "p. \(source + 1) : pas encore lue par l'OCR, ignorée"))
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
            // Génération des pages au début : une suggestion ne s'écrit pas sur une page déplacée entre-temps (étape 2).
            let generation = await service.generation(documentId: documentId)
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
                try await service.store(page, documentId: documentId, pageIndex: source, expectedGeneration: generation)
            } catch {
                self.loadError = String(localized: "Correction non enregistrée : \(error.localizedDescription)")
                return
            }
            if self.showOCR(page, source: source) {
                if source == self.focusSource, self.ocrPage?.engine == engine { self.ocrPage = page }
            } else if !self.closed, let candidate = await self.candidateOCR(source: source) {
                // D7 et décision F4 : la version corrigée passe d'abord, même face au moteur réglé ou choisi dans le menu ;
                // affichée dès l'acceptation et non au geste suivant (contre-revue Codex de 51f8a2d, F3).
                self.adoptOCR(candidate, source: source)
            }
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

    /// Ancien dialogue de correction : même garde de session que l'éditeur complet, sur le MainActor.
    /// Une page ou une lecture remplacée pendant la saisie ne reçoit jamais un index devenu périmé.
    func correctOCRLine(_ index: Int, text: String, original: OCRPage, source: Int) {
        // Alerte qu'on referme : `loadError` resterait affiché sur la page jusqu'à la fermeture du livre.
        if !correctOCRLines([index: text], ifStill: original, source: source) {
            model.lastError = String(localized: "Le texte de cette page a changé pendant ta correction : rien n'a été enregistré. Ferme cet écran et recommence.")
        }
    }

    /// Refuse si la page affichée ou son résultat OCR a changé depuis `original` : une relecture peut insérer ou
    /// réordonner des lignes, et le même numéro désignerait alors un autre texte (revue Codex de la 75).
    @discardableResult
    func correctOCRLines(_ corrections: [Int: String], ifStill original: OCRPage, source: Int) -> Bool {
        guard ocrUnchanged(since: original, source: source) else { return false }
        correctOCRLines(corrections)
        return true
    }

    func ocrUnchanged(since original: OCRPage, source: Int) -> Bool {
        // Le panneau doit aussi être l'OCR retenu : sinon la correction changerait le panneau sans les zones.
        guard source == focusSource, let current = ocrPage, current.engine == original.engine,
              selectedEngines[source] == current.engine else { return false }
        return current.lines.map(\.text) == original.lines.map(\.text)
    }

    /// Plusieurs lignes en une seule écriture : des écritures séparées pourraient se terminer dans le désordre.
    /// Refusée si le panneau n'est pas l'OCR retenu de la page (contre-revue Codex de 51f8a2d, F2) : panneau et zones
    /// changeraient de version l'un sans l'autre.
    func correctOCRLines(_ corrections: [Int: String]) {
        guard var page = ocrPage, selectedEngines[focusSource] == page.engine else { return }
        var changed = false
        for (index, text) in corrections where page.lines.indices.contains(index) {
            let new = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !new.isEmpty else { continue }
            page.lines[index] = page.lines[index].acceptingCorrection(new)
            changed = true
        }
        guard changed, showOCR(page, source: focusSource) else { return }
        ocrPage = page
        wordStartMemo.removeAll()
        let source = focusSource, documentId = document.id, service = model.ocr
        // C2.5 : génération relue juste avant l'écriture, comme les autres voies (`acceptSuggestions`, relecture) —
        // une correction ne doit pas s'installer sur une page déplacée ou relue entre-temps.
        Task {
            let generation = await service.generation(documentId: documentId)
            do {
                try await service.store(page, documentId: documentId, pageIndex: source, expectedGeneration: generation)
            } catch {
                // P3 n°5 (revue R2) : le refus de la garde est publié, jamais avalé — le panneau montrait
                // déjà la correction, elle aurait été perdue sans un mot.
                self.loadError = String(localized: "Correction non enregistrée : \(error.localizedDescription)")
            }
        }
    }

    /// Enregistre à côté de la lecture d'OvisOCR2, jamais à sa place, et rafraîchit l'affichage sans relancer le modèle.
    func saveOvisCorrection(_ text: String, source: Int) {
        do {
            try DocumentAITextStore.writeCorrection(text, documentId: document.id, page: source)
            NotificationCenter.default.post(name: .aiPageRead, object: DocumentScan.PageRead(documentId: document.id, page: source))
        } catch {
            model.lastError = String(localized: "Correction non enregistrée : \(error.localizedDescription)")
        }
    }

    var hasCorrections: Bool {
        DocumentAITextStore.hasCorrection(documentId: document.id, page: focusSource)
            || ocrPage?.lines.contains { $0.originalText != nil } == true
    }

    /// Retour à ce que l'OCR et OvisOCR2 avaient lu sur la page affichée, sans rien relancer.
    func undoCorrections() {
        let source = focusSource
        if var page = ocrPage, page.lines.contains(where: { $0.originalText != nil }) {
            page.lines = page.lines.map(\.revertingCorrection)
            // Même contrôle que les corrections (F2) : panneau et zones changent ensemble, ou rien n'est écrit.
            guard showOCR(page, source: source) else {
                model.lastError = String(localized: "Le texte de cette page a changé : rien n'a été annulé. Ferme cet écran et recommence.")
                return
            }
            ocrPage = page
            wordStartMemo.removeAll()
            let documentId = document.id, service = model.ocr
            // C2.5 : même garde de génération que les autres voies (annulation des corrections comprises).
            Task {
                let generation = await service.generation(documentId: documentId)
                do {
                    try await service.store(page, documentId: documentId, pageIndex: source, expectedGeneration: generation)
                } catch {
                    // P3 n°5 (revue R2) : même publication que les corrections — un refus ne se perd plus en
                    // silence pendant que l'affichage montre déjà la page revenue en arrière.
                    self.loadError = String(localized: "Correction non enregistrée : \(error.localizedDescription)")
                }
            }
        }
        DocumentAITextStore.removeCorrection(documentId: document.id, page: source)
        NotificationCenter.default.post(name: .aiPageRead, object: DocumentScan.PageRead(documentId: document.id, page: source))
    }
}
