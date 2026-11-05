// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import GLMOCRKit
import OCRKit
import PDFKit
import PencilKit
import ReaderCore
import UIKit

/// `ReaderController` : OCR de la page, relecture des lignes douteuses.
extension ReaderController {
    // MARK: OCR

    /// Page stable depuis un instant : OCR en cache affiché, OCR auto si demandé. `samePageKeeps` : page courante
    /// inchangée et page de travail encore visible (glisser, zoom, bord de la page voisine) → `focusSource` et
    /// `ocrPage` gardés : le panneau ne revient pas en haut.
    func schedulePageSettled(samePageKeeps: Bool = false) {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let visible = self.visibleSources()
            if let pinned = self.pinnedFocus, !visible.contains(pinned) { self.pinnedFocus = nil }
            // Page choisie dans le panneau : gardée tant qu'elle est à l'écran, même si on regarde l'autre.
            let keep = samePageKeeps && visible.contains(self.focusSource)
                && (self.pinnedFocus == self.focusSource || self.currentSourcePage == self.settledSource)
            self.pageSettled(keepFocus: keep)
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }


    func pageSettled(keepFocus: Bool = false) {
        ink.showOCRBoxes = model.appSettings.showOCRBoxes
        if !keepFocus {
            ocrPage = nil
            ocrState = .idle
        }
        let source = currentSourcePage
        settledSource = source
        // Miniatures voisines et test « la page a du texte » seulement une fois la page posée
        // (pas à chaque page qui défile).
        preloadThumbnails(around: source)
        ink.trim(around: source)
        if !keepFocus { pageHasPDFText = false }
        pageTextTask?.cancel()
        let url = fileURL
        pageTextTask = Task.detached(priority: .utility) { [weak self] in
            // Même règle que le toucher : un peu de texte suffit (folio, légende).
            let has = PDFTextEngine.hasTextLayer(url: url, pageIndex: source)
            await MainActor.run {
                guard !Task.isCancelled, self?.currentSourcePage == source else { return }
                self?.pageHasPDFText = has
            }
        }
        let visible = visibleSources()
        // Nouvelle page : la file d'OCR de l'ancienne ne sert plus.
        if visible != shownSources { cancelEnsureOCR() }
        if shownSources != visible { shownSources = visible }
        if !keepFocus { focusSource = pinnedFocus.flatMap { visible.contains($0) ? $0 : nil } ?? source }
        scheduleTone(visible)
        guard document.capabilities.textAnalysis else { return } // Lecture visuelle : ni nettoyage, ni furigana, ni OCR.
        scheduleSharpening(visible)
        scheduleFurigana(visible)
                Task { [weak self] in
            guard let self else { return }
            // Zones en cache pour toutes les pages visibles (double page).
            var missing: [Int] = []
            for page in visible {
                if let cached = await self.cachedOCR(source: page) {
                    self.showOCR(cached, source: page)
                    if page == self.focusSource, !keepFocus || self.ocrPage == nil { self.ocrPage = cached }
                } else {
                    missing.append(page)
                }
            }
            // OCR automatique (réglage) ou furigana actifs : les pages visibles sans OCR sont lues.
            if !missing.isEmpty, self.model.appSettings.ocrAutoCurrentPage || FuriganaLayer.enabled {
                self.ensureOCR(missing)
            }
        }
    }

    /// Pages affichées. Double page : la planche entière compte, même zoomée sur une seule page (sinon la page
    /// choisie dans le panneau disparaissait de la liste et le panneau retombait sur l'autre).
    func visibleSources() -> [Int] {
        guard let pdf else { return [currentSourcePage] }
        var indices = pdfView.visiblePages.map { pdf.index(for: $0) }.filter { presented.indices.contains($0) }
        if settings.layout == .double { indices = indices.flatMap(spread(of:)) }
        let sources = indices.filter { presented.indices.contains($0) }.map { presented[$0].source }
        return Array(Set(sources)).sorted()
    }

    /// Les pages de la planche (double page) qui contient `index` : (0,1), (2,3)… ou, en livre, 0 seule puis (1,2)…
    func spread(of index: Int) -> [Int] {
        if pdfView.displaysAsBook {
            guard index > 0 else { return [0] }
            let first = (index - 1) / 2 * 2 + 1
            return [first, first + 1]
        }
        let first = index / 2 * 2
        return [first, first + 1]
    }

    /// Moteurs à essayer, dans l'ordre, pour lire le cache d'une page.
    func preferredEngines() -> [String] {
        switch settings.ocrEngine {
        case .pdfText: return [OCREngineID.pdfText]
        case .vision: return [OCREngineID.vision]
        case .ndlocr: return [OCREngineID.ndlocr]
        case .ppocr5: return [OCREngineID.ppocr5]
        case .glmocr: return [OCREngineID.glmocr]
        case .auto: return [OCREngineID.pdfText, OCREngineID.ndlocr, OCREngineID.ppocr5, OCREngineID.vision]
        }
    }

    /// OCR de la page par un moteur autre que « texte du PDF » (celui du panneau, sinon le cache).
    func realOCR(source: Int) async -> OCRPage? {
        if source == focusSource, let page = ocrPage { return page.engine == OCREngineID.pdfText ? nil : page }
        if let memo = realOCRMemo[source] { return memo }
        var found: OCRPage?
        for engine in preferredEngines() where engine != OCREngineID.pdfText {
            if let page = await model.ocr.cached(documentId: document.id, pageIndex: source, engine: engine) { found = page; break }
        }
        realOCRMemo[source] = .some(found)
        return found
    }

    /// Début du mot du dictionnaire qui contient le caractère `offset` de `text` (plus long mot à chaque
    /// position, comme le panneau d'étude). Sans dictionnaire : le caractère lui-même.
    func wordStart(in text: String, at offset: Int) async -> Int {
        let starts: [Int]
        if let memo = wordStartMemo[text] {
            starts = memo
        } else {
            let segments = await model.dictionary.segment(text)
            starts = FuriganaTextView.wordStarts(text, segments: segments) ?? Array(0..<text.count)
            if wordStartMemo.count > 300 { wordStartMemo.removeAll() }
            wordStartMemo[text] = starts
        }
        return starts.indices.contains(offset) ? min(starts[offset], offset) : offset
    }

    func cachedOCR(source: Int) async -> OCRPage? {
        // Un ancien cache « Texte du PDF » ne doit pas bloquer l'OCR d'une page photo devenue identifiable comme
        // scan (le PDF du scanner peut contenir une couche OCR cachée).
        let skipPDFText: Bool
        if settings.ocrEngine == .auto {
            let url = fileURL
            skipPDFText = await Task.detached(priority: .utility) {
                !PDFTextEngine.hasTextLayer(url: url, pageIndex: source)
            }.value
        } else {
            skipPDFText = false
        }
        for engine in preferredEngines() {
            if engine == OCREngineID.pdfText && skipPDFText { continue }
            if let page = await model.ocr.cached(documentId: document.id, pageIndex: source, engine: engine) { return page }
        }
        return nil
    }

    /// Lance l'OCR de la page lue (en tâche de fond ; le cache évite de refaire).
    /// - Parameters:
    ///   - engine: moteur imposé (sinon : réglage du document, « auto » résolu selon la page).
    ///   - force: ignore le cache (bouton « Relancer »).
    func runOCR(engine: String? = nil, force: Bool = false) {
        guard document.capabilities.textAnalysis else { return }
        ocrTask?.cancel()
        let source = focusSource
        let url = fileURL
        let documentId = document.id
        let choice = settings.ocrEngine
        let service = model.ocr
        ocrState = .running
        ocrTask = Task { [weak self] in
            let engineID: String
            if let engine {
                engineID = engine
            } else {
                engineID = await Task.detached(priority: .userInitiated) {
                    OCRService.resolve(choice, url: url, pageIndex: source)
                }.value
            }
            do {
                var page = try await service.page(documentId: documentId, url: url, pageIndex: source, engine: engineID, force: force)
                guard let self, !Task.isCancelled else { return }
                // Chaque lecture demandée (même en cache) : caractères douteux revérifiés (`refineOCR`).
                page.proofread = false
                self.showOCR(page, source: source)
                if self.focusSource == source {
                    self.ocrPage = page
                    self.ocrState = .idle
                    // Même texte qu'avant : `ocrPage` ne relance rien tout seul.
                    self.refineOCR()
                }
            } catch is CancellationError {
                return
            } catch {
                Diagnostics.error("OCR \(engineID) p. \(source) : \(error.localizedDescription)", "ocr")
                guard let self, self.focusSource == source else { return }
                self.ocrState = .failed(error.localizedDescription)
            }
        }
    }

    /// OCR d'une page avec un moteur précis (comparaison), sans changer la page affichée.
    func ocr(engine: String) async throws -> OCRPage {
        try await model.ocr.page(documentId: document.id, url: fileURL, pageIndex: focusSource, engine: engine)
    }

    /// Pilule du panneau : travailler sur l'autre page affichée (double page).
    func focus(_ source: Int) {
        guard source != focusSource, shownSources.contains(source) else { return }
        pinnedFocus = source
        ocrTask?.cancel()
        focusSource = source
        ocrPage = nil
        ocrState = .idle
        Task { [weak self] in
            guard let self else { return }
            if let cached = await self.cachedOCR(source: source) {
                if self.focusSource == source { self.ocrPage = cached }
            } else if self.model.appSettings.ocrAutoCurrentPage || FuriganaLayer.enabled {
                self.ensureOCR([source])
            }
        }
    }

    /// Lit en fond les pages données qui n'ont pas encore d'OCR (moteur du document), une à la fois :
    /// une seule file, vidée quand la page change ou que le lecteur se ferme.
    func ensureOCR(_ pages: [Int]) {
        guard document.capabilities.textAnalysis else { return }
        for page in pages where !ensureQueue.contains(page) && ensuringPage != page { ensureQueue.append(page) }
        guard ensureTask == nil, !ensureQueue.isEmpty else { return }
        let url = fileURL, documentId = document.id, choice = settings.ocrEngine, service = model.ocr
        ensureTask = Task { [weak self] in
            defer { self?.ensureTask = nil; self?.ensuringPage = nil }
            while let self, !Task.isCancelled, !self.ensureQueue.isEmpty {
                let source = self.ensureQueue.removeFirst()
                self.ensuringPage = source
                guard self.shownSources.contains(source) else { continue }
                if source == self.focusSource { self.ocrState = .running }
                let engine = await Task.detached(priority: .userInitiated) {
                    OCRService.resolve(choice, url: url, pageIndex: source)
                }.value
                do {
                    let page = try await service.page(documentId: documentId, url: url, pageIndex: source, engine: engine)
                    self.showOCR(page, source: source)
                    if source == self.focusSource { self.ocrPage = page; self.ocrState = .idle }
                } catch {
                    if source == self.focusSource { self.ocrState = .failed(error.localizedDescription) }
                }
            }
        }
    }

    func cancelEnsureOCR() {
        ensureQueue = []
        ensureTask?.cancel()
        ensureTask = nil
    }

    func setShowOCRBoxes(_ on: Bool) {
        model.appSettings.showOCRBoxes = on
        ink.showOCRBoxes = on
        if on { pageSettled() }
    }

    /// Les tâches IA (relecture, vérification, mise en page, traduction) continuent : elles sont à `AITaskCenter`.
    func close() {
        savePositionWork?.perform()
        cropTask?.cancel()
        sharpenTask?.cancel()
        toneTask?.cancel()
        ToneCache.clear()
        furiganaTask?.cancel()
        pageFuriganaTasks.values.forEach { $0.cancel() }
        pageFuriganaTasks.removeAll()
        for page in furiganaGeneration.keys { furiganaGeneration[page, default: 0] += 1 }
        cancelEnsureOCR()
        ocrTask?.cancel()
        documentOCRTask?.cancel()
        settleWork?.cancel()
        ink.flush()
        pdf?.cancelFindString()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        // Libère tout de suite le PDF (et ses pages copiées) au lieu d'attendre la fin de la vue.
        pageTextTask?.cancel()
        buildTask?.cancel()
        closed = true
        pdfView.document = nil
        pdf = nil
        pageStringCache = nil
        let url = fileURL
        DispatchQueue.global(qos: .utility).async { PDFPool.release(url) }
    }

    // MARK: Relecture de l'OCR

    static let aiRereadKey = "ocr.aiReread"
    /// Relecture IA en cours sur la page de travail (vue : observer aussi `AITaskCenter.shared`).
    var rereading: Bool { AITaskCenter.shared.isRunning(prefix: rereadKey(focusSource)) }
    /// Préfixe des relectures d'une page ; la clé complète ajoute la version du résultat OCR relu.
    func rereadKey(_ source: Int) -> String { "reread|\(document.id)|\(source)|" }

    /// Page de travail : relecture par le dictionnaire si pas encore faite (pages en cache d'avant, dictionnaire
    /// chargé après l'OCR, nouvel OCR), puis caractères qui diffèrent du texte d'OvisOCR2 (s'il a lu la page) marqués
    /// douteux, puis lignes douteuses à GLM-OCR. Rejouable : sans changement, rien n'est réécrit.
    func refineOCR() {
        guard let page = ocrPage, page.engine != OCREngineID.pdfText else { return }
        let source = focusSource, documentId = document.id, service = model.ocr
        let process = AppModel.proofreader(model.dictionary)
        Task { [weak self] in
            var read = page.proofread == true ? page : await process(page)
            // Pas de dictionnaire : la page reste « non relue » (réessayée plus tard), le contrôle par l'IA a lieu.
            let proofreadFailed = read.proofread != true
            if let reference = DocumentAITextStore.read(documentId: documentId, reader: ModelSpec.ovisocr2.id, page: source) {
                read = OCRReferenceDiff.markDifferences(read, reference: reference)
            }
            guard let self, self.ocrPage == page else { return }
            guard read != page else { self.rereadDoubtful(); return }
            if !proofreadFailed { try? await service.store(read, documentId: documentId, pageIndex: source) }
            self.showOCR(read, source: source)
            self.ocrPage = read
            if proofreadFailed { self.rereadDoubtful() }
        }
    }

    /// Nouvelle lecture de la page de travail par l'IA (scan, vérification, mise en page) : doutes revérifiés.
    func recheckDoubtsAfterAIRead(page source: Int) {
        guard !closed, source == focusSource else { return }
        refineOCR()
    }

    /// Résultat écrit en cache par une tâche IA pour la page affichée (même moteur) : affiché.
    func reloadOCRAfterAITask() {
        guard !closed, let shown = ocrPage else { return }
        ocrReloadRevision &+= 1
        let revision = ocrReloadRevision
        let source = focusSource, documentId = document.id, service = model.ocr
        Task { [weak self] in
            guard let cached = await service.cached(documentId: documentId, pageIndex: source, engine: shown.engine),
                  cached != shown, let self, !self.closed, self.ocrReloadRevision == revision, self.focusSource == source, self.ocrPage == shown else { return }
            self.showOCR(cached, source: source)
            self.ocrPage = cached
            self.wordStartMemo.removeAll()
            Diagnostics.log("Cache OCR affiché : p. \(source + 1), lignes à revoir=\(OCRProofreader.doubtful(cached).count)", "ocr-ui")
        }
    }

    /// Lignes douteuses de la page de travail relues par GLM-OCR (installé, option active ou demande directe).
    func rereadDoubtful(force: Bool = false) {
        guard let page = ocrPage, page.engine != OCREngineID.pdfText, force || page.reread != true else { return }
        guard force || UserDefaults.standard.object(forKey: Self.aiRereadKey) as? Bool ?? true else { return }
        let engine = GLMOCREngine()
        let lines = OCRProofreader.doubtful(page)
        guard engine.isAvailable, !lines.isEmpty else { return }
        // Tâche de l'app (continue si on change de page ou ferme le lecteur). Même version déjà en cours : rien
        // (le lecteur se met à jour à la fin, cf. `AITaskCenter.finished`). Autre version : l'ancienne est remplacée.
        let source = focusSource, url = fileURL, documentId = document.id, service = model.ocr
        let key = rereadKey(source) + String(page.hashValue)
        guard !AITaskCenter.shared.isRunning(key) else { return }
        AITaskCenter.shared.cancel(prefix: rereadKey(source))
        AITaskCenter.shared.run(key, title: String(localized: "Relecture GLM-OCR p. \(source + 1)"), modelId: ModelSpec.glmocr.id, activity: "relecture") { [weak self] id in
            AITaskCenter.shared.log(id, String(localized: "GLM-OCR relit \(lines.count) ligne(s) douteuse(s) de la page \(source + 1)…"))
            let rotation = await service.additionalRotation(documentId: documentId, pageIndex: source)
            let read = try await Diagnostics.measure("GLM-OCR relit \(lines.count) ligne(s) p. \(source)", "relecture") {
                try await engine.reread(page, lines: lines,
                                        input: .pdfPage(url: url, index: source, additionalRotation: rotation))
            }
            try Task.checkCancellation()
            // Page changée entre-temps (correction à la main, autre OCR) : résultat jeté.
            let shown = self.flatMap { $0.focusSource == source && !$0.closed ? $0.ocrPage : nil }
            let current = shown == nil ? await service.cached(documentId: documentId, pageIndex: source, engine: page.engine) : shown
            guard current == nil || current == page else {
                AITaskCenter.shared.log(id, String(localized: "Page modifiée entre-temps : relecture jetée"))
                return
            }
            AITaskCenter.shared.log(id, String(localized: "Relecture enregistrée"))
            try? await service.store(read, documentId: documentId, pageIndex: source)
            guard let self, !self.closed else { return }
            self.showOCR(read, source: source)
            if self.focusSource == source { self.ocrPage = read }
        }
    }
}
