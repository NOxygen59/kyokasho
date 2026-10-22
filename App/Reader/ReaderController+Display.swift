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

    // FDR-1 : modes .singlePage/.twoUp non continus (zoom qui saute) et `fitToPage` relancé à chaque changement de taille (remet le zoom). Voir § 6 étape 1.
    func applyDisplaySettings() {
        let s = settings
        let paginated = s.scrollMode == .paginated
        let double = s.layout == .double
        let rtl = s.direction == .rightToLeft

        // Le contrôleur de pages de PDFKit (glissement entre pages) ne gère que la page simple.
        let pageController = paginated && !double && s.transition == .slide
        if pdfView.isUsingPageViewController != pageController {
            pdfView.usePageViewController(pageController, withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 24])
        }
        switch (double, paginated) {
        case (false, true): pdfView.displayMode = .singlePage
        case (false, false): pdfView.displayMode = .singlePageContinuous
        case (true, true): pdfView.displayMode = .twoUp
        case (true, false): pdfView.displayMode = .twoUpContinuous
        }
        pdfView.displayDirection = paginated ? .horizontal : .vertical
        pdfView.displaysAsBook = double && s.firstPageAlone
        pdfView.displaysRTL = rtl && !double
        pdfView.displaysPageBreaks = true
        pdfView.pageBreakMargins = paginated ? .zero : UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        pdfView.pageShadowsEnabled = s.background != .black
        pdfView.backgroundColor = s.background.uiColor
        DispatchQueue.main.async { [pdfView] in pdfView.fitToPage() }
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
        let key = ScanSharpening.key(documentId: document.id, page: source), url = fileURL
        // Calculs lancés l'un après l'autre pour la même page : seul le dernier est gardé.
        furiganaGeneration[source, default: 0] += 1
        let generation = furiganaGeneration[source, default: 0]
        // Texte d'OvisOCR2 (scan à l'import, vérification, mise en page IA) : lectures d'après lui.
        let aiText = DocumentAnalysisService.rawURL(document.id, ModelSpec.ovisocr2.id, source)
        Task.detached(priority: .utility) { [weak self] in
            guard !PDFTextEngine.hasTextLayer(url: url, pageIndex: source) else { return }
            let frame: PageFrame? = (try? PDFPool.withDocument(url) { doc -> PageFrame? in
                doc.page(at: source).map { PageFrame(box: $0.bounds(for: .cropBox), rotation: $0.rotation) }
            }) ?? nil
            guard let frame else { return }
            let reference = try? String(contentsOf: aiText, encoding: .utf8)
            let marks = FuriganaLayer.marks(from: ocr, reference: reference, frame: frame)
            guard await self?.furiganaGeneration[source] == generation else { return }
            FuriganaLayer.set(marks, for: key)
            await self?.pdfView.redrawVisiblePages()
        }
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

    /// Fond des pages changé : on redessine (le document est reconstruit en tâche de fond).
    func setPageTone(_ tone: PageTone) {
        guard tone != PageTone.current else { return }
        PageTone.current = tone
        rebuild(keepingSource: currentSourcePage)
    }

    func update(settings newSettings: ReaderSettings) {
        let old = settings
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
        let doc = document
        model.persist { try $0.save(doc) }
    }
}
