// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import GLMOCRKit
import OCRKit
import PDFKit
import PencilKit
import ReaderCore
import UIKit

/// `ReaderController` : navigation, gestes, dessin.
extension ReaderController {
    // MARK: Navigation

    func go(toPresented index: Int, animated: Bool = true) {
        pdfView.cancelPendingViewportRestoration()
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


    /// Tourne la page. En mode paginé sans contrôleur de pages de PDFKit (double page, ou
    /// transition maison), glissement animé : la page actuelle (photo) part d'un côté, la
    /// nouvelle arrive de l'autre, dans le sens de lecture.
    /// Page à afficher : juste après la dernière page visible, ou juste avant la première.
    /// (`goToNextPage` de PDFKit n'avance que d'une page : en double page, elle restait souvent
    /// dans la même double page et rien ne bougeait.)
    func turnTarget(forward: Bool) -> PDFPage? {
        guard let pdf else { return nil }
        let visible = pdfView.visiblePages.map { pdf.index(for: $0) }.filter { $0 != NSNotFound }
        let lo = visible.min() ?? currentIndex, hi = visible.max() ?? currentIndex
        let i = forward ? hi + 1 : lo - 1
        return i >= 0 && i < pdf.pageCount ? pdf.page(at: i) : nil
    }

    func turn(forward: Bool) {
        pdfView.cancelPendingViewportRestoration()
        // Défilement continu : une page coupée en bas compte comme visible ; PDFKit tourne bien tout seul.
        guard settings.scrollMode == .paginated else {
            forward ? pdfView.goToNextPage(nil) : pdfView.goToPreviousPage(nil)
            return
        }
        guard let target = turnTarget(forward: forward) else { return }
        let animate = settings.scrollMode == .paginated && settings.transition == .slide
            && !pdfView.isUsingPageViewController && pdfView.isAtFit && !isAnimatingTurn
            && !UIAccessibility.isReduceMotionEnabled
        guard animate, let host = pdfView.superview,
              let snapshot = pdfView.snapshotView(afterScreenUpdates: false) else {
            pdfView.go(to: target)
            return
        }
        isAnimatingTurn = true
        snapshot.frame = pdfView.frame
        host.insertSubview(snapshot, aboveSubview: pdfView)
        pdfView.go(to: target)
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

    func pageChanged() {
        // T1 : le contrôleur de pages vient peut-être de créer la vue de la nouvelle page.
        applyPencilPageTurnGuard()
        guard let pdf, let page = pdfView.currentPage else { return }
        let index = pdf.index(for: page)
        guard index != NSNotFound, index != currentIndex || presented.isEmpty == false else { return }
        let changed = index != currentIndex
        // Planche changée : un surlignage commencé sur l'ancienne ne publie plus rien (contre-revue 1.5.0, P2 5),
        // et le recalage différé du zoom animé n'a plus lieu d'être (P2 9).
        if changed {
            ocrHighlightGeneration += 1
            ocrHighlightDrag = nil
            ocrHighlightPreview = []
            pendingFitToPage?.cancel()
        }
        currentIndex = index
        updateCurrentSourcePage()
        ReadingTimeTracker.shared.pageViewed(currentSourcePage)
        if changed { tapLookupGeneration += 1 }
        if changed, lookupRequest != nil { endLookup() }
        if ReaderBarsPolicy.hidesOnPageChange(pageChanged: changed, rebuilding: rebuilding, hideOnTurn: settings.hideBarsOnScroll,
                                              barsVisible: barsVisible,
                                              secondsSinceBarsChanged: ProcessInfo.processInfo.systemUptime - barsChangedAt) {
            barsVisible = false
        }
        scheduleSavePosition()
        // Glisser ou zoomer dans la même page : la page de travail reste (le panneau ne revient pas en haut).
        schedulePageSettled(samePageKeeps: true)
    }

    func updateCurrentSourcePage() {
        guard let pdf, presented.indices.contains(currentIndex) else { return }
        var source = presented[currentIndex].source
        if settings.layout == .double {
            // Planche entière (même zoomée sur une page) : la page courante reste la première de la planche.
            let visible = pdfView.visiblePages.map { pdf.index(for: $0) }.filter { presented.indices.contains($0) }
                .flatMap(spread(of:)).filter { presented.indices.contains($0) }
            if let first = visible.map({ presented[$0].source }).min() { source = min(source, first) }
        }
        if source != currentSourcePage {
            currentSourcePage = source
            scheduleSavePosition()
        }
    }

    func scheduleSavePosition() {
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
    func preloadThumbnails(around source: Int) {
        let n = settings.preloadCount
        // Mode économie d'énergie : rien d'avance (les miniatures se font quand on ouvre la bande).
        guard n > 0, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        let lower = max(0, source - n), upper = min(document.pageCount - 1, source + n)
        guard lower <= upper else { return }
        for page in lower...upper {
            // Même largeur que la bande des pages (`FilmstripCell`), sinon la préparation ne sert à rien.
            model.thumbnails.thumbnail(documentId: document.id, fileURL: fileURL, page: page, width: 120) { _ in }
        }
    }

    // MARK: Gestes

    // FDR-1 : gestes / zoom « cassés » — pistes : tap simple qui attend l'échec du double-tap (~0,3 s), glisser en conflit avec le défilement, survol actif par défaut. Voir § 6 étape 1.
    func configureGestures() {
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
        // Même traitement tactile que le mode Pencil (qui marche bien) : PDFKit en « mode annotation » en permanence.
        // Ses gestes de texte (sélection au doigt, liens) ne se mêlent plus au pincement et au défilement d'iOS ;
        // la sélection de texte est faite ici (appui long sur un mot, puis glisser pour l'étendre).
        pdfView.isInMarkupMode = true
        // T1 (revue D-07) : après chaque recalage différé (rotation, panneau ouvert ou fermé), garde du Pencil réappliquée.
        pdfView.onLayoutSettled = { [weak self] in self?.applyPencilPageTurnGuard() }
        // Appui long : sélection d'un mot, étendue en glissant (le tap l'ignore ensuite).
        longPressWatcher = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressWatcher.minimumPressDuration = 0.35
        longPressWatcher.cancelsTouchesInView = false
        longPressWatcher.delaysTouchesEnded = false
        longPressWatcher.delegate = self
        pencilTap = UITapGestureRecognizer(target: self, action: #selector(handlePencilTap(_:)))
        pencilTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        pencilTap.cancelsTouchesInView = false
        pencilTap.delegate = self
        pencilTap.isEnabled = false
        applyPencilLookupGestures()
        hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        hover.delegate = self
        // Curseur (trackpad, souris) : cliquer-glisser sélectionne le texte. Le doigt, lui, passe par l'appui long.
        pointerSelect = UIPanGestureRecognizer(target: self, action: #selector(handlePointerSelect(_:)))
        pointerSelect.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        pointerSelect.allowedScrollTypesMask = []
        pointerSelect.maximumNumberOfTouches = 1
        pointerSelect.cancelsTouchesInView = false
        pointerSelect.delegate = self
        if attach { pdfView.addGestureRecognizer(pointerSelect) }
        if attach {
            pdfView.addGestureRecognizer(hover)
            pdfView.addGestureRecognizer(pencilTap)
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
            // Le défilement à deux doigts du trackpad appartient au UIScrollView de PDFKit.
            // Le geste maison ne sert qu'au balayage tactile d'un doigt pour tourner la page.
            if UserDefaults.standard.object(forKey: "reader.trackpadScrollPassThrough") as? Bool ?? true {
                swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            }
            if attach { pdfView.addGestureRecognizer(swipe) }
        }
        // Trackpad, deux doigts : en double page dézoomée, PDFKit ne tourne pas la page au défilement (RET-063).
        trackpadPageTurn = UIPanGestureRecognizer(target: self, action: #selector(handleTrackpadPageTurn(_:)))
        trackpadPageTurn.allowedScrollTypesMask = .continuous
        trackpadPageTurn.allowedTouchTypes = []
        trackpadPageTurn.delegate = self
        trackpadPageTurn.cancelsTouchesInView = false
        if attach { pdfView.addGestureRecognizer(trackpadPageTurn) }
    }

    @objc func handleTrackpadPageTurn(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended, settings.layout == .double,
              pdfView.scaleFactor <= pdfView.scaleFactorForSizeToFit * 1.05 else { return }
        let moved = gesture.translation(in: pdfView)
        guard PresentationLayout.isPageTurnScroll(moved) else { return }
        let towardLeft = moved.x < 0
        let forward = settings.direction == .rightToLeft ? !towardLeft : towardLeft
        forward ? next() : previous()
    }

    @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        // Zoomé : le glisser sert à se déplacer dans la page, pas à tourner.
        guard pdfView.scaleFactor <= pdfView.scaleFactorForSizeToFit * 1.05 else { return }
        // Glisser vers la gauche = page suivante en lecture gauche → droite, l'inverse en droite → gauche.
        let towardLeft = gesture.direction == .left
        let forward = settings.direction == .rightToLeft ? !towardLeft : towardLeft
        forward ? next() : previous()
    }

    @objc func handlePencilTap(_ gesture: UITapGestureRecognizer) {
        guard pencilLookup, !isDrawing else { return }
        let point = gesture.location(in: pdfView)
        Task { await lookup(at: point) }
    }

    @objc func handleHover(_ gesture: UIHoverGestureRecognizer) {
        traceLookup("Événement survol état=\(gesture.state.rawValue)")
        // Maj tenue : survol même bouton éteint (RET-021, #24). Les modificateurs viennent de l'événement lui-même.
        let shift = gesture.modifierFlags.contains(.shift)
        guard HoverLookupMode.isActive(toggleOn: hoverLookup, shiftHeld: shift, drawing: isDrawing),
              gesture.state == .began || gesture.state == .changed else {
            hoverTask?.cancel()
            return
        }
        let point = gesture.location(in: pdfView)
        // Toujours sur le mot affiché : rien à refaire.
        if lookupHighlight.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(point) }) {
            traceLookup("Survol : mot déjà surligné")
            hoverTask?.cancel()
            return
        }
        hoverTask?.cancel()
        // Petit délai : on cherche quand le curseur se pose, pas à chaque pixel.
        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }
            self.lookupOpenedByShiftOnly = HoverLookupMode.opensWithShiftOnly(toggleOn: self.hoverLookup, shiftHeld: shift)
            await self.lookup(at: point, fromHover: true)
        }
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { pressWasLong = true }
        let point = gesture.location(in: pdfView)
        switch gesture.state {
        case .began:
            guard !isDrawing, let page = pdfView.page(for: point, nearest: false) else { return }
            let pagePoint = pdfView.convert(point, to: page)
            selectionAnchor = (page, pagePoint)
            // Pendant la sélection, le doigt ne fait pas défiler la page.
            setInnerPan(enabled: false)
            select(page.selectionForWord(at: pagePoint))
        case .changed:
            extendSelection(to: point)
        default:
            selectionAnchor = nil
            setInnerPan(enabled: true)
        }
    }

    /// Sélection du point d'ancrage jusqu'à `point`, d'une page à l'autre d'une double page.
    /// Document reconstruit pendant le geste (réglage, page nettoyée) : sélection abandonnée.
    private func extendSelection(to point: CGPoint) {
        guard let (page, start) = selectionAnchor, let document = page.document, document === pdfView.document, !isDrawing else {
            selectionAnchor = nil
            setInnerPan(enabled: true)
            return
        }
        let target = pdfView.page(for: point, nearest: true) ?? page
        select(document.selection(from: page, at: start, to: target, at: pdfView.convert(point, to: target)))
    }

    @objc func handlePointerSelect(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: pdfView)
        switch gesture.state {
        case .began:
            guard !isDrawing, !ocrHighlightMode else { return }
            let translation = gesture.translation(in: pdfView)
            let origin = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
            // Page sans texte (scan) : rien à sélectionner, le glisser garde son effet habituel.
            guard let page = pdfView.page(for: origin, nearest: false), page.string?.isEmpty == false else { return }
            pressWasLong = true
            selectionAnchor = (page, pdfView.convert(origin, to: page))
            setInnerPan(enabled: false)
            extendSelection(to: point)
        case .changed:
            extendSelection(to: point)
        default:
            if selectionAnchor != nil {
                selectionAnchor = nil
                setInnerPan(enabled: true)
            }
        }
    }

    private func select(_ selection: PDFSelection?) {
        guard let selection, selection.string?.isEmpty == false else { return }
        pdfView.setCurrentSelection(selection, animate: false)
        hasSelection = true
    }

    /// Premier `UIScrollView` sous la vue PDF : le défilement interne de PDFKit (`PDFScrollView` en double page).
    var pdfInnerScrollView: UIScrollView? {
        func find(_ view: UIView) -> UIScrollView? {
            for sub in view.subviews {
                if let scroll = sub as? UIScrollView { return scroll }
                if let found = find(sub) { return found }
            }
            return nil
        }
        return find(pdfView)
    }

    /// Défilement zoomable de la page sous `point`. En page unique avec glissement, PDFKit passe par un contrôleur de pages :
    /// le premier défilement trouvé (`pdfInnerScrollView`) est alors celui qui fait tourner les pages, sans vue à zoomer,
    /// et le double toucher retombait sur le zoom immédiat, sans animation (retour de NOxygen59 du 07/11/2026, portrait
    /// comme paysage). Chaque page y a son propre défilement zoomable : on prend celui qui contient le point.
    func zoomableScrollView(at point: CGPoint) -> UIScrollView? {
        var zoomable: [UIScrollView] = []
        func collect(_ view: UIView) {
            for sub in view.subviews {
                if let scroll = sub as? UIScrollView, scroll.delegate?.viewForZooming?(in: scroll) != nil { zoomable.append(scroll) }
                collect(sub)
            }
        }
        collect(pdfView)
        let visible = zoomable.filter { !$0.isHidden && $0.window != nil && $0.alpha > 0 }
        return visible.first { $0.convert($0.bounds, to: pdfView).contains(point) } ?? visible.first
    }

    /// Glisser du défilement interne de PDFKit (le pincement est un autre geste et reste actif).
    private func setInnerPan(enabled: Bool) {
        guard let scroll = pdfInnerScrollView else {
            Diagnostics.log("sélection : défilement interne de PDFKit introuvable", "gestes")
            return
        }
        scroll.panGestureRecognizer.isEnabled = enabled
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        // Un appui long sert à sélectionner du texte (PDFKit) : ce n'est pas un tap.
        guard !pressWasLong else {
            Diagnostics.log("toucher ignoré : suit un appui long", "gestes")
            return
        }
        let point = gesture.location(in: pdfView)
        if hasSelection {
            // Le drapeau peut être périmé (document reconstruit : PDFKit n'annonce pas toujours la fin de la sélection).
            // Remis à zéro ici, sinon chaque toucher suivant serait avalé et les barres ne reviendraient plus.
            let visible = ReaderBarsPolicy.isVisibleSelection(pdfView.currentSelection?.string)
            pdfView.clearSelection()
            hasSelection = false
            if visible {
                Diagnostics.log("toucher : efface la sélection", "gestes")
                return
            }
        }
        // Note en attente d'ancre : ce toucher la pose (sur le mot touché s'il y en a un).
        if let note = placingAnchorFor {
            placingAnchorFor = nil
            placeAnchor(for: note, at: point)
            return
        }
        if lookupMode {
            // Sans cette reprise, les barres cachées en tournant la page ne revenaient plus dans ce mode.
            tapLookupGeneration += 1
            let generation = tapLookupGeneration
            let popupWasOpen = lookupRequest != nil
            Task { [weak self] in
                guard let self else { return }
                await self.lookup(at: point, tapGeneration: generation)
                guard !self.closed, ReaderBarsPolicy.togglesAfterLookup(
                    isStale: generation != self.tapLookupGeneration,
                    popupWasOpen: popupWasOpen, popupIsOpen: self.lookupRequest != nil) else { return }
                Diagnostics.log("toucher sans mot : barres \(self.barsVisible ? "cachées" : "affichées")", "gestes")
                self.barsVisible.toggle()
            }
            return
        }
        // Popup ouvert par le survol : un clic ailleurs le ferme (sans tourner la page).
        if lookupRequest != nil {
            Diagnostics.log("toucher : ferme le dictionnaire", "gestes")
            endLookup()
            return
        }
        // Tap sur un surlignage : proposer de le supprimer.
        if let page = pdfView.page(for: point, nearest: false) {
            let pagePoint = pdfView.convert(point, to: page)
            if let annotation = page.annotation(at: pagePoint), let name = annotation.userName, name.hasPrefix("note:") {
                let id = String(name.dropFirst(5))
                if let note = notes.first(where: { $0.id == id }) { openNote = note }
                return
            }
            if let annotation = page.annotation(at: pagePoint), let name = annotation.userName, name.hasPrefix("hl:") {
                let id = String(name.dropFirst(3))
                tappedHighlight = highlights.first { $0.id == id }
                return
            }
        }
        // Un tap ne tourne plus la page (glisser au doigt, flèches ou ← → au clavier) : il montre / cache les barres.
        Diagnostics.log("toucher : barres \(barsVisible ? "cachées" : "affichées")", "gestes")
        barsVisible.toggle()
    }

    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        pendingFitToPage?.cancel()
        let point = gesture.location(in: pdfView)
        let fit = pdfView.scaleFactorForSizeToFit
        // Zoom animé par le défilement interne de PDFKit (demande de NOxygen59 du 06/11/2026) ; sans lui, ou avec
        // « Réduire les animations », le zoom reste immédiat comme avant.
        let pageScroll = zoomableScrollView(at: point)
        let scroll = UIAccessibility.isReduceMotionEnabled ? nil : pageScroll
        let zoomView = scroll.flatMap { $0.delegate?.viewForZooming?(in: $0) }
        // Zoomé ? En page unique avec glissement, le zoom vit dans le défilement de la page ; PDFKit ne le reporte peut-être
        // pas dans `scaleFactor` (`isAtFit` resterait vrai et le double toucher zoomerait encore au lieu de revenir à la
        // page entière). On regarde donc aussi l'échelle de ce défilement (relecture du lot 1.5.3, R1).
        let pageZoomed = pageScroll.map { $0.minimumZoomScale > 0 && $0.zoomScale > $0.minimumZoomScale * 1.01 } ?? false
        if !pdfView.isAtFit || pageZoomed {
            guard let scroll, zoomView != nil, scroll.minimumZoomScale > 0 else {
                // Sans animation : remettre aussi le défilement de la page à son minimum, puis l'ajustement habituel.
                if pageZoomed, let pageScroll { pageScroll.setZoomScale(pageScroll.minimumZoomScale, animated: false) }
                pdfView.fitToPage()
                return
            }
            scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
            // Puis l'ajustement habituel, une fois l'animation finie (bornes et repère du zoom « page entière »), seulement
            // si rien n'a bougé entre-temps : même PDF, même page, zoom toujours au minimum (contre-revue 1.5.0, P2 9).
            let startPDF = pdfView.document, startPage = pdfView.currentPage, target = scroll.minimumZoomScale
            let fit = DispatchWorkItem { [weak self, weak scroll] in
                guard let self, let scroll, self.pdfView.document === startPDF, self.pdfView.currentPage === startPage,
                      abs(scroll.zoomScale - target) < 0.01, !scroll.isZooming, !scroll.isTracking else { return }
                self.pdfView.fitToPage()
            }
            pendingFitToPage = fit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: fit)
            return
        }
        guard let page = pdfView.page(for: point, nearest: true) else { return }
        let pagePoint = pdfView.convert(point, to: page)
        let target = fit * 2.5
        let visible = CGSize(width: pdfView.bounds.width / target, height: pdfView.bounds.height / target)
        let pageRect = CGRect(x: pagePoint.x - visible.width / 2, y: pagePoint.y - visible.height / 2,
                              width: visible.width, height: visible.height)
        if let scroll, let zoomView {
            let rect = pdfView.convert(pdfView.convert(pageRect, from: page), to: zoomView)
            if rect.width > 0, rect.height > 0, rect.minX.isFinite, rect.minY.isFinite {
                scroll.zoom(to: rect, animated: true)
                return
            }
        }
        pdfView.scaleFactor = target
        pdfView.go(to: pageRect, on: page)
    }

    // MARK: Dessin

    func setDrawing(_ on: Bool) {
        isDrawing = on
        toolModes.update(documentId: document.id) { $0.drawing = on }
        // Toujours en mode annotation (voir `configureGestures`), dessin ou non.
        pdfView.isInMarkupMode = true
        if on {
            pdfView.clearSelection()
            barsVisible = true
        }
        ink.setEditing(on)
        applyDisplaySettings()
        DispatchQueue.main.async { [ink] in ink.showToolPicker(on) }
        // T1 : les vues de page du contrôleur peuvent n'apparaître qu'après la mise en page.
        DispatchQueue.main.async { [weak self] in self?.applyPencilPageTurnGuard() }
    }
}
