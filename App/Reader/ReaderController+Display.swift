// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import GLMOCRKit
import OCRKit
import PDFKit
import PencilKit
import ReaderCore
import UIKit

/// `ReaderController` : réglages d'affichage, netteté des scans, furigana.
extension ReaderController {
    // MARK: Réglages

    func applyDisplaySettings(refit: Bool = false) {
        let viewport = refit ? nil : pdfView.captureViewport()
        let s = settings
        let paginated = s.scrollMode == .paginated
        let double = s.layout == .double
        let rtl = s.direction == .rightToLeft

        // Le contrôleur de pages de PDFKit (glissement entre pages) ne gère que la page simple.
        let pageController = paginated && !double && s.transition == .slide
        if pdfView.isUsingPageViewController != pageController {
            pdfView.usePageViewController(pageController, withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 24])
        }
        let mode: PDFDisplayMode
        switch (double, paginated) {
        case (false, true): mode = .singlePage
        case (false, false): mode = .singlePageContinuous
        case (true, true): mode = .twoUp
        case (true, false): mode = .twoUpContinuous
        }
        if pdfView.displayMode != mode { pdfView.displayMode = mode }
        tuneDoublePageGestures(double: double, paginated: paginated, pageController: pageController)
        pdfView.displayDirection = paginated ? .horizontal : .vertical
        pdfView.displaysAsBook = double && s.firstPageAlone
        pdfView.displaysRTL = rtl && !double
        pdfView.displaysPageBreaks = true
        pdfView.pageBreakMargins = paginated ? .zero : UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        pdfView.pageShadowsEnabled = s.background != .black
        applyTone()
        pdfView.finishLayout(preserving: viewport)
        // Sans contrôleur de pages, PDFKit ne tourne pas les pages au glisser : on le fait nous-mêmes.
        let manualSwipe = paginated && !pageController && !isDrawing
        swipeLeft.isEnabled = manualSwipe
        swipeRight.isEnabled = manualSwipe
        doubleTap.isEnabled = s.doubleTapZoom && !isDrawing
        singleTap.isEnabled = !isDrawing
        if s.doubleTapZoom {
            singleTap.require(toFail: doubleTap)
        }
    }

    /// Double page : déplacement libre et zoom au toucher fiables (RET-043, Issue #63).
    ///
    /// Sans contrôleur de pages, PDFKit met les deux pages dans un seul `PDFScrollView`, réglé par défaut avec
    /// `isDirectionalLockEnabled = true` (déplacement bloqué sur l'axe du début du geste) et un pan qui accepte
    /// deux doigts : deux doigts posés devenaient un déplacement et le pincement ne démarrait pas. Mesuré sur
    /// iPad avec les candidates de diagnostic 2d à 2g (journaux `[gestes-2e]`) : verrou coupé et pan limité à
    /// un doigt, le pincement démarre à chaque geste à deux doigts, et il fait déjà suivre la page sous les
    /// doigts. Ailleurs, les réglages relevés de PDFKit sont rétablis.
    func tuneDoublePageGestures(double: Bool, paginated: Bool, pageController: Bool) {
        guard !pageController, let scroll = pdfInnerScrollView else { return }
        // Réglage mesuré en double page paginée (le cas observé par NOxygen59) ; le reste garde le comportement de PDFKit.
        let tuned = double && paginated
        scroll.isDirectionalLockEnabled = !tuned
        scroll.panGestureRecognizer.maximumNumberOfTouches = tuned ? 1 : 2
    }

    /// Applique de nouveaux réglages (globaux ou du document). Reconstruit si la structure change.
    // MARK: Netteté des scans (DE-GAN)

    /// Pages visibles scannées : version nettoyée préparée en tâche de fond, puis redessinées.
    func scheduleSharpening(_ pages: [Int]) {
        sharpenTask?.cancel()
        guard ScanSharpening.enabled else { return }
        let url = fileURL, id = document.id
        sharpenTask = Task.detached(priority: .utility) { [weak self] in
            var changed = false
            for page in pages {
                guard !Task.isCancelled else { return }
                // Page avec du texte intégré (PDF numérique) : déjà nette, rien à faire.
                guard !PDFTextEngine.hasTextLayer(url: url, pageIndex: page) else { continue }
                let key = ScanSharpening.key(documentId: id, page: page)
                if (try? ScanSharpening.prepare(key: key, fileURL: url, page: page)) == true { changed = true }
            }
            guard changed, !Task.isCancelled else { return }
            await self?.pdfView.redrawVisiblePages()
        }
    }

    // MARK: Furigana

    /// Zones OCR affichées (+ furigana du scan si l'option est active et la page sans texte intégré).
    func showOCR(_ ocr: OCRPage, source: Int) {
        realOCRMemo[source] = nil
        ink.setOCR(ocr, source: source)
        guard FuriganaLayer.enabled else { return }
        // Un moteur OCR explicite fournit les boîtes du scan même si le scanner a ajouté une couche texte PDF.
        // La couche PDF est traitée séparément par `scheduleFurigana`.
        guard ocr.engine != OCREngineID.pdfText else { return }
        let key = ScanSharpening.key(documentId: document.id, page: source), url = fileURL
        // Calculs lancés l'un après l'autre pour la même page : seul le dernier est gardé.
        furiganaGeneration[source, default: 0] += 1
        let generation = furiganaGeneration[source, default: 0]
        // Texte d'OvisOCR2 (scan à l'import, vérification, mise en page IA) : lectures d'après lui.
        let documentId = document.id
        let translator = model.dictionary.translator
        let lookupOptions = model.dictionary.lookupOptions
        let additionalRotation = transforms[source]?.rotation ?? 0
        pageFuriganaTasks[source]?.cancel()
        pageFuriganaTasks[source] = Task.detached(priority: .utility) { [weak self] in
            // `PDFPool` lit le fichier d'origine, sans l'orientation choisie ; les boîtes OCR, elles, en tiennent compte.
            let frame: PageFrame? = (try? PDFPool.withDocument(url) { doc -> PageFrame? in
                doc.page(at: source).map {
                    PageFrame(box: $0.bounds(for: .cropBox),
                              rotation: PageTransform.effectiveRotation(intrinsic: $0.rotation, additional: additionalRotation))
                }
            }) ?? nil
            guard let frame else { return }
            let reference = DocumentAITextStore.read(documentId: documentId, reader: ModelSpec.ovisocr2.id, page: source)
            // Même choix de lectures que dans le panneau OCR : MeCab si présent, sinon le dictionnaire.
            // Une page scannée sans couche texte doit bénéficier des mots déjà reconnus dans le panneau.
            let marks = FuriganaLayer.marks(from: ocr, reference: reference, frame: frame) { text in
                let segments = Furigana.analyzer == nil
                    ? (translator.flatMap { try? $0.segment(text, options: lookupOptions) } ?? []) : []
                return TextFurigana.rubies(text, segments: segments)
            }
            Diagnostics.log("Furigana p. \(source + 1) : \(ocr.engine), \(ocr.lines.count) lignes OCR, "
                            + "texte Ovis \(reference?.count ?? 0) caractères, \(marks.count) lectures", "furigana")
            await self?.publishPageFurigana(marks, key: key, source: source, generation: generation)
        }
    }

    /// Contrôle et publication d'un seul tenant sur le fil principal : rien ne peut s'intercaler. Un calcul annulé
    /// (fermeture, remplacement) a pu rendre des lectures de secours : elles ne doivent pas entrer dans le cache.
    private func publishPageFurigana(_ marks: [FuriganaLayer.Mark], key: String, source: Int, generation: Int) {
        guard !closed, !Task.isCancelled, furiganaGeneration[source] == generation else { return }
        FuriganaLayer.set(marks, for: key)
        pdfView.redrawVisiblePages()
    }


    func refreshFurigana(afterAIRead read: DocumentScan.PageRead) {
        guard !closed, read.documentId == document.id, shownSources.contains(read.page), FuriganaLayer.enabled else { return }
        Task { [weak self] in
            guard let self, let cached = await self.cachedOCR(source: read.page) else { return }
            self.showOCR(cached, source: read.page)
        }
    }

    /// Pages visibles avec texte intégré : furigana calculés depuis le texte du PDF.
    func scheduleFurigana(_ pages: [Int]) {
        furiganaTask?.cancel()
        guard FuriganaLayer.enabled else { return }
        let url = fileURL, id = document.id
        furiganaTask = Task.detached(priority: .utility) { [weak self] in
            var changed = false
            for source in pages {
                guard !Task.isCancelled else { return }
                let key = ScanSharpening.key(documentId: id, page: source)
                guard !FuriganaLayer.has(key) else { continue }
                guard PDFTextEngine.hasTextLayer(url: url, pageIndex: source) else { continue }
                let marks: [FuriganaLayer.Mark]? = (try? PDFPool.withDocument(url) { doc -> [FuriganaLayer.Mark]? in
                    doc.page(at: source).map(FuriganaLayer.marks(from:))
                }) ?? nil
                if let marks { FuriganaLayer.set(marks, for: key); changed = true }
            }
            guard changed, !Task.isCancelled else { return }
            await self?.pdfView.redrawVisiblePages()
        }
    }

    func setFuriganaTint(_ tint: FuriganaLayer.Tint) {
        UserDefaults.standard.set(tint.rawValue, forKey: FuriganaLayer.Tint.storageKey)
        pdfView.redrawVisiblePages()
    }

    func setFurigana(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: FuriganaLayer.storageKey)
        // Recalcul complet de la page posée (texte du PDF et OCR en cache).
        if on { schedulePageSettled() } else { furiganaTask?.cancel() }
        pdfView.redrawVisiblePages()
    }

    func setScanCleaning(_ method: ScanSharpening.Method) {
        UserDefaults.standard.set(method.rawValue, forKey: ScanSharpening.storageKey)
        sharpenTask?.cancel()
        if ScanSharpening.enabled { scheduleSharpening(visibleSources()) }
        pdfView.redrawVisiblePages()
    }

    /// Fond des pages changé : redessin immédiat (teinte peinte), puis pages voisines préparées (`scheduleTone`).
    func setPageTone(_ tone: PageTone) {
        guard tone != PageTone.current else { return }
        PageTone.current = tone
        ToneCache.clear()
        pdfView.redrawVisiblePages()
        scheduleTone(shownSources)
    }

    /// Pages teintées préparées : planche affichée, précédente et suivante ; les autres sont libérées (la fenêtre
    /// suit la lecture : en tournant, la nouvelle voisine se prépare, l'ancienne s'en va).
    func scheduleTone(_ visible: [Int]) {
        toneTask?.cancel()
        let tone = PageTone.current
        guard tone != .normal, let low = visible.min(), let high = visible.max() else { ToneCache.clear(); return }
        let reach = settings.layout == .double ? 2 : 1
        let window = Array(max(0, low - reach)...min(document.pageCount - 1, high + reach))
        let id = document.id, url = fileURL
        ToneCache.keep(Set(window.map { ScanSharpening.key(documentId: id, page: $0) }), tone: tone)
        // D'abord les pages affichées, puis les voisines.
        let order = visible + window.filter { !visible.contains($0) }
        toneTask = Task.detached(priority: .utility) { [weak self] in
            var shownReady = false
            for page in order {
                guard !Task.isCancelled else { return }
                let key = ScanSharpening.key(documentId: id, page: page)
                if ToneCache.prepare(key: key, fileURL: url, page: page, tone: tone), visible.contains(page) { shownReady = true }
            }
            guard shownReady, !Task.isCancelled else { return }
            await self?.pdfView.redrawVisiblePages()
        }
    }

    func applyTone() {
        pdfView.backgroundColor = settings.background.uiColor
    }

    /// Pages « Auto » (par défaut) : portrait = une page, paysage = double page. « Simple » ou « Double » choisis :
    /// toujours respectés. Appelé par `ReaderScreen` à l'ouverture et à chaque rotation.
    func adaptLayout(portrait: Bool) {
        guard portrait != portraitMode else { return }
        portraitMode = portrait
        update(settings: model.readerDefaults.applying(document.settingsOverride))
    }

    /// « Auto » remplacé par la disposition de l'orientation (le reste du lecteur ne voit que simple / double).
    func resolved(_ s: ReaderSettings) -> ReaderSettings {
        var s = s
        if s.layout == .auto { s.layout = portraitMode == true ? .single : .double }
        return s
    }

    func update(settings newSettings: ReaderSettings) {
        let old = settings
        let newSettings = resolved(newSettings)
        guard old != newSettings else { return }
        settings = newSettings
        let rtlDouble = { (s: ReaderSettings) in s.direction == .rightToLeft && s.layout == .double }
        let needsRebuild = old.direction != newSettings.direction || old.splitWidePages != newSettings.splitWidePages
            || old.autoCrop != newSettings.autoCrop || rtlDouble(old) != rtlDouble(newSettings)
            || (rtlDouble(newSettings) && old.firstPageAlone != newSettings.firstPageAlone)
        if needsRebuild {
            rebuild(keepingSource: currentSourcePage)
        } else {
            applyDisplaySettings()
        }
        if old.ocrEngine != newSettings.ocrEngine { schedulePageSettled() }
    }

    func setDocumentOverride(_ override: ReaderSettingsOverride) {
        document.settingsOverride = override
        let doc = document
        model.persist { try $0.save(doc) }
        update(settings: model.readerDefaults.applying(override))
    }

    /// La page source `index` devient la page « 1 » (numéros affichés comme dans le manuel imprimé).
    func setFirstPage(_ index: Int) {
        document.firstPageIndex = max(0, min(index, document.pageCount - 1))
        model.savePageOne(document)
    }
}
