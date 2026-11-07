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
        if !keepFocus || !document.capabilities.textAnalysis { pageHasPDFText = false }
        pageTextTask?.cancel()
        if document.capabilities.textAnalysis {
            let url = fileURL
            pageTextTask = Task.detached(priority: .utility) { [weak self] in
                // Même règle que le toucher : un peu de texte suffit (folio, légende).
                let has = ActivityCenter.shared.measure(.pageText) { PDFTextEngine.hasTextLayer(url: url, pageIndex: source) }
                await MainActor.run {
                    guard !Task.isCancelled, self?.currentSourcePage == source else { return }
                    self?.pageHasPDFText = has
                }
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
                if let candidate = await self.candidateOCR(source: page) {
                    // Panneau gardé (même page, même moteur) : il ne revient pas en haut. Sinon il suit l'OCR retenu.
                    let keepPanel = keepFocus && self.ocrPage?.engine == candidate.page.engine
                    // Refusé : une intention plus récente (menu, réglage) affiche déjà sa propre lecture.
                    self.adoptOCR(candidate, source: page, updatePanel: !keepPanel)
                } else {
                    missing.append(page)
                }
            }
            // OCR automatique (réglage) ou furigana actifs : les pages visibles sans OCR sont lues.
            if !missing.isEmpty, self.model.appSettings.ocrAutoCurrentPage || self.pageFuriganaOn {
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

    /// Moteurs à essayer, dans l'ordre, pour lire le cache d'une page : règle unique `OCRSelectionPolicy` (moteur
    /// choisi pour la page, sinon réglage ; en Auto, la lecture déjà faite d'abord).
    func preferredEngines(source: Int) async -> [String] {
        let choice = settings.ocrEngine, pinned = pinnedEngines[source]
        let text = pinned == nil && choice == .auto ? await hasTextLayer(source: source) : false
        return OCRSelectionPolicy.cacheOrder(choice: choice, pinned: pinned, hasTextLayer: text)
    }

    /// Moteur d'une nouvelle lecture de la page, quand aucune lecture faite n'est réutilisable.
    func engineToRead(source: Int) async -> String {
        let choice = settings.ocrEngine, pinned = pinnedEngines[source]
        let text = pinned == nil && choice == .auto ? await hasTextLayer(source: source) : false
        return OCRSelectionPolicy.engineToRead(choice: choice, pinned: pinned, hasTextLayer: text, isInstalled: Self.isInstalled)
    }

    /// Vraie couche de texte (pas un scan avec image pleine page), hors du fil principal.
    func hasTextLayer(source: Int) async -> Bool {
        let url = fileURL
        return await Task.detached(priority: .utility) { PDFTextEngine.hasTextLayer(url: url, pageIndex: source) }.value
    }

    /// OCR de la page par un moteur autre que « texte du PDF » (celui du panneau, sinon le cache), sans effet sur la
    /// sélection.
    func realOCR(source: Int) async -> OCRPage? {
        if source == focusSource, let page = ocrPage { return page.engine == OCREngineID.pdfText ? nil : page }
        if let memo = realOCRMemo[source] { return memo }
        let found = await cachedOCR(source: source, excludingPDFText: true)
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

    /// Lecture déjà faite de la page, **sans effet** sur la sélection (toucher, surlignage, cartes, survol) : celle du
    /// moteur retenu si elle existe — ces gestes lisent alors la version affichée —, sinon celle de la règle.
    /// Lire n'adopte rien : seul `adoptOCR` change l'OCR retenu (revue Codex de d87e048, §3).
    func cachedOCR(source: Int, excludingPDFText: Bool = false) async -> OCRPage? {
        if let engine = selectedEngines[source], !(excludingPDFText && engine == OCREngineID.pdfText),
           let page = await model.ocr.cached(documentId: document.id, pageIndex: source, engine: engine) {
            return page
        }
        return await policyCachedOCR(source: source, excludingPDFText: excludingPDFText)
    }

    /// Lecture déjà faite que la règle unique retient : ordre `OCRSelectionPolicy.cacheOrder`, puis, en Auto sans choix
    /// pour la page, la version corrigée à la main d'abord (D7). Sans effet sur la sélection.
    private func policyCachedOCR(source: Int, excludingPDFText: Bool = false) async -> OCRPage? {
        let choice = settings.ocrEngine, pinned = pinnedEngines[source]
        var order = await preferredEngines(source: source)
        if excludingPDFText { order.removeAll { $0 == OCREngineID.pdfText } }
        let prioritize = OCRSelectionPolicy.prioritizesCorrections(choice: choice, pinned: pinned)
        var found: [OCRPage] = []
        for engine in order {
            guard let page = await model.ocr.cached(documentId: document.id, pageIndex: source, engine: engine) else { continue }
            found.append(page)
            // Sans priorité des corrections, la première lecture suffit ; avec, il faut savoir si une suivante est corrigée.
            if !prioritize { break }
        }
        return OCRSelectionPolicy.retained(among: found, prioritizingCorrections: prioritize)
    }

    /// Lecture déjà faite à adopter comme OCR retenu, avec le ticket pris **avant** les attentes. Ne préfère pas le
    /// moteur déjà retenu : un nouveau cache valide (ou une correction) peut être reconsidéré, de façon atomique.
    func candidateOCR(source: Int) async -> OCRCandidate? {
        let ticket = ocrSelection.ticket(for: source)
        return await policyCachedOCR(source: source).map { OCRCandidate(page: $0, ticket: ticket) }
    }

    /// OCR retenu de la page : lecture déjà faite selon la règle unique, sinon nouvelle lecture par le moteur de la
    /// règle. Le ticket est pris avant l'attente : `adoptOCR` écartera le résultat si une intention plus récente existe.
    func selectedOCR(source: Int) async throws -> OCRCandidate {
        let ticket = ocrSelection.ticket(for: source)
        if let cached = await policyCachedOCR(source: source) { return OCRCandidate(page: cached, ticket: ticket) }
        let engine = await engineToRead(source: source)
        let page = try await model.ocr.page(documentId: document.id, url: fileURL, pageIndex: source, engine: engine)
        return OCRCandidate(page: page, ticket: ticket)
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
        let service = model.ocr
        // Moteur demandé (menu du panneau, « Relancer ») : retenu pour cette page (décision D2), il gagne sur le cache.
        // Nouvelle intention : les lectures encore en cours pour la page deviennent périmées (revue Codex, R1).
        if let engine {
            // « Relancer » (force) relit le même moteur : ce n'est pas un nouveau choix pour la page.
            if force { ocrSelection.retain(engine, source: source) } else { ocrSelection.pin(engine, source: source) }
        } else if force {
            ocrSelection.invalidate(source)
        }
        // Pris après l'intention, avant toute attente.
        let ticket = ocrSelection.ticket(for: source)
        ocrState = .running
        ocrTask = Task { [weak self] in
            let engineID = engine ?? "auto"
            do {
                guard let reader = self else { return }
                var candidate: OCRCandidate
                if let engine {
                    let page = try await service.page(documentId: documentId, url: url, pageIndex: source, engine: engine, force: force)
                    candidate = OCRCandidate(page: page, ticket: ticket)
                } else if force {
                    let id = await reader.engineToRead(source: source)
                    let page = try await service.page(documentId: documentId, url: url, pageIndex: source, engine: id, force: true)
                    candidate = OCRCandidate(page: page, ticket: ticket)
                } else {
                    // « Lire la page », ouverture du panneau : même règle que la page posée (lecture faite d'abord).
                    candidate = try await reader.selectedOCR(source: source)
                }
                guard let self, !Task.isCancelled else { return }
                if self.focusSource == source { self.ocrState = .idle }
                // Chaque lecture demandée (même en cache) : caractères douteux revérifiés (`refineOCR`).
                candidate.page.proofread = false
                // Refusé (intention plus récente) : ni zones, ni furigana, ni panneau (revue Codex, R2).
                guard self.adoptOCR(candidate, source: source), self.focusSource == source else { return }
                // Même texte qu'avant : `ocrPage` ne relance rien tout seul.
                self.refineOCR()
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
        guard document.capabilities.textAnalysis else { throw CancellationError() }
        return try await model.ocr.page(documentId: document.id, url: fileURL, pageIndex: focusSource, engine: engine)
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
            // Adoption complète : panneau, zones et furigana de la page choisie suivent la même lecture.
            if let candidate = await self.candidateOCR(source: source) {
                self.adoptOCR(candidate, source: source)
            } else if self.model.appSettings.ocrAutoCurrentPage || self.pageFuriganaOn {
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
        ensureTask = Task { [weak self] in
            defer { self?.ensureTask = nil; self?.ensuringPage = nil }
            while let self, !Task.isCancelled, !self.ensureQueue.isEmpty {
                let source = self.ensureQueue.removeFirst()
                self.ensuringPage = source
                guard self.shownSources.contains(source) else { continue }
                if source == self.focusSource { self.ocrState = .running }
                do {
                    // Même règle que la page posée : une lecture déjà faite (même d'un modèle absent) d'abord.
                    let candidate = try await self.selectedOCR(source: source)
                    if source == self.focusSource { self.ocrState = .idle }
                    // Une lecture lancée avant un choix explicite est refusée en entier (revue Codex, R2).
                    self.adoptOCR(candidate, source: source)
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
            // Même moteur que le panneau : affiché seulement s'il est encore l'OCR retenu de la page de travail.
            guard self.focusSource == source, self.showOCR(read, source: source) else { return }
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
            guard self.showOCR(cached, source: source) else { return }
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
            guard let self, !self.closed, self.showOCR(read, source: source) else { return }
            if self.focusSource == source { self.ocrPage = read }
        }
    }
}
