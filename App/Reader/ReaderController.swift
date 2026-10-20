// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import OCRKit
import PDFKit
import PencilKit
import ReaderCore
import UIKit

/// Pilote le `PDFView` d'un document : construction des pages affichées (rognage, découpe,
/// rotation — en mémoire, le fichier n'est jamais réécrit), réglages, navigation, gestes,
/// surlignages, signets, recherche, sauvegarde de la position.
@MainActor
final class ReaderController: NSObject, ObservableObject {
    let model: AppModel
    @Published private(set) var document: LibraryDocument
    let pdfView = ReaderPDFView()
    let ink: InkStore

    @Published private(set) var settings: ReaderSettings
    @Published private(set) var pdf: PDFDocument?
    @Published private(set) var presented: [PresentedPage] = []
    @Published private(set) var currentIndex = 0
    @Published var barsVisible = true
    @Published private(set) var isDrawing = false
    @Published private(set) var hasSelection = false
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published var tappedHighlight: Highlight?
    @Published var loadError: String?
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var isSearching = false
    /// OCR de la page lue (première page lue en double page).
    @Published private(set) var ocrPage: OCRPage?
    @Published private(set) var ocrState: OCRState = .idle

    enum OCRState: Equatable {
        case idle, running, failed(String)
    }

    struct SearchResult: Identifiable {
        let id = UUID()
        /// `nil` : trouvé dans le texte OCR (page scannée), pas dans le texte du PDF.
        let selection: PDFSelection?
        let presentedIndex: Int
        let sourcePage: Int
        let context: String
        var fromOCR: Bool { selection == nil }
    }

    /// Lecture OCR de tout le document (pages scannées → texte cherchable).
    @Published private(set) var documentOCRProgress: (done: Int, total: Int)?
    private var documentOCRTask: Task<Void, Never>?

    private var transforms: [Int: PageTransform] = [:]
    private var highlights: [Highlight] = []
    /// Boîte et rotation d'origine de chaque page source (avant nos transformations).
    private var originalBoxes: [Int: CGRect] = [:]
    private var originalRotations: [Int: Int] = [:]
    /// Pages sources coupées en deux (réglage global ou manuel) : jamais rognées en entier.
    private var splitSources: Set<Int> = []
    /// Vrai pendant une reconstruction : le changement de page qui en résulte n'est pas un geste.
    private var rebuilding = false
    private var observers: [NSObjectProtocol] = []
    private var savePositionWork: DispatchWorkItem?
    private var cropTask: Task<Void, Never>?
    private var ocrTask: Task<Void, Never>?
    private var settleWork: DispatchWorkItem?
    private var singleTap: UITapGestureRecognizer!
    private var doubleTap: UITapGestureRecognizer!
    private var swipeLeft: UISwipeGestureRecognizer!
    /// Appui long en cours ou terminé (sélection de texte de PDFKit) : le tap qui suit est ignoré.
    private var pressWasLong = false
    private var longPressWatcher: UILongPressGestureRecognizer!
    private var swipeRight: UISwipeGestureRecognizer!

    init(document: LibraryDocument, model: AppModel) {
        self.document = document
        self.model = model
        self.settings = model.settings(for: document)
        self.currentSourcePage = document.lastPageIndex
        self.ink = InkStore(documentId: document.id, model: model)
        super.init()
        ink.controller = self
        configureGestures()
        observe()
    }

    var fileURL: URL { model.storage.url(for: document.id) }

    /// Page source en cours de lecture. En double page, la première page *lue* de la double page
    /// (celle de droite en lecture droite → gauche), pas la première dans l'ordre interne.
    @Published private(set) var currentSourcePage = 0

    var isCurrentPageBookmarked: Bool { bookmarks.contains { $0.pageIndex == currentSourcePage } }

    // MARK: Chargement

    func load() {
        do {
            transforms = try model.database.pageTransforms(documentId: document.id)
            highlights = try model.database.highlights(documentId: document.id)
            bookmarks = try model.database.bookmarks(documentId: document.id)
            try ink.loadIndex()
        } catch {
            loadError = error.localizedDescription
        }
        rebuild(keepingSource: document.lastPageIndex)
        markOpened()
        startAutoCropIfNeeded()
        schedulePageSettled()
    }

    /// (Re)construit le document affiché à partir du fichier et des transformations.
    private func rebuild(keepingSource source: Int) {
        guard let pdf = PDFDocument(url: fileURL) else {
            loadError = "Impossible d'ouvrir ce PDF."
            return
        }
        originalBoxes.removeAll(keepingCapacity: true)
        originalRotations.removeAll(keepingCapacity: true)
        let rtl = settings.direction == .rightToLeft
        var splitPages = Set<Int>()

        // De la fin vers le début : les insertions ne décalent pas les pages restant à traiter.
        for index in stride(from: pdf.pageCount - 1, through: 0, by: -1) {
            guard let page = pdf.page(at: index) else { continue }
            let box = page.bounds(for: .cropBox)
            originalBoxes[index] = box
            originalRotations[index] = page.rotation
            let transform = transforms[index]
            if let extra = transform?.rotation, extra % 360 != 0 {
                page.rotation = ((page.rotation + extra) % 360 + 360) % 360
            }
            let visibleSize = page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
            let split = transform?.split ?? false || (settings.splitWidePages && PresentationLayout.isWide(visibleSize))
            if split, let copy = page.copy() as? PDFPage {
                splitPages.insert(index)
                let first: PresentedPage.Part = rtl ? .right : .left
                let second: PresentedPage.Part = rtl ? .left : .right
                page.setBounds(PresentationLayout.box(for: first, in: box), for: .cropBox)
                copy.setBounds(PresentationLayout.box(for: second, in: box), for: .cropBox)
                pdf.insert(copy, at: index + 1)
            } else if settings.autoCrop, let crop = transform?.autoCrop {
                page.setBounds(ContentBounds.apply(crop, to: box), for: .cropBox)
            }
        }
        splitSources = splitPages
        presented = PresentationLayout.pages(pageCount: originalBoxes.count, splitPages: splitPages, rightToLeft: rtl)
        if rtl && settings.layout == .double {
            // Double page de droite à gauche : on range les pages dans l'ordre visuel nous-mêmes
            // (l'option RTL de PDFKit intervertit les tailles des pages d'une même double page).
            // (`exchangePage` de PDFKit lève une exception avec des pages copiées : on retire puis réinsère.)
            let order = PresentationLayout.rightToLeftSpreadOrder(count: pdf.pageCount, firstPageAlone: settings.firstPageAlone)
            for i in order.indices where order[i] == i + 1 {
                guard let second = pdf.page(at: i + 1) else { continue }
                pdf.removePage(at: i + 1)
                pdf.insert(second, at: i)
            }
            presented = order.map { presented[$0] }
        }
        addHighlightAnnotations(to: pdf)

        rebuilding = true
        self.pdf = pdf
        pdf.delegate = self
        #if DEBUG
        let overlays = !UserDefaults.standard.bool(forKey: "debugNoOverlays")
        #else
        let overlays = true
        #endif
        pdfView.pageOverlayViewProvider = overlays ? ink : nil
        pdfView.document = pdf
        applyDisplaySettings()
        go(toSource: source, animated: false)
        rebuilding = false
    }

    private func markOpened() {
        let id = document.id
        let page = document.lastPageIndex
        model.persist { try $0.updateReadingPosition(documentId: id, pageIndex: page) }
    }

    /// `cropBox` d'origine d'une page source (repère des résultats OCR).
    func originalBox(ofSource source: Int) -> CGRect? { originalBoxes[source] }

    // MARK: Réglages

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
    func update(settings newSettings: ReaderSettings) {
        let old = settings
        settings = newSettings
        let rtlDouble = { (s: ReaderSettings) in s.direction == .rightToLeft && s.layout == .double }
        let needsRebuild = old.direction != newSettings.direction || old.splitWidePages != newSettings.splitWidePages
            || old.autoCrop != newSettings.autoCrop || rtlDouble(old) != rtlDouble(newSettings)
            || (rtlDouble(newSettings) && old.firstPageAlone != newSettings.firstPageAlone)
        if needsRebuild {
            rebuild(keepingSource: currentSourcePage)
            startAutoCropIfNeeded()
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

    // MARK: Navigation

    func go(toPresented index: Int, animated: Bool = true) {
        guard let pdf, let page = pdf.page(at: max(0, min(index, pdf.pageCount - 1))) else { return }
        pdfView.go(to: page)
        currentIndex = pdf.index(for: page)
        updateCurrentSourcePage()
        // Les pages visibles ne sont connues qu'après la mise en page : on recalcule juste après.
        DispatchQueue.main.async { [weak self] in self?.updateCurrentSourcePage() }
    }

    func go(toSource source: Int, animated: Bool = true) {
        go(toPresented: PresentationLayout.presentedIndex(ofSource: source, in: presented), animated: animated)
    }

    func next() { turn(forward: true) }

    func previous() { turn(forward: false) }

    private var isAnimatingTurn = false

    /// Tourne la page. En mode paginé sans contrôleur de pages de PDFKit (double page, ou
    /// transition maison), glissement animé : la page actuelle (photo) part d'un côté, la
    /// nouvelle arrive de l'autre, dans le sens de lecture.
    private func turn(forward: Bool) {
        guard forward ? pdfView.canGoToNextPage : pdfView.canGoToPreviousPage else { return }
        let animate = settings.scrollMode == .paginated && settings.transition == .slide
            && !pdfView.isUsingPageViewController && pdfView.isAtFit && !isAnimatingTurn
            && !UIAccessibility.isReduceMotionEnabled
        guard animate, let host = pdfView.superview,
              let snapshot = pdfView.snapshotView(afterScreenUpdates: false) else {
            forward ? pdfView.goToNextPage(nil) : pdfView.goToPreviousPage(nil)
            return
        }
        isAnimatingTurn = true
        snapshot.frame = pdfView.frame
        host.insertSubview(snapshot, aboveSubview: pdfView)
        forward ? pdfView.goToNextPage(nil) : pdfView.goToPreviousPage(nil)
        pdfView.layoutIfNeeded()
        // Lecture gauche → droite : avancer fait partir le contenu vers la gauche ; l'inverse en droite → gauche.
        let movesLeft = forward != (settings.direction == .rightToLeft)
        let width = pdfView.bounds.width
        pdfView.transform = CGAffineTransform(translationX: movesLeft ? width : -width, y: 0)
        UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            snapshot.transform = CGAffineTransform(translationX: movesLeft ? -width : width, y: 0)
            self.pdfView.transform = .identity
        } completion: { _ in
            snapshot.removeFromSuperview()
            self.pdfView.transform = .identity
            self.isAnimatingTurn = false
        }
    }

    private func pageChanged() {
        guard let pdf, let page = pdfView.currentPage else { return }
        let index = pdf.index(for: page)
        guard index != NSNotFound, index != currentIndex || presented.isEmpty == false else { return }
        let changed = index != currentIndex
        currentIndex = index
        updateCurrentSourcePage()
        if changed, !rebuilding, settings.hideBarsOnScroll, barsVisible { barsVisible = false }
        scheduleSavePosition()
        preloadThumbnails(around: currentSourcePage)
        schedulePageSettled()
    }

    private func updateCurrentSourcePage() {
        guard let pdf, presented.indices.contains(currentIndex) else { return }
        var source = presented[currentIndex].source
        if settings.layout == .double {
            let visible = pdfView.visiblePages.map { pdf.index(for: $0) }.filter { presented.indices.contains($0) }
            if let first = visible.map({ presented[$0].source }).min() { source = min(source, first) }
        }
        if source != currentSourcePage {
            currentSourcePage = source
            scheduleSavePosition()
        }
    }

    private func scheduleSavePosition() {
        savePositionWork?.cancel()
        let id = document.id
        let page = currentSourcePage
        document.lastPageIndex = page
        let work = DispatchWorkItem { [model] in
            model.persist { try $0.updateReadingPosition(documentId: id, pageIndex: page) }
        }
        savePositionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Prépare les miniatures des pages voisines (aperçu instantané dans la barre de pages).
    private func preloadThumbnails(around source: Int) {
        let n = settings.preloadCount
        guard n > 0 else { return }
        let lower = max(0, source - n), upper = min(document.pageCount - 1, source + n)
        guard lower <= upper else { return }
        for page in lower...upper {
            model.thumbnails.thumbnail(documentId: document.id, fileURL: fileURL, page: page, width: 240) { _ in }
        }
    }

    // MARK: OCR

    /// Page stable depuis un instant : OCR en cache affiché, OCR auto si demandé.
    func schedulePageSettled() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pageSettled() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func pageSettled() {
        ink.showOCRBoxes = model.appSettings.showOCRBoxes
        ocrPage = nil
        ocrState = .idle
        let source = currentSourcePage
        let visible = visibleSources()
        Task { [weak self] in
            guard let self else { return }
            // Zones en cache pour toutes les pages visibles (double page).
            for page in visible {
                if let cached = await self.cachedOCR(source: page) { self.ink.setOCR(cached, source: page) }
            }
            if let cached = await self.cachedOCR(source: source) {
                if self.currentSourcePage == source { self.ocrPage = cached }
            } else if self.model.appSettings.ocrAutoCurrentPage {
                self.runOCR()
            }
        }
    }

    private func visibleSources() -> [Int] {
        guard let pdf else { return [currentSourcePage] }
        let sources = pdfView.visiblePages.map { pdf.index(for: $0) }.filter { presented.indices.contains($0) }.map { presented[$0].source }
        return Array(Set(sources)).sorted()
    }

    /// Moteurs à essayer, dans l'ordre, pour lire le cache d'une page.
    private func preferredEngines() -> [String] {
        switch settings.ocrEngine {
        case .pdfText: return [OCREngineID.pdfText]
        case .vision: return [OCREngineID.vision]
        case .auto: return [OCREngineID.pdfText, OCREngineID.vision]
        }
    }

    private func cachedOCR(source: Int) async -> OCRPage? {
        for engine in preferredEngines() {
            if let page = await model.ocr.cached(documentId: document.id, pageIndex: source, engine: engine) { return page }
        }
        return nil
    }

    /// Lance l'OCR de la page lue (en tâche de fond ; le cache évite de refaire).
    /// - Parameters:
    ///   - engine: moteur imposé (sinon : réglage du document, « auto » résolu selon la page).
    ///   - force: ignore le cache (bouton « Relancer »).
    func runOCR(engine: String? = nil, force: Bool = false) {
        ocrTask?.cancel()
        let source = currentSourcePage
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
                let page = try await service.page(documentId: documentId, url: url, pageIndex: source, engine: engineID, force: force)
                guard let self, !Task.isCancelled else { return }
                self.ink.setOCR(page, source: source)
                if self.currentSourcePage == source {
                    self.ocrPage = page
                    self.ocrState = .idle
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.currentSourcePage == source else { return }
                self.ocrState = .failed(error.localizedDescription)
            }
        }
    }

    /// OCR d'une page avec un moteur précis (comparaison), sans changer la page affichée.
    func ocr(engine: String) async throws -> OCRPage {
        try await model.ocr.page(documentId: document.id, url: fileURL, pageIndex: currentSourcePage, engine: engine)
    }

    func setShowOCRBoxes(_ on: Bool) {
        model.appSettings.showOCRBoxes = on
        ink.showOCRBoxes = on
        if on { pageSettled() }
    }

    func close() {
        savePositionWork?.perform()
        cropTask?.cancel()
        ocrTask?.cancel()
        documentOCRTask?.cancel()
        settleWork?.cancel()
        ink.flush()
        pdf?.cancelFindString()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    // MARK: Gestes

    private func configureGestures() {
        doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        singleTap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        singleTap.delegate = self
        singleTap.require(toFail: doubleTap)
        #if DEBUG
        let attach = !UserDefaults.standard.bool(forKey: "debugNoGestures")
        #else
        let attach = true
        #endif
        // Nos gestes ne doivent jamais bloquer ceux de PDFKit (sélection de texte à l'appui long,
        // poignées, menu) : ils observent les touches sans les annuler ni les retarder.
        for gesture in [doubleTap!, singleTap!] {
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesEnded = false
        }
        // Observe seulement (n'empêche rien) : marque les appuis longs pour que le tap les ignore.
        longPressWatcher = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressWatcher.minimumPressDuration = 0.35
        longPressWatcher.cancelsTouchesInView = false
        longPressWatcher.delaysTouchesEnded = false
        longPressWatcher.delegate = self
        if attach {
            pdfView.addGestureRecognizer(doubleTap)
            pdfView.addGestureRecognizer(singleTap)
            pdfView.addGestureRecognizer(longPressWatcher)
        }
        swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        for swipe in [swipeLeft!, swipeRight!] {
            swipe.delegate = self
            swipe.cancelsTouchesInView = false
            swipe.delaysTouchesEnded = false
            if attach { pdfView.addGestureRecognizer(swipe) }
        }
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        // Zoomé : le glisser sert à se déplacer dans la page, pas à tourner.
        guard pdfView.scaleFactor <= pdfView.scaleFactorForSizeToFit * 1.05 else { return }
        // Glisser vers la gauche = page suivante en lecture gauche → droite, l'inverse en droite → gauche.
        let towardLeft = gesture.direction == .left
        let forward = settings.direction == .rightToLeft ? !towardLeft : towardLeft
        forward ? next() : previous()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { pressWasLong = true }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // Un appui long sert à sélectionner du texte (PDFKit) : ce n'est pas un tap.
        guard !pressWasLong else { return }
        let point = gesture.location(in: pdfView)
        if hasSelection {
            pdfView.clearSelection()
            return
        }
        // Tap sur un surlignage : proposer de le supprimer.
        if let page = pdfView.page(for: point, nearest: false) {
            let pagePoint = pdfView.convert(point, to: page)
            if let annotation = page.annotation(at: pagePoint), let name = annotation.userName, name.hasPrefix("hl:") {
                let id = String(name.dropFirst(3))
                tappedHighlight = highlights.first { $0.id == id }
                return
            }
        }
        switch TapZones.action(atFraction: point.x / max(pdfView.bounds.width, 1), settings: settings) {
        case .next: next()
        case .previous: previous()
        case .toggleBars: barsVisible.toggle()
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: pdfView)
        let fit = pdfView.scaleFactorForSizeToFit
        if !pdfView.isAtFit {
            pdfView.fitToPage()
            return
        }
        guard let page = pdfView.page(for: point, nearest: true) else { return }
        let pagePoint = pdfView.convert(point, to: page)
        let target = fit * 2.5
        pdfView.scaleFactor = target
        let visible = CGSize(width: pdfView.bounds.width / target, height: pdfView.bounds.height / target)
        pdfView.go(to: CGRect(x: pagePoint.x - visible.width / 2, y: pagePoint.y - visible.height / 2,
                              width: visible.width, height: visible.height), on: page)
    }

    // MARK: Dessin

    func setDrawing(_ on: Bool) {
        isDrawing = on
        pdfView.isInMarkupMode = on
        if on {
            pdfView.clearSelection()
            barsVisible = true
        }
        ink.setEditing(on)
        applyDisplaySettings()
        DispatchQueue.main.async { [ink] in ink.showToolPicker(on) }
    }

    // MARK: Surlignages

    private func addHighlightAnnotations(to pdf: PDFDocument) {
        for highlight in highlights { annotate(highlight, in: pdf) }
    }

    private func pages(forSource source: Int, in pdf: PDFDocument) -> [PDFPage] {
        presented.enumerated().compactMap { index, p in p.source == source ? pdf.page(at: index) : nil }
    }

    private func annotate(_ highlight: Highlight, in pdf: PDFDocument) {
        for page in pages(forSource: highlight.pageIndex, in: pdf) {
            for rect in highlight.rects {
                let annotation = PDFAnnotation(bounds: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
                                               forType: .highlight, withProperties: nil)
                annotation.color = highlight.color.uiColor.withAlphaComponent(0.45)
                annotation.userName = "hl:" + highlight.id
                page.addAnnotation(annotation)
            }
        }
    }

    func highlightSelection(color: HighlightColor) {
        guard let pdf, let selection = pdfView.currentSelection else { return }
        var bySource: [Int: (rects: [PageRect], text: [String])] = [:]
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let index = pdf.index(for: page)
                guard presented.indices.contains(index) else { continue }
                let source = presented[index].source
                let r = line.bounds(for: page)
                guard r.width > 0, r.height > 0 else { continue }
                bySource[source, default: ([], [])].rects.append(PageRect(x: r.minX, y: r.minY, width: r.width, height: r.height))
                if let text = line.string { bySource[source, default: ([], [])].text.append(text) }
            }
        }
        for (source, value) in bySource {
            let highlight = Highlight(documentId: document.id, pageIndex: source, rects: value.rects, color: color,
                                      text: value.text.joined(separator: "\n"))
            highlights.append(highlight)
            annotate(highlight, in: pdf)
            model.persist { try $0.save(highlight) }
        }
        pdfView.clearSelection()
    }

    func deleteHighlight(_ highlight: Highlight) {
        highlights.removeAll { $0.id == highlight.id }
        if let pdf {
            for page in pages(forSource: highlight.pageIndex, in: pdf) {
                for annotation in page.annotations where annotation.userName == "hl:" + highlight.id {
                    page.removeAnnotation(annotation)
                }
            }
        }
        model.persist { try $0.deleteHighlight(id: highlight.id) }
    }

    var allHighlights: [Highlight] { highlights }

    // MARK: Signets

    func toggleBookmark() {
        let page = currentSourcePage
        if let existing = bookmarks.first(where: { $0.pageIndex == page }) {
            bookmarks.removeAll { $0.id == existing.id }
            model.persist { try $0.deleteBookmark(id: existing.id) }
        } else {
            let bookmark = Bookmark(documentId: document.id, pageIndex: page, title: "Page \(page + 1)")
            bookmarks.append(bookmark)
            bookmarks.sort { $0.pageIndex < $1.pageIndex }
            model.persist { try $0.save(bookmark) }
        }
    }

    func rename(_ bookmark: Bookmark, to title: String) {
        guard let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[i].title = title
        let updated = bookmarks[i]
        model.persist { try $0.save(updated) }
    }

    func delete(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        model.persist { try $0.deleteBookmark(id: bookmark.id) }
    }

    // MARK: Rotation et découpe de la page courante

    func rotateCurrentPage() {
        let source = currentSourcePage
        var t = transforms[source] ?? PageTransform(documentId: document.id, pageIndex: source)
        t.rotation = (t.rotation + 90) % 360
        transforms[source] = t
        model.persist { try $0.save(t) }
        rebuild(keepingSource: source)
    }

    func toggleSplitCurrentPage() {
        let source = currentSourcePage
        var t = transforms[source] ?? PageTransform(documentId: document.id, pageIndex: source)
        t.split.toggle()
        transforms[source] = t
        model.persist { try $0.save(t) }
        rebuild(keepingSource: source)
    }

    var isCurrentPageSplit: Bool { presented.indices.contains(currentIndex) && presented[currentIndex].part != .whole }

    // MARK: Rognage automatique (calculé en tâche de fond, mis en cache en base)

    private func startAutoCropIfNeeded() {
        cropTask?.cancel()
        guard settings.autoCrop else { return }
        let missing = (0..<document.pageCount).filter { transforms[$0]?.autoCrop == nil }
        guard !missing.isEmpty else { return }
        // Ordre : page courante puis vers l'extérieur, pour que ce qu'on lit soit rogné d'abord.
        let start = currentSourcePage
        let ordered = missing.sorted { abs($0 - start) < abs($1 - start) }
        let url = fileURL
        let documentId = document.id
        cropTask = Task.detached(priority: .utility) { [weak self] in
            guard let cg = CGPDFDocument(url as CFURL) else { return }
            var batch: [Int: NormalizedRect] = [:]
            for (n, index) in ordered.enumerated() {
                if Task.isCancelled { return }
                if let crop = autoreleasepool(invoking: { Self.detectCrop(cg, pageIndex: index) }) {
                    batch[index] = crop
                }
                if batch.count >= 12 || n == ordered.count - 1 {
                    let ready = batch
                    batch.removeAll()
                    await self?.applyCrops(ready, documentId: documentId)
                }
            }
        }
    }

    nonisolated private static func detectCrop(_ document: CGPDFDocument, pageIndex: Int) -> NormalizedRect? {
        guard let page = document.page(at: pageIndex + 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        let width = 160
        let height = max(1, Int((Double(width) * box.height / max(box.width, 1)).rounded()))
        var pixels = [UInt8](repeating: 255, count: width * height)
        let ok: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.interpolationQuality = .low
            ctx.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.drawPDFPage(page)
            return true
        }
        guard ok else { return nil }
        // Le contexte a l'origine en bas : les lignes du tampon vont du haut vers le bas, comme attendu.
        return pixels.withUnsafeBufferPointer {
            ContentBounds.detect(pixels: $0, width: width, height: height, bytesPerRow: width)
        } ?? NormalizedRect.full
    }

    private func applyCrops(_ crops: [Int: NormalizedRect], documentId: String) {
        guard documentId == document.id, settings.autoCrop, let pdf else { return }
        var toSave: [PageTransform] = []
        for (index, crop) in crops {
            var t = transforms[index] ?? PageTransform(documentId: documentId, pageIndex: index)
            t.autoCrop = crop
            transforms[index] = t
            toSave.append(t)
            guard !splitSources.contains(index), let box = originalBoxes[index] else { continue }
            for page in pages(forSource: index, in: pdf) {
                page.setBounds(ContentBounds.apply(crop, to: box), for: .cropBox)
            }
        }
        model.persist { try $0.save(toSave) }
        pdfView.layoutDocumentView()
        // Les tailles de page ont changé : recalcul de l'échelle « page entière » (sauf si zoomé).
        if pdfView.isAtFit { pdfView.fitToPage() }
    }

    // MARK: Recherche

    func search(_ query: String) {
        guard let pdf else { return }
        pdf.cancelFindString()
        searchResults = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSearching = false
            pdfView.highlightedSelections = nil
            return
        }
        isSearching = true
        pdf.beginFindString(trimmed, withOptions: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
        // Pages scannées : recherche aussi dans le texte OCR en cache.
        let documentId = document.id
        let engines = [OCREngineID.vision]
        let service = model.ocr
        Task { [weak self] in
            let hits = await service.search(trimmed, documentId: documentId, engines: engines)
            guard let self else { return }
            let pdfPages = Set(self.searchResults.filter { !$0.fromOCR }.map(\.sourcePage))
            for hit in hits where !pdfPages.contains(hit.page) {
                let index = PresentationLayout.presentedIndex(ofSource: hit.page, in: self.presented)
                let result = SearchResult(selection: nil, presentedIndex: index, sourcePage: hit.page,
                                          context: "📷 " + hit.context.replacingOccurrences(of: "\n", with: " "))
                let position = self.searchResults.firstIndex { $0.sourcePage > hit.page } ?? self.searchResults.endIndex
                self.searchResults.insert(result, at: position)
            }
        }
    }

    /// Lit (OCR) toutes les pages qui n'ont pas encore de texte, en tâche de fond.
    func ocrWholeDocument() {
        guard documentOCRTask == nil else { return }
        let url = fileURL
        let documentId = document.id
        let count = document.pageCount
        let choice = settings.ocrEngine
        let service = model.ocr
        documentOCRProgress = (0, count)
        documentOCRTask = Task { [weak self] in
            for page in 0..<count {
                if Task.isCancelled { break }
                let engine = await Task.detached(priority: .utility) {
                    OCRService.resolve(choice, url: url, pageIndex: page)
                }.value
                _ = try? await service.page(documentId: documentId, url: url, pageIndex: page, engine: engine)
                await MainActor.run { self?.documentOCRProgress = (page + 1, count) }
            }
            await MainActor.run {
                self?.documentOCRProgress = nil
                self?.documentOCRTask = nil
                self?.schedulePageSettled()
            }
        }
    }

    func cancelWholeDocumentOCR() {
        documentOCRTask?.cancel()
    }

    func show(_ result: SearchResult) {
        guard let selection = result.selection else {
            go(toSource: result.sourcePage)
            return
        }
        pdfView.go(to: selection)
        selection.color = UIColor.systemOrange.withAlphaComponent(0.6)
        pdfView.highlightedSelections = [selection]
    }

    // MARK: Image de la page (pour l'IA)

    /// Rendu net de la page affichée (≈ 2 048 px de large), pour le presse-papiers.
    func renderCurrentPage(maxWidth: CGFloat = 2048) -> UIImage? {
        // La page lue (en double page : la première lue, pas la première dans l'ordre interne).
        let index = presented.firstIndex { $0.source == currentSourcePage } ?? currentIndex
        guard let pdf, let page = pdf.page(at: index) else { return nil }
        let box = page.bounds(for: .cropBox)
        let rotated = page.rotation % 180 != 0
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        let scale = maxWidth / max(size.width, 1)
        return page.thumbnail(of: CGSize(width: size.width * scale, height: size.height * scale), for: .cropBox)
    }

    // MARK: Notifications

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pageChanged() }
        })
        observers.append(center.addObserver(forName: .PDFViewSelectionChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let text = self.pdfView.currentSelection?.string ?? ""
                self.hasSelection = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.savePositionWork?.perform()
                self?.ink.flush()
            }
        })
    }
}

// MARK: - Délégués

extension ReaderController: UIGestureRecognizerDelegate {
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        MainActor.assumeIsolated {
            // Nouveau contact : on oublie l'appui long précédent.
            if gestureRecognizer === longPressWatcher { pressWasLong = false }
        }
        return true
    }
}

extension ReaderController: PDFDocumentDelegate {
    nonisolated func didMatchString(_ instance: PDFSelection) {
        MainActor.assumeIsolated {
            guard let pdf, let page = instance.pages.first else { return }
            let index = pdf.index(for: page)
            let context = instance.copy() as? PDFSelection
            context?.extend(atStart: 20)
            context?.extend(atEnd: 30)
            let text = (context?.string ?? instance.string ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let source = presented.indices.contains(index) ? presented[index].source : index
            let result = SearchResult(selection: instance, presentedIndex: index, sourcePage: source, context: text)
            // Résultats triés par page de lecture (l'ordre interne peut différer en droite → gauche).
            let position = searchResults.firstIndex { $0.sourcePage > source } ?? searchResults.endIndex
            searchResults.insert(result, at: position)
        }
    }

    nonisolated func documentDidEndDocumentFind(_ notification: Notification) {
        MainActor.assumeIsolated { isSearching = false }
    }
}

// MARK: - Vue PDF

/// `PDFView` qui garde l'échelle « page entière » à jour quand la taille change (rotation, Split View).
final class ReaderPDFView: PDFView {
    private var lastSize: CGSize = .zero
    private var lastFit: CGFloat = 0

    /// Vrai si la page est affichée « entière » (pas de zoom de l'utilisateur).
    var isAtFit: Bool {
        lastFit == 0 || abs(scaleFactor - lastFit) / lastFit < 0.02
    }

    /// Ajuste la page à la vue. (On n'utilise pas `autoScales` : PDFKit le désactive dès qu'on
    /// règle le zoom minimum, et ne réajuste alors plus rien quand la taille change.)
    func fitToPage() {
        layoutDocumentView()
        let fit = scaleFactorForSizeToFit
        guard fit > 0 else { return }
        minScaleFactor = fit
        maxScaleFactor = max(6, fit * 6)
        scaleFactor = fit
        lastFit = fit
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize, bounds.width > 0 else { return }
        lastSize = bounds.size
        let wasFit = isAtFit
        // Après la mise en page de PDFKit : panneau latéral, Split View, rotation.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if wasFit {
                self.fitToPage()
            } else {
                self.minScaleFactor = self.scaleFactorForSizeToFit
            }
        }
    }
}

extension ReaderSettings.Background {
    var uiColor: UIColor {
        switch self {
        case .black: return .black
        case .darkGray: return UIColor(white: 0.11, alpha: 1)
        case .gray: return UIColor(white: 0.32, alpha: 1)
        case .white: return .white
        case .sepia: return UIColor(red: 0.96, green: 0.92, blue: 0.83, alpha: 1)
        }
    }
}

extension HighlightColor {
    var uiColor: UIColor {
        switch self {
        case .yellow: return UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)
        case .green: return UIColor(red: 0.45, green: 0.85, blue: 0.4, alpha: 1)
        case .blue: return UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1)
        case .pink: return UIColor(red: 1.0, green: 0.45, blue: 0.7, alpha: 1)
        case .orange: return UIColor(red: 1.0, green: 0.6, blue: 0.25, alpha: 1)
        }
    }
}
