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

    /// Furigana dessinés sur ce document : choix du manga (masqués par défaut), sinon réglage général.
    var pageFuriganaOn: Bool {
        document.isInMangaSpace ? document.settingsOverride.pageFurigana == true : FuriganaLayer.enabled
    }

    /// Fait connaître au dessin le choix de ce document (lu par PDFKit depuis ses fils).
    func registerFuriganaChoice() {
        FuriganaLayer.setManga(document.isInMangaSpace, shown: document.settingsOverride.pageFurigana == true,
                               documentId: document.id)
    }

    /// Classement changé dans la bibliothèque pendant la lecture : la copie du lecteur, le choix des furigana et les pages
    /// dessinées suivent, sans attendre la réouverture.
    func syncClassification(mangaSpace: Bool?) {
        guard document.settingsOverride.mangaSpace != mangaSpace else { return }
        document.settingsOverride.mangaSpace = mangaSpace
        registerFuriganaChoice()
        if pageFuriganaOn { schedulePageSettled() } else { furiganaTask?.cancel() }
        pdfView.redrawVisiblePages()
    }

    func applyDisplaySettings(refit: Bool = false) {
        registerFuriganaChoice()
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
        applyPencilPageTurnGuard()
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
        // Mode surlignage : un doigt surligne, rien d'autre (`applyHighlightGestures`).
        swipeLeft.isEnabled = manualSwipe && !ocrHighlightMode
        swipeRight.isEnabled = manualSwipe && !ocrHighlightMode
        doubleTap.isEnabled = s.doubleTapZoom && !isDrawing && !ocrHighlightMode
        singleTap.isEnabled = !isDrawing && !ocrHighlightMode
        if s.doubleTapZoom {
            singleTap.require(toFail: doubleTap)
        }
    }

    /// Retour terrain T1 (10/11/2026) : en page seule + Glissement, le défilement du contrôleur de pages de PDFKit
    /// prenait l'Apple Pencil comme un doigt, et écrire faisait tourner la page. Pendant le dessin dans ce mode, tous
    /// les défilements sous la vue PDF refusent le Pencil (le doigt et le trackpad tournent toujours la page) ; la
    /// toile PencilKit est laissée intacte. Rappelée à chaque changement de page : le contrôleur crée de nouvelles
    /// vues de page. Décision pure : `PencilPageTurnGuard` (testée).
    func applyPencilPageTurnGuard() {
        let drawing = isDrawing
        let pageController = pdfView.isUsingPageViewController
        var changed = 0, scrolls = 0
        func walk(_ view: UIView) {
            for sub in view.subviews where !(sub is PKCanvasView) {
                if let scroll = sub as? UIScrollView {
                    scrolls += 1
                    let pan = scroll.panGestureRecognizer
                    let current = pan.allowedTouchTypes.map(\.intValue)
                    if let next = PencilPageTurnGuard.touchTypes(current: current, drawing: drawing, pageController: pageController) {
                        pan.allowedTouchTypes = next.map { NSNumber(value: $0) }
                        changed += 1
                    }
                }
                walk(sub)
            }
        }
        walk(pdfView)
        // Recette 1.5.5 (1.1) : trace pour la prochaine recette si le Pencil fait encore glisser la page.
        if changed > 0 {
            Diagnostics.log("Pencil : \(changed) défilement(s) sur \(scrolls) réglé(s), dessin \(drawing), glissement \(pageController)", "gestes")
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
        // Réglage mesuré en double page paginée (le cas observé par NOxygen59) ; le reste garde le comportement de PDFKit.
        doublePagePanTuned = !pageController && double && paginated
        guard !pageController, let scroll = pdfInnerScrollView else { return }
        scroll.isDirectionalLockEnabled = !doublePagePanTuned
        applyInnerPanTouches()
    }

    /// Seul endroit qui règle le nombre de doigts du pan interne de PDFKit, appelé après chaque création de la vue interne
    /// et à chaque changement du mode surlignage (revue après recette 1.4.8, P2 4). Surlignage : un doigt surligne, deux
    /// doigts déplacent (aussi en double page). Sinon, un doigt en double page paginée (pincement), un ou deux ailleurs.
    func applyInnerPanTouches() {
        guard let pan = pdfInnerScrollView?.panGestureRecognizer else { return }
        pan.minimumNumberOfTouches = ocrHighlightMode ? 2 : 1
        pan.maximumNumberOfTouches = doublePagePanTuned && !ocrHighlightMode ? 1 : 2
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
                let hasText = ActivityCenter.shared.measure(.pageText) { PDFTextEngine.hasTextLayer(url: url, pageIndex: page) }
                guard !hasText else { continue }
                let key = ScanSharpening.key(documentId: id, page: page)
                let done = ActivityCenter.shared.measure(.sharpening) { (try? ScanSharpening.prepare(key: key, fileURL: url, page: page)) == true }
                if done { changed = true }
            }
            guard changed, !Task.isCancelled else { return }
            await self?.pdfView.requestRedraw()
        }
    }

    // MARK: Furigana

    /// Adoption **unique** d'une lecture comme OCR retenu de la page : sélection, zones, furigana, panneau et pastille
    /// changent ensemble, ou rien ne change (revue Codex de d87e048, R1 et R2).
    ///
    /// Refusée si une intention plus récente a eu lieu pour la page depuis la prise du ticket (choix du menu, « Relancer »,
    /// rotation, nouveau réglage, autre adoption), ou si le moteur diffère de celui choisi pour la page. Le résultat refusé
    /// reste en cache ; il n'est simplement pas affiché.
    /// - Parameters:
    ///   - updatePanel: `false` garde le panneau (même page, même moteur, position de lecture conservée).
    /// - Returns: `true` si la lecture est maintenant l'OCR retenu affiché.
    @discardableResult
    func adoptOCR(_ candidate: OCRCandidate, source: Int, updatePanel: Bool = true) -> Bool {
        guard !closed, ocrSelection.adopt(candidate.page.engine, ticket: candidate.ticket,
                                          overridingPin: OCRSelectionPolicy.isCorrected(candidate.page),
                                          fromCache: candidate.fromCache) else {
            Diagnostics.log("OCR p. \(source + 1) : \(candidate.page.engine) écarté, demande périmée "
                            + "(moteur retenu \(selectedEngines[source] ?? "aucun"))", "furigana")
            return false
        }
        drawOCR(candidate.page, source: source)
        if updatePanel, source == focusSource { ocrPage = candidate.page }
        return true
    }

    /// Rafraîchit l'affichage avec une nouvelle version **du moteur déjà retenu** (relecture, correction, cache mis à
    /// jour par une tâche IA). Un autre moteur est refusé : il doit passer par `adoptOCR`.
    /// - Returns: `false` si le résultat a été écarté ; l'appelant ne doit alors pas toucher au panneau.
    @discardableResult
    func showOCR(_ ocr: OCRPage, source: Int) -> Bool {
        // Un seul OCR par page alimente zones et furigana : celui retenu par la règle (`OCRSelectionPolicy`) ou choisi
        // dans le panneau. Un autre moteur (ancienne requête, correction d'un autre moteur, vérification) reste en
        // base mais ne remplace plus l'affichage (enquête furigana iPad / Mac, 07/11/2026).
        guard !closed, selectedEngines[source] == ocr.engine else {
            Diagnostics.log("OCR p. \(source + 1) : \(ocr.engine) écarté, moteur retenu \(selectedEngines[source] ?? "aucun")", "furigana")
            return false
        }
        drawOCR(ocr, source: source)
        return true
    }

    /// Zones OCR affichées (+ furigana du scan si l'option est active et la page sans texte intégré). Appelée seulement
    /// par `adoptOCR` et `showOCR`, après leur contrôle.
    private func drawOCR(_ ocr: OCRPage, source: Int) {
        realOCRMemo[source] = nil
        // Comparé au moteur **dessiné**, pas au moteur retenu : un choix du menu écrit déjà le nouveau moteur retenu
        // avant l'arrivée de la lecture (contre-revue Codex de 51f8a2d, F1).
        if ocrSelection.publish(ocr.engine, source: source) != nil {
            // Les furigana mémorisés viennent de l'ancien moteur : les retirer, sinon `scheduleFurigana` sauterait la page
            // (clé présente) et le dessin garderait l'ancienne lecture (texte du PDF choisi après des furigana NDLOCR).
            FuriganaLayer.remove(ScanSharpening.key(documentId: document.id, page: source))
            furiganaGeneration[source, default: 0] += 1
            pageFuriganaTasks[source]?.cancel()
            pdfView.requestRedraw()
            if ocr.engine == OCREngineID.pdfText { scheduleFurigana(shownSources) }
        }
        ink.setOCR(ocr, source: source)
        guard pageFuriganaOn else { return }
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
            // Page revue ou simple glissement : mêmes données, mêmes lectures, ni calcul ni redessin. L'empreinte couvre tout
            // ce dont dépendent les lectures, cadre du PDF compris (PDF remplacé sous le même identifiant).
            var hasher = Hasher()
            hasher.combine(ocr)
            hasher.combine(reference)
            hasher.combine(frame.box.origin.x)
            hasher.combine(frame.box.origin.y)
            hasher.combine(frame.box.width)
            hasher.combine(frame.box.height)
            hasher.combine(frame.rotation)
            hasher.combine(translator?.cacheGeneration)
            hasher.combine(lookupOptions)
            hasher.combine(Furigana.analyzer != nil)
            let signature = hasher.finalize()
            guard FuriganaLayer.signature(for: key) != signature else { return }
            // Même choix de lectures que dans le panneau OCR : MeCab si présent, sinon le dictionnaire.
            // Une page scannée sans couche texte doit bénéficier des mots déjà reconnus dans le panneau.
            let marks = FuriganaLayer.marks(from: ocr, reference: reference, frame: frame) { text in
                let segments = Furigana.analyzer == nil
                    ? (translator.flatMap { try? $0.segment(text, options: lookupOptions) } ?? []) : []
                return TextFurigana.rubies(text, segments: segments)
            }
            Diagnostics.log("Furigana p. \(source + 1) : \(ocr.engine), \(ocr.lines.count) lignes OCR, "
                            + "texte Ovis \(reference?.count ?? 0) caractères, \(marks.count) lectures", "furigana")
            // Préparée ici : la publication, sur le fil principal, n'a plus qu'à la ranger.
            let page = FuriganaLayer.PreparedPage(marks, signature: signature)
            await self?.publishPageFurigana(page, key: key, source: source, generation: generation, engine: ocr.engine)
        }
    }

    /// Contrôle et publication d'un seul tenant sur le fil principal : rien ne peut s'intercaler. Un calcul annulé
    /// (fermeture, remplacement) a pu rendre des lectures de secours : elles ne doivent pas entrer dans le cache.
    private func publishPageFurigana(_ page: FuriganaLayer.PreparedPage, key: String, source: Int, generation: Int,
                                     engine: String) {
        // Moteur retenu changé pendant le calcul (choix dans le panneau, réglage) : ces lectures ne sont plus les bonnes.
        // `drawOCR` n'est appelé qu'après adoption : un moteur retenu vide signifie un réglage remis à zéro entre-temps.
        guard !closed, !Task.isCancelled, furiganaGeneration[source] == generation,
              selectedEngines[source] == engine else { return }
        FuriganaLayer.set(page, for: key)
        pdfView.requestRedraw()
    }


    func refreshFurigana(afterAIRead read: DocumentScan.PageRead) {
        guard !closed, read.documentId == document.id, shownSources.contains(read.page), pageFuriganaOn else { return }
        Task { [weak self] in
            guard let self, let candidate = await self.candidateOCR(source: read.page) else { return }
            self.adoptOCR(candidate, source: read.page)
        }
    }

    /// Pages visibles avec texte intégré : furigana calculés depuis le texte du PDF.
    func scheduleFurigana(_ pages: [Int]) {
        furiganaTask?.cancel()
        guard pageFuriganaOn else { return }
        let url = fileURL, id = document.id
        furiganaTask = Task.detached(priority: .utility) { [weak self] in
            var changed = false
            for source in pages {
                guard !Task.isCancelled else { return }
                let key = ScanSharpening.key(documentId: id, page: source)
                guard !FuriganaLayer.has(key) else { continue }
                guard ActivityCenter.shared.measure(.pageText, { PDFTextEngine.hasTextLayer(url: url, pageIndex: source) }) else { continue }
                let marks: [FuriganaLayer.Mark]? = ActivityCenter.shared.measure(.furigana) {
                    (try? PDFPool.withDocument(url) { doc -> [FuriganaLayer.Mark]? in
                        doc.page(at: source).map(FuriganaLayer.marks(from:))
                    }) ?? nil
                }
                guard let marks else { continue }
                // Texte du PDF : seulement si aucun OCR d'un autre moteur n'est retenu pour la page. Vérifié sur le fil
                // principal juste avant l'écriture : un OCR publié pendant ce calcul garde la page.
                let allowed = await MainActor.run { () -> Bool in
                    guard let self, !self.closed, !Task.isCancelled else { return false }
                    let retained = self.selectedEngines[source]
                    guard retained == nil || retained == OCREngineID.pdfText else { return false }
                    FuriganaLayer.set(marks, for: key)
                    return true
                }
                if allowed { changed = true }
            }
            guard changed, !Task.isCancelled else { return }
            await self?.pdfView.requestRedraw()
        }
    }

    func setFuriganaTint(_ tint: FuriganaLayer.Tint) {
        UserDefaults.standard.set(tint.rawValue, forKey: FuriganaLayer.Tint.storageKey)
        pdfView.redrawVisiblePages()
    }

    func setFurigana(_ on: Bool) {
        if document.isInMangaSpace {
            // Manga : choix de ce document seulement, gardé dans ses réglages (et ses paquets).
            var override = document.settingsOverride
            override.pageFurigana = on ? true : nil
            setDocumentOverride(override, keepingChoices: false)
        } else {
            UserDefaults.standard.set(on, forKey: FuriganaLayer.storageKey)
        }
        registerFuriganaChoice()
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
                let ready = ActivityCenter.shared.measure(.tone) { ToneCache.prepare(key: key, fileURL: url, page: page, tone: tone) }
                if ready, visible.contains(page) { shownReady = true }
            }
            guard shownReady, !Task.isCancelled else { return }
            await self?.pdfView.requestRedraw()
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
        if old.ocrEngine != newSettings.ocrEngine {
            // Nouveau réglage du moteur : intention durable, qui remplace les choix faits page par page dans le panneau.
            // Les lectures encore en cours sont périmées, même si aucune sélection ne reste (revue Codex, R1).
            ocrSelection.reset()
            // Furigana mémorisés de l'ancien moteur : sans moteur retenu précédent, `adoptOCR` ne saurait pas qu'ils
            // viennent d'ailleurs, et `scheduleFurigana` sauterait les pages (passage au texte du PDF). Simple cache.
            FuriganaLayer.clearMemory()
            realOCRMemo.removeAll()
            ocrPage = nil
            schedulePageSettled()
        }
    }

    /// `keepingChoices` : le classement Manga et le choix des furigana viennent de la copie courante du lecteur, pas d'une
    /// feuille ouverte avant un reclassement (contre-revue 5a0f68f, P2 2). Seul `setFurigana` les écrit lui-même.
    /// « Garder pour ce document » (menu du panneau Texte, décision D2) : le moteur choisi pour la page de travail
    /// devient le moteur du document ; les choix page par page sont alors remplacés par ce réglage.
    func keepPinnedEngineForDocument() {
        guard let id = pinnedEngines[focusSource], let choice = OCREngineChoice(rawValue: id) else { return }
        var override = document.settingsOverride
        override.ocrEngine = choice
        setDocumentOverride(override)
    }

    func setDocumentOverride(_ override: ReaderSettingsOverride, keepingChoices: Bool = true) {
        var override = override
        if keepingChoices {
            override.mangaSpace = document.settingsOverride.mangaSpace
            override.pageFurigana = document.settingsOverride.pageFurigana
        }
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

/// Lecture candidate à l'OCR retenu d'une page, avec le ticket pris **avant** la lecture : `adoptOCR` la refuse si une
/// intention plus récente a eu lieu pour la page entre-temps.
struct OCRCandidate {
    var page: OCRPage
    let ticket: OCRPageSelection.Ticket
    /// Lue dans le cache (et non calculée maintenant) : refusée si une lecture a été dessinée depuis le ticket, car elle
    /// peut être plus ancienne que l'affichage (étape 2).
    let fromCache: Bool
}
