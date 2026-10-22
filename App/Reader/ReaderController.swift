// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import GLMOCRKit
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
    /// Note ouverte dans la fenêtre flottante.
    @Published var openNote: PageComment?
    /// Note qui attend son ancre : le prochain toucher sur la page la pose.
    @Published var placingAnchorFor: PageComment?
    /// Notes du document (ancres affichées sur les pages).
    @Published private(set) var notes: [PageComment] = []
    @Published var loadError: String?
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var isSearching = false
    /// OCR de la page lue (première page lue en double page).
    /// OCR de la page de travail (`focusSource`) : panneau Texte / Mots.
    @Published private(set) var ocrPage: OCRPage? {
        // Nouvelle page de travail lue : ses lignes douteuses partent à GLM-OCR (s'il est installé et l'option active).
        didSet {
            // Autre page : la relecture de l'ancienne s'arrête (son résultat est jeté).
            if ocrPage == nil { rereadTask?.cancel(); rereading = false }
            if ocrPage != nil, oldValue?.lines != ocrPage?.lines || oldValue == nil {
                DispatchQueue.main.async { [weak self] in self?.refineOCR() }
            }
        }
    }
    /// Pages affichées (deux en double page) et celle choisie dans le panneau (pilules).
    @Published private(set) var shownSources: [Int] = []
    @Published private(set) var focusSource = 0
    @Published private(set) var ocrState: OCRState = .idle

    // MARK: Dictionnaire au toucher
    /// Outil « dictionnaire » actif : un tap sur un caractère cherche le mot.
    @Published var lookupMode = false
    /// Demande de recherche (texte à partir du caractère touché, point d'ancrage dans la vue).
    @Published var lookupRequest: LookupRequest?
    /// Rectangles (repère de la vue PDF) du texte touché puis du mot reconnu.
    @Published var lookupHighlight: [CGRect] = []

    struct LookupRequest: Equatable {
        let id = UUID()
        let text: String
        let anchor: CGPoint
        /// Premier caractère trouvé (repère de la vue PDF) : le popup se place à côté, sans le cacher.
        var wordRect: CGRect = .zero
        /// Texte vertical (colonnes) : popup à côté de la colonne ; horizontal : popup sous la ligne.
        var vertical = false
    }

    /// Survol au curseur (trackpad / souris) : le popup du dictionnaire suit le pointeur.
    @Published var hoverLookup = UserDefaults.standard.object(forKey: "reader.hoverLookup") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hoverLookup, forKey: "reader.hoverLookup") }
    }
    /// La page a du texte (intégré ou OCR) : l'option de survol a un sens.
    var pageHasText: Bool { ocrPage != nil || pageHasPDFText }
    /// Texte intégré à la page lue : calculé une fois par page, hors du fil principal (et plus à
    /// chaque rafraîchissement de l'écran, ce qui relisait tout le texte de la page).
    @Published private(set) var pageHasPDFText = false
    /// Texte de la page touchée / survolée, gardé pour les recherches suivantes sur la même page.
    /// Texte de la page sous le curseur + correspondance « index de `characterIndex(at:)` → index du texte ».
    private var pageStringCache: (index: Int, string: NSString, map: [Int], hasText: Bool)?
    /// `realOCR` des pages hors panneau (évite une lecture du cache SQLite à chaque survol) ; vidé à chaque OCR.
    private var realOCRMemo: [Int: OCRPage?] = [:]
    /// Début de mot par caractère, par ligne de texte (découpage du dictionnaire), pour le survol.
    private var wordStartMemo: [String: [Int]] = [:]
    private var pageTextTask: Task<Void, Never>?
    private var sharpenTask: Task<Void, Never>?
    private var furiganaTask: Task<Void, Never>?
    /// File de `ensureOCR` : pages à lire, page en cours, tâche unique.
    private var ensureQueue: [Int] = []
    private var ensuringPage: Int?
    private var ensureTask: Task<Void, Never>?
    private var hover: UIHoverGestureRecognizer!
    private var pencilTap: UITapGestureRecognizer!
    /// Le Pencil cherche le mot touché dans le dictionnaire (au lieu de dessiner ou d'afficher les barres).
    @Published var pencilLookup = false {
        didSet {
            // Le doigt et la souris gardent le tap normal ; le Pencil passe par `pencilTap`.
            let all: [UITouch.TouchType] = pencilLookup ? [.direct, .indirect, .indirectPointer] : [.direct, .indirect, .indirectPointer, .pencil]
            singleTap?.allowedTouchTypes = all.map { NSNumber(value: $0.rawValue) }
            pencilTap?.isEnabled = pencilLookup
        }
    }
    private var hoverTask: Task<Void, Never>?

    /// Contexte du mot cherché, pour fabriquer une carte : phrase, ligne dans la page.
    struct LookupContext {
        let source: Int
        let presentedIndex: Int
        let sentence: String
        /// Rectangle de la ligne, repère de la page PDF (reconverti au moment de l'ajout).
        let lineRect: CGRect
        let vertical: Bool
    }
    private(set) var lookupContext: LookupContext?

    /// Caractères du texte touché, pour surligner exactement le mot reconnu (n premiers).
    private var lookupCharacterRects: [CGRect] = []

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
        pdfView.onLookupSelection = { [weak self] in self?.lookupSelection() }
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
            notes = try model.database.comments(documentId: document.id)
            try ink.loadIndex()
        } catch {
            loadError = error.localizedDescription
        }
        rebuild(keepingSource: document.lastPageIndex)
        markOpened()
    }

    /// Résultat de la construction (fait hors du fil principal) : document affiché + repères.
    private struct Built: @unchecked Sendable {
        let pdf: PDFDocument
        let boxes: [Int: CGRect]
        let rotations: [Int: Int]
        let splits: Set<Int>
        let presented: [PresentedPage]
    }

    /// Numéro de la dernière construction demandée : un résultat plus ancien est ignoré.
    private var rebuildGeneration = 0
    /// Vrai pendant la construction du document (ouverture, réglages, page coupée).
    @Published private(set) var isBuilding = false
    private var buildTask: Task<Void, Never>?
    /// Lecteur fermé : plus rien ne doit réinstaller de document.
    private var closed = false

    /// (Re)construit le document affiché à partir du fichier et des transformations.
    /// Le gros du travail (lecture de toutes les pages, copies des pages coupées, ordre droite → gauche)
    /// se fait en tâche de fond ; seule l'installation dans la vue PDF reste sur le fil principal.
    private func rebuild(keepingSource source: Int) {
        pageStringCache = nil
        rebuildGeneration += 1
        let generation = rebuildGeneration
        let url = fileURL, transforms = transforms, settings = settings, documentId = document.id
        isBuilding = true
        // Une seule construction à la fois : la précédente (plus à jour) est abandonnée.
        buildTask?.cancel()
        buildTask = Task.detached(priority: .userInitiated) { [weak self] in
            let built = autoreleasepool { Self.build(url: url, documentId: documentId, transforms: transforms, settings: settings) }
            guard !Task.isCancelled else { return }
            await self?.install(built, source: source, generation: generation)
        }
    }

    nonisolated private static func build(url: URL, documentId: String, transforms: [Int: PageTransform],
                                          settings: ReaderSettings) -> Built? {
        guard let pdf = PDFDocument(url: url) else { return nil }
        pdf.delegate = TonedPageProvider.shared
        var boxes: [Int: CGRect] = [:]
        var rotations: [Int: Int] = [:]
        let rtl = settings.direction == .rightToLeft
        var splitPages = Set<Int>()
        let count = pdf.pageCount
        boxes.reserveCapacity(count)
        rotations.reserveCapacity(count)

        // Pages dans l'ordre final, puis un seul rangement du document (voir plus bas).
        var ordered: [PDFPage] = []
        ordered.reserveCapacity(count)
        for index in 0..<count {
            guard let page = pdf.page(at: index) else { continue }
            let box = page.bounds(for: .cropBox)
            boxes[index] = box
            rotations[index] = page.rotation
            ordered.append(page)
            // Version nettoyée (DE-GAN) possible : posée sur le cadre d'origine.
            let pageKey = ScanSharpening.key(documentId: documentId, page: index)
            (page as? TonedPage)?.pageKey = pageKey
            (page as? TonedPage)?.originalBox = box
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
                // `copy()` ne recopie pas les propriétés Swift.
                (copy as? TonedPage)?.pageKey = pageKey
                (copy as? TonedPage)?.originalBox = box
                ordered.append(copy)
            } else if settings.autoCrop, let crop = transform?.autoCrop {
                page.setBounds(ContentBounds.apply(crop, to: box), for: .cropBox)
            }
        }
        var presented = PresentationLayout.pages(pageCount: boxes.count, splitPages: splitPages, rightToLeft: rtl)
        var reordered = !splitPages.isEmpty
        if rtl && settings.layout == .double {
            // Double page de droite à gauche : on range les pages dans l'ordre visuel nous-mêmes
            // (l'option RTL de PDFKit intervertit les tailles des pages d'une même double page).
            let order = PresentationLayout.rightToLeftSpreadOrder(count: ordered.count, firstPageAlone: settings.firstPageAlone)
            ordered = order.map { ordered[$0] }
            presented = order.map { presented[$0] }
            reordered = reordered || ordered.count > 1
        }
        // (Une page illisible manquerait à la liste : dans ce cas on ne touche pas au document.)
        if reordered, boxes.count == count {
            // Vider puis remplir par la fin : chaque opération est immédiate, alors que retirer / insérer
            // au milieu décale toutes les pages suivantes (lent sur un gros livre). Même document et mêmes
            // pages : le sommaire reste valable. (`exchangePage` lève une exception avec des pages copiées.)
            for i in stride(from: pdf.pageCount - 1, through: 0, by: -1) { pdf.removePage(at: i) }
            for (i, page) in ordered.enumerated() { pdf.insert(page, at: i) }
        }
        return Built(pdf: pdf, boxes: boxes, rotations: rotations, splits: splitPages, presented: presented)
    }

    private func install(_ built: Built?, source: Int, generation: Int) {
        guard generation == rebuildGeneration, !closed else { return }
        isBuilding = false
        // Page tournée pendant la construction : on reste où l'utilisateur est allé.
        let target = pdf == nil ? source : currentSourcePage
        guard let built else {
            loadError = "Impossible d'ouvrir ce PDF."
            return
        }
        originalBoxes = built.boxes
        originalRotations = built.rotations
        splitSources = built.splits
        presented = built.presented
        let pdf = built.pdf
        // Rognages calculés pendant la construction (l'instantané des transformations était plus ancien).
        if settings.autoCrop {
            var pagesBySource: [Int: [PDFPage]] = [:]
            for (i, p) in built.presented.enumerated() where transforms[p.source]?.autoCrop != nil && !built.splits.contains(p.source) {
                if let page = pdf.page(at: i) { pagesBySource[p.source, default: []].append(page) }
            }
            for (source, pages) in pagesBySource {
                guard let crop = transforms[source]?.autoCrop, let box = built.boxes[source] else { continue }
                for page in pages { page.setBounds(ContentBounds.apply(crop, to: box), for: .cropBox) }
            }
        }
        addHighlightAnnotations(to: pdf)
        for note in notes { annotateAnchor(note, in: pdf) }
        // L'ancien document ne doit plus envoyer de résultats de recherche (ses index ne valent plus rien).
        self.pdf?.cancelFindString()
        self.pdf?.delegate = nil
        if !searchResults.isEmpty || !pendingResults.isEmpty {
            searchResults = []
            pendingResults = []
            isSearching = false
        }

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
        go(toSource: target, animated: false)
        rebuilding = false
        // Le rognage a besoin des repères de pages : lancé une fois le document installé.
        startAutoCropIfNeeded()
        schedulePageSettled()
    }

    private func markOpened() {
        let id = document.id
        let page = document.lastPageIndex
        model.persist { try $0.updateReadingPosition(documentId: id, pageIndex: page) }
    }

    /// Cherche le texte sous `point` (vue PDF) : texte intégré du PDF, sinon OCR (fait si besoin).
    /// `fromHover` : survol au curseur → jamais d'OCR lancé (trop lent), et rien ne se ferme
    /// quand le pointeur passe sur un blanc (pour pouvoir aller jusqu'au popup).
    func lookup(at point: CGPoint, fromHover: Bool = false) async {
        guard let pdf, let page = pdfView.page(for: point, nearest: false) else { return }
        let index = pdf.index(for: page)
        guard presented.indices.contains(index) else { return }
        let source = presented[index].source
        let pagePoint = pdfView.convert(point, to: page)
        let maxLength = model.dictionary.profile.lookup.scanLength

        // 1. Texte intégré du PDF (lu une fois par page, gardé pour le survol).
        let ns: NSString
        let map: [Int]
        let pageHasText: Bool
        if let cached = pageStringCache, cached.index == index {
            ns = cached.string
            map = cached.map
            pageHasText = cached.hasText
        } else {
            ns = (page.string ?? "") as NSString
            map = Self.glyphToStringMap(ns)
            // Même règle que l'OCR « auto » : au moins 8 vrais caractères (pas seulement des blancs).
            pageHasText = (ns as String).unicodeScalars.lazy.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
                .prefix(8).count >= 8
            pageStringCache = (index, ns, map, pageHasText)
        }
        // OCR déjà fait par un vrai moteur (panneau, furigana) : il passe avant la couche texte du PDF, qui sur
        // un PDF « photo » est souvent l'OCR médiocre de l'appli de scan.
        let realOCR = pageHasText ? await realOCR(source: source) : nil
        // Texte intégré seulement s'il y en a vraiment (un PDF « photo » a souvent une couche vide ou faite
        // de blancs : il passe par l'OCR).
        if pageHasText, realOCR == nil {
            let glyph = page.characterIndex(at: pagePoint)
            // Point hors du texte (marge, image) : rien à chercher, et surtout pas l'OCR d'une page numérique.
            guard glyph >= 0, glyph < map.count, let i = Self.stringIndex(near: map[glyph], glyph: glyph, on: page, string: ns) else {
                if !fromHover { lookupHighlight = [] }
                return
            }
            do {
                var text = ""
                var rects: [CGRect] = []
                // Remonter au début du mot (toucher 井 dans 天井 cherche 天井) : fenêtre de la ligne autour
                // du caractère, découpée par le dictionnaire.
                var back: [Int] = []
                var k = i
                while back.count < 16, k > 0 {
                    let r = ns.rangeOfComposedCharacterSequence(at: k - 1)
                    let piece = ns.substring(with: r)
                    if piece == "\n" || piece == "\r" { break }
                    back.insert(r.location, at: 0)
                    k = r.location
                }
                var window = back.map { ns.substring(with: ns.rangeOfComposedCharacterSequence(at: $0)) }.joined()
                var f = i
                while f < ns.length, window.count < back.count + 16 {
                    let r = ns.rangeOfComposedCharacterSequence(at: f)
                    let piece = ns.substring(with: r)
                    if piece == "\n" || piece == "\r" { break }
                    window += piece
                    f = NSMaxRange(r)
                }
                let wordStart = await wordStart(in: window, at: back.count)
                var j = wordStart < back.count ? back[wordStart] : i
                while j < ns.length, text.count < maxLength {
                    let range = ns.rangeOfComposedCharacterSequence(at: j)
                    let piece = ns.substring(with: range)
                    if piece == "\n" || piece == "\r" { break }
                    text += piece
                    // Rectangle du caractère dans le même repère que le texte (`selection(for:)`).
                    let bounds = page.selection(for: range)?.bounds(for: page) ?? .zero
                    rects.append(pdfView.convert(bounds, from: page))
                    j = NSMaxRange(range)
                }
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    let line = page.selectionForLine(at: pagePoint)
                    let context = LookupContext(source: source, presentedIndex: index,
                                                sentence: line?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? text,
                                                lineRect: line?.bounds(for: page) ?? .zero, vertical: false)
                    present(text: text, rects: rects, anchor: point, context: context)
                    return
                }
                if !fromHover { lookupHighlight = [] }
                return
            }
        }

        // 2. OCR de la page (cache, sinon le moteur choisi : NDLOCR / PP-OCRv5 s'ils sont installés).
        guard let box = originalBoxes[source], let frame = pageFrame(ofSource: source) else { return }
        var ocr = realOCR ?? (source == focusSource ? ocrPage : nil)
        if ocr == nil { ocr = await cachedOCR(source: source) }
        if ocr == nil, fromHover {
            // Survol d'une page jamais lue : on lance l'OCR en fond, le survol marchera dès qu'il a fini.
            ensureOCR([source])
            return
        }
        if ocr == nil {
            let focused = source == focusSource
            if focused { ocrState = .running }
            let engine = await scanEngine(source: source)
            ocr = try? await model.ocr.page(documentId: document.id, url: fileURL, pageIndex: source, engine: engine)
            if focused, focusSource == source { ocrState = .idle }
            if let ocr { if source == focusSource { ocrPage = ocr }; showOCR(ocr, source: source) }
        }
        guard let ocr else { return }
        // Rotation intrinsèque comprise (photos de pages) : sans elle, le toucher visait à côté.
        let normalized = frame.normalized(pagePoint)
        // Marge de toucher : ~14 pt au doigt, ~4 pt au curseur, convertis en fraction de la page affichée.
        let margin: CGFloat = fromHover ? 4 : 14
        // Largeur affichée de la page (côté qui correspond à l'axe x du repère OCR, rotation comprise).
        let shownWidth = frame.rotation % 180 == 0 ? box.width : box.height
        let tolerance = Double(margin / max(shownWidth * pdfView.scaleFactor, 1))
        guard let hit = ocr.character(at: normalized, tolerance: tolerance) else {
            if !fromHover { lookupHighlight = [] }
            return
        }
        let hitLine = ocr.lines[hit.line]
        let lb = hitLine.box
        let context = LookupContext(source: source, presentedIndex: index, sentence: hitLine.text,
                                    lineRect: frame.pageRect(lb),
                                    vertical: hitLine.vertical)
        var text = ""
        var rects: [CGRect] = []
        var line = hit.line
        // Début du mot qui contient le caractère touché (pas seulement ce caractère).
        var start = await wordStart(in: hitLine.text, at: hit.index)
        // Le texte continue sur les lignes suivantes (phrase coupée par la mise en page).
        while line < ocr.lines.count, text.count < maxLength {
            let l = ocr.lines[line]
            let chars = Array(l.text)
            for k in start..<chars.count where text.count < maxLength {
                text.append(chars[k])
                if l.charBoxes.indices.contains(k) {
                    let b = l.charBoxes[k]
                    let pageRect = frame.pageRect(b)
                    rects.append(pdfView.convert(pageRect, from: page))
                } else {
                    rects.append(.zero)
                }
            }
            line += 1
            start = 0
        }
        present(text: text, rects: rects, anchor: point, context: context)
    }

    /// `characterIndex(at:)` / `characterBounds(at:)` ne comptent pas les fins de ligne de `page.string`
    /// (vérifié sur Mac) : sans correction, le mot lu glissait d'un caractère par ligne au-dessus.
    nonisolated static func glyphToStringMap(_ ns: NSString) -> [Int] {
        var map: [Int] = []
        map.reserveCapacity(ns.length)
        for i in 0..<ns.length {
            let unit = ns.character(at: i)
            if unit != 0x0A, unit != 0x0D { map.append(i) }
        }
        return map
    }

    /// Index du texte pour le caractère `glyph`, contrôlé par sa position : si PDFKit compte autrement
    /// (espaces ajoutées…), on cherche à côté le caractère qui est vraiment à cet endroit.
    private static func stringIndex(near guess: Int, glyph: Int, on page: PDFPage, string ns: NSString) -> Int? {
        let target = page.characterBounds(at: glyph)
        guard target.width > 0 || target.height > 0 else { return guess }
        let center = CGPoint(x: target.midX, y: target.midY)
        for delta in [0, -1, 1, -2, 2, -3, 3, -4, 4] {
            let i = guess + delta
            guard i >= 0, i < ns.length else { continue }
            let unit = ns.character(at: i)
            if unit == 0x0A || unit == 0x0D { continue }
            if let r = page.selection(for: NSRange(location: i, length: 1))?.bounds(for: page),
               r.insetBy(dx: -1, dy: -1).contains(center) { return i }
        }
        return nil
    }

    private func present(text: String, rects: [CGRect], anchor: CGPoint, context: LookupContext) {
        // Même mot que celui déjà affiché (le curseur bouge un peu) : on garde le popup.
        if let current = lookupRequest, current.text == text, lookupCharacterRects.first == rects.first { return }
        lookupCharacterRects = rects
        lookupContext = context
        lookupHighlight = Array(rects.prefix(1))
        let first = rects.first { !$0.isEmpty } ?? CGRect(origin: anchor, size: .zero)
        var vertical = false
        if rects.count > 1, !rects[0].isEmpty, !rects[1].isEmpty {
            vertical = abs(rects[1].midX - rects[0].midX) < rects[0].width * 0.5 && rects[1].midY > rects[0].midY
        }
        lookupRequest = LookupRequest(text: text, anchor: anchor, wordRect: first, vertical: vertical)
    }

    /// Le dictionnaire a reconnu `length` caractères : on surligne exactement le mot.
    func setLookupMatchLength(_ length: Int) {
        lookupHighlight = Array(lookupCharacterRects.prefix(max(1, length))).filter { !$0.isEmpty }
    }

    /// Cherche le texte sélectionné (menu iOS → « Dictionnaire »). Texte du PDF seulement.
    func lookupSelection() {
        guard let pdf, let selection = pdfView.currentSelection, let page = selection.pages.first,
              let raw = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        let index = pdf.index(for: page)
        guard presented.indices.contains(index) else { return }
        let pageRect = selection.bounds(for: page)
        let viewRect = pdfView.convert(pageRect, from: page)
        let line = page.selectionForLine(at: CGPoint(x: pageRect.midX, y: pageRect.midY))
        let context = LookupContext(source: presented[index].source, presentedIndex: index,
                                    sentence: line?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? raw,
                                    lineRect: line?.bounds(for: page) ?? pageRect, vertical: false)
        let text = String(raw.prefix(model.dictionary.profile.lookup.scanLength))
        pdfView.clearSelection()
        present(text: text, rects: [viewRect], anchor: CGPoint(x: viewRect.maxX, y: viewRect.minY), context: context)
    }

    /// Moteur pour lire une page scannée : le réglage du document (Auto = NDLOCR → PP-OCRv5 → Vision),
    /// jamais « texte du PDF » ici (on n'arrive là que si le texte intégré n'a rien donné).
    private func scanEngine(source: Int) async -> String {
        let choice = settings.ocrEngine
        let url = fileURL
        let resolved = await Task.detached(priority: .userInitiated) {
            OCRService.resolve(choice == .pdfText ? .auto : choice, url: url, pageIndex: source)
        }.value
        guard resolved == OCREngineID.pdfText else { return resolved }
        for id in [OCREngineID.ndlocr, OCREngineID.ppocr5] where OCRService.engine(id)?.isAvailable == true { return id }
        return OCREngineID.vision
    }

    /// « Titre · p. N » (numéro imprimé) de la page du mot cherché.
    var lookupSourceLabel: String? {
        lookupContext.map { "\(document.title) · p. \(document.pageLabel($0.source))" }
    }

    /// Image de la ligne du mot (agrandie de 40 % en épaisseur, 1200 px de large au plus), en JPEG.
    func lookupLineJPEG() -> Data? {
        guard let context = lookupContext, !context.lineRect.isEmpty,
              let page = pdf?.page(at: context.presentedIndex) else { return nil }
        var r = context.lineRect
        if context.vertical { r = r.insetBy(dx: -r.width * 0.2, dy: 0) } else { r = r.insetBy(dx: 0, dy: -r.height * 0.2) }
        // Repère de dessin de la page (rotation et cropBox compris).
        let crop = page.bounds(for: .cropBox)
        r = r.intersection(crop).applying(page.transform(for: .cropBox))
        guard r.width > 1, r.height > 1 else { return nil }
        let scale = min(1200 / r.width, 6)
        let size = CGSize(width: (r.width * scale).rounded(), height: (r.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -r.minX, y: -r.minY)
            page.draw(with: .cropBox, to: cg)
        }
        return image.jpegData(compressionQuality: 0.7)
    }

    func endLookup() {
        lookupRequest = nil
        lookupHighlight = []
        lookupCharacterRects = []
    }

    /// `cropBox` d'origine d'une page source (repère des résultats OCR).
    func originalBox(ofSource source: Int) -> CGRect? { originalBoxes[source] }

    /// Repère des résultats OCR d'une page source (cadre d'origine + rotation intrinsèque du PDF).
    func pageFrame(ofSource source: Int) -> PageFrame? {
        originalBoxes[source].map { PageFrame(box: $0, rotation: originalRotations[source] ?? 0) }
    }

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
    private func showOCR(_ ocr: OCRPage, source: Int) {
        realOCRMemo[source] = nil
        ink.setOCR(ocr, source: source)
        guard FuriganaLayer.enabled else { return }
        let key = ScanSharpening.key(documentId: document.id, page: source), url = fileURL
        Task.detached(priority: .utility) { [weak self] in
            guard !PDFTextEngine.hasTextLayer(url: url, pageIndex: source) else { return }
            let frame: PageFrame? = (try? PDFPool.withDocument(url) { doc -> PageFrame? in
                doc.page(at: source).map { PageFrame(box: $0.bounds(for: .cropBox), rotation: $0.rotation) }
            }) ?? nil
            guard let frame else { return }
            FuriganaLayer.set(FuriganaLayer.marks(from: ocr, frame: frame), for: key)
            await self?.pdfView.redrawVisiblePages()
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
    /// Page à afficher : juste après la dernière page visible, ou juste avant la première.
    /// (`goToNextPage` de PDFKit n'avance que d'une page : en double page, elle restait souvent
    /// dans la même double page et rien ne bougeait.)
    private func turnTarget(forward: Bool) -> PDFPage? {
        guard let pdf else { return nil }
        let visible = pdfView.visiblePages.map { pdf.index(for: $0) }.filter { $0 != NSNotFound }
        let lo = visible.min() ?? currentIndex, hi = visible.max() ?? currentIndex
        let i = forward ? hi + 1 : lo - 1
        return i >= 0 && i < pdf.pageCount ? pdf.page(at: i) : nil
    }

    private func turn(forward: Bool) {
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

    private func pageChanged() {
        guard let pdf, let page = pdfView.currentPage else { return }
        let index = pdf.index(for: page)
        guard index != NSNotFound, index != currentIndex || presented.isEmpty == false else { return }
        let changed = index != currentIndex
        currentIndex = index
        updateCurrentSourcePage()
        if changed, lookupRequest != nil { endLookup() }
        if changed, !rebuilding, settings.hideBarsOnScroll, barsVisible { barsVisible = false }
        scheduleSavePosition()
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
        // Mode économie d'énergie : rien d'avance (les miniatures se font quand on ouvre la bande).
        guard n > 0, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        let lower = max(0, source - n), upper = min(document.pageCount - 1, source + n)
        guard lower <= upper else { return }
        for page in lower...upper {
            // Même largeur que la bande des pages (`FilmstripCell`), sinon la préparation ne sert à rien.
            model.thumbnails.thumbnail(documentId: document.id, fileURL: fileURL, page: page, width: 120) { _ in }
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
        // Miniatures voisines et test « la page a du texte » seulement une fois la page posée
        // (pas à chaque page qui défile).
        preloadThumbnails(around: source)
        ink.trim(around: source)
        pageHasPDFText = false
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
        shownSources = visible
        focusSource = source
        scheduleSharpening(visible)
        scheduleFurigana(visible)
        Task { [weak self] in
            guard let self else { return }
            // Zones en cache pour toutes les pages visibles (double page).
            var missing: [Int] = []
            for page in visible {
                if let cached = await self.cachedOCR(source: page) {
                    self.showOCR(cached, source: page)
                    if page == self.focusSource { self.ocrPage = cached }
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
        case .ndlocr: return [OCREngineID.ndlocr]
        case .ppocr5: return [OCREngineID.ppocr5]
        case .glmocr: return [OCREngineID.glmocr]
        case .auto: return [OCREngineID.pdfText, OCREngineID.glmocr, OCREngineID.ndlocr, OCREngineID.ppocr5, OCREngineID.vision]
        }
    }

    /// OCR de la page par un moteur autre que « texte du PDF » (celui du panneau, sinon le cache).
    private func realOCR(source: Int) async -> OCRPage? {
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
    private func wordStart(in text: String, at offset: Int) async -> Int {
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
                let page = try await service.page(documentId: documentId, url: url, pageIndex: source, engine: engineID, force: force)
                guard let self, !Task.isCancelled else { return }
                self.showOCR(page, source: source)
                if self.focusSource == source {
                    self.ocrPage = page
                    self.ocrState = .idle
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

    private func cancelEnsureOCR() {
        ensureQueue = []
        ensureTask?.cancel()
        ensureTask = nil
    }

    func setShowOCRBoxes(_ on: Bool) {
        model.appSettings.showOCRBoxes = on
        ink.showOCRBoxes = on
        if on { pageSettled() }
    }

    func close() {
        savePositionWork?.perform()
        rereadTask?.cancel()
        cropTask?.cancel()
        sharpenTask?.cancel()
        furiganaTask?.cancel()
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

    // MARK: Gestes

    // FDR-1 : gestes / zoom « cassés » — pistes : tap simple qui attend l'échec du double-tap (~0,3 s), glisser en conflit avec le défilement, survol actif par défaut. Voir § 6 étape 1.
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
        pencilTap = UITapGestureRecognizer(target: self, action: #selector(handlePencilTap(_:)))
        pencilTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        pencilTap.cancelsTouchesInView = false
        pencilTap.delegate = self
        pencilTap.isEnabled = false
        hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        hover.delegate = self
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

    @objc private func handlePencilTap(_ gesture: UITapGestureRecognizer) {
        guard pencilLookup, !isDrawing else { return }
        let point = gesture.location(in: pdfView)
        Task { await lookup(at: point) }
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        guard hoverLookup, !isDrawing, gesture.state == .began || gesture.state == .changed else {
            hoverTask?.cancel()
            return
        }
        let point = gesture.location(in: pdfView)
        // Toujours sur le mot affiché : rien à refaire.
        if lookupHighlight.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(point) }) {
            hoverTask?.cancel()
            return
        }
        hoverTask?.cancel()
        // Petit délai : on cherche quand le curseur se pose, pas à chaque pixel.
        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.lookup(at: point, fromHover: true)
        }
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
        // Note en attente d'ancre : ce toucher la pose (sur le mot touché s'il y en a un).
        if let note = placingAnchorFor {
            placingAnchorFor = nil
            placeAnchor(for: note, at: point)
            return
        }
        if lookupMode {
            Task { await lookup(at: point) }
            return
        }
        // Popup ouvert par le survol : un clic ailleurs le ferme (sans tourner la page).
        if lookupRequest != nil {
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
        barsVisible.toggle()
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

    // MARK: Relecture de l'OCR

    static let aiRereadKey = "ocr.aiReread"
    /// Relecture IA en cours sur la page de travail.
    @Published private(set) var rereading = false
    private var rereadTask: Task<Void, Never>?

    /// Page de travail : relecture par le dictionnaire si pas encore faite (pages en cache d'avant, dictionnaire
    /// chargé après l'OCR), puis lignes douteuses à GLM-OCR.
    private func refineOCR() {
        guard let page = ocrPage, page.engine != OCREngineID.pdfText else { return }
        guard page.proofread != true else { rereadDoubtful(); return }
        let source = focusSource, documentId = document.id, service = model.ocr
        let process = AppModel.proofreader(model.dictionary)
        Task { [weak self] in
            let read = await process(page)
            guard let self, self.ocrPage == page else { return }
            // Pas de dictionnaire : seules les lignes peu sûres partent à GLM-OCR.
            guard read.proofread == true else { self.rereadDoubtful(); return }
            try? await service.store(read, documentId: documentId, pageIndex: source)
            self.showOCR(read, source: source)
            self.ocrPage = read
        }
    }

    /// Lignes douteuses de la page de travail relues par GLM-OCR (installé, option active ou demande directe).
    func rereadDoubtful(force: Bool = false) {
        guard let page = ocrPage, page.engine != OCREngineID.pdfText, force || page.reread != true else { return }
        guard force || UserDefaults.standard.object(forKey: Self.aiRereadKey) as? Bool ?? true else { return }
        let engine = GLMOCREngine()
        let lines = OCRProofreader.doubtful(page)
        guard engine.isAvailable, !lines.isEmpty else { return }
        // Une seule relecture à la fois : la précédente (autre version de la page) est abandonnée.
        rereadTask?.cancel()
        let source = focusSource, url = fileURL, documentId = document.id, service = model.ocr
        rereading = true
        rereadTask = Task { [weak self] in
            defer { if !Task.isCancelled { self?.rereading = false } }
            guard let read = try? await Diagnostics.measure("GLM-OCR relit \(lines.count) ligne(s) p. \(source)", "relecture", {
                      try await engine.reread(page, lines: lines, input: .pdfPage(url: url, index: source))
                  }),
                  !Task.isCancelled, let self,
                  // Page changée entre-temps (correction à la main, autre OCR) : résultat jeté.
                  self.ocrPage == page else { return }
            try? await service.store(read, documentId: documentId, pageIndex: source)
            self.showOCR(read, source: source)
            if self.focusSource == source { self.ocrPage = read }
        }
    }

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

    @Published private(set) var verifyState: VerifyState = .idle
    @Published var verifications: [PageVerification] = []
    private var verifyTask: Task<Void, Never>?
    /// Acceptations appliquées l'une après l'autre (jamais deux écritures de la même page en même temps).
    private var acceptChain: Task<Void, Never>?

    /// Relit les pages affichées (double page : les deux) avec OvisOCR2 et propose les lignes qui diffèrent.
    /// Rien n'est changé sans accord ; le modèle est libéré à la fin.
    func verifyShownPages() {
        guard OvisOCR2Reader().isAvailable else { return }
        verifyTask?.cancel()
        let sources = shownSources, url = fileURL, service = model.ocr
        verifications = []
        verifyState = .running(done: 0, total: sources.count)
        verifyTask = Task { [weak self] in
            for (k, source) in sources.enumerated() {
                guard let self, !Task.isCancelled else { return }
                var result = PageVerification(source: source, suggestions: [])
                let page = source == self.focusSource ? self.ocrPage : nil
                let ocr: OCRPage?
                if let page {
                    ocr = page
                } else {
                    let cached = await self.cachedOCR(source: source)
                    if let cached { ocr = cached } else {
                        let engine = await self.scanEngine(source: source)
                        ocr = try? await service.page(documentId: self.document.id, url: url, pageIndex: source, engine: engine)
                    }
                }
                result.engine = ocr?.engine
                if let ocr {
                    do {
                        let markdown = try await Diagnostics.measure("OvisOCR2 page \(source)", "verif") {
                            try await OvisOCR2Reader().read(.pdfPage(url: url, index: source),
                                                            maxTokens: DocumentAnalysisService.tokenBudget(ocr))
                        }
                        Diagnostics.log("OvisOCR2 page \(source) : \(markdown.count) caractères lus", "verif")
                        // Gardé : sert aussi à la vue « Mise en page IA » du panneau Texte.
                        let file = DocumentAnalysisService.rawURL(self.document.id, ModelSpec.ovisocr2.id, source)
                        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? markdown.write(to: file, atomically: true, encoding: .utf8)
                        result.suggestions = OCRReferenceDiff.suggestions(ocr, reference: markdown)
                        Diagnostics.log("page \(source) : \(result.suggestions.count) différence(s)", "verif")
                    } catch {
                        result.error = error.localizedDescription
                    }
                } else {
                    result.error = "Page pas encore lue par l'OCR."
                }
                guard !Task.isCancelled else { return }
                self.verifications.append(result)
                self.verifyState = .running(done: k + 1, total: sources.count)
            }
            // Seul OvisOCR2 est libéré (GLM-OCR peut servir à la relecture des lignes douteuses).
            await OvisOCR2Reader().unload()
            self?.verifyState = .done
        }
    }

    func cancelVerification() {
        let task = verifyTask
        task?.cancel()
        verifyState = .idle
        // Libéré une fois la génération arrêtée (elle s'arrête au jeton suivant).
        Task { await task?.value; await OvisOCR2Reader().unload() }
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
        var line = line
        if text.count != line.charBoxes.count {
            line.charBoxes = CharacterLayout.proportional(text, in: line.box, vertical: line.vertical)
            line.measuredCharBoxes = false
        }
        line.text = text
        line.edited = true
        line.doubt = []
        return line
    }

    /// Correction à la main d'une ligne (gardée : la relecture automatique n'y touche plus).
    func correctOCRLine(_ index: Int, text: String) {
        guard var page = ocrPage, page.lines.indices.contains(index) else { return }
        rereadTask?.cancel()
        rereading = false
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

    // MARK: Notes (fenêtre flottante, ancres)

    /// Nouvelle note sur la page de travail, ouverte tout de suite dans la fenêtre flottante.
    func newNote() {
        let note = PageComment(documentId: document.id, pageIndex: focusSource, body: "")
        notes.append(note)
        model.persist { try $0.save(note) }
        openNote = note
    }

    /// Enregistre une note modifiée (texte, dessin ou ancre) et met son ancre à jour sur la page.
    func saveNote(_ note: PageComment) {
        var note = note
        note.updatedAt = Date()
        let old = notes.first { $0.id == note.id }
        if let i = notes.firstIndex(where: { $0.id == note.id }) { notes[i] = note } else { notes.append(note) }
        if openNote?.id == note.id { openNote = note }
        model.persist { try $0.save(note) }
        // Pastille refaite seulement si l'ancre a bougé (pas à chaque mot tapé).
        if let pdf, old?.anchorRect != note.anchorRect || old?.pageIndex != note.pageIndex {
            if let old { removeAnchor(old, in: pdf) }
            annotateAnchor(note, in: pdf)
        }
    }

    func deleteNote(_ note: PageComment) {
        notes.removeAll { $0.id == note.id }
        if openNote?.id == note.id { openNote = nil }
        if placingAnchorFor?.id == note.id { placingAnchorFor = nil }
        if let pdf { removeAnchor(note, in: pdf) }
        model.persist { try $0.deleteComment(id: note.id) }
    }

    /// Notes rechargées (ajoutées depuis le panneau d'étude).
    func reloadNotes() {
        notes = (try? model.database.comments(documentId: document.id)) ?? notes
        guard let pdf else { return }
        for note in notes { removeAnchor(note, in: pdf); annotateAnchor(note, in: pdf) }
    }

    private func placeAnchor(for note: PageComment, at point: CGPoint) {
        guard let pdf, let page = pdfView.page(for: point, nearest: false) else { return }
        let index = pdf.index(for: page)
        guard presented.indices.contains(index) else { return }
        let pagePoint = pdfView.convert(point, to: page)
        guard var note = notes.first(where: { $0.id == note.id }) else { return }
        // Mot sous le doigt (texte du PDF), sinon un petit carré autour du point.
        let word = page.selectionForWord(at: pagePoint)
        let text = word?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rect: CGRect
        if let bounds = word?.bounds(for: page), !text.isEmpty, bounds.width < 400, bounds.height < 200 {
            rect = bounds
        } else {
            rect = CGRect(x: pagePoint.x - 10, y: pagePoint.y - 10, width: 20, height: 20)
        }
        note.pageIndex = presented[index].source
        note.anchorRect = PageRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        note.anchorText = text.isEmpty ? nil : String(text.prefix(30))
        saveNote(note)
    }

    /// Va à l'ancre de la note et fait clignoter le mot ancré 1,5 s.
    func goToAnchor(_ note: PageComment) {
        guard let rect = note.anchorRect else { go(toSource: note.pageIndex); return }
        go(toSource: note.pageIndex)
        guard let pdf else { return }
        let bounds = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height).insetBy(dx: -3, dy: -3)
        var added: [(PDFPage, PDFAnnotation)] = []
        for page in pages(forSource: note.pageIndex, in: pdf) where page.bounds(for: .cropBox).intersects(bounds) {
            let flash = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            flash.color = UIColor.systemYellow.withAlphaComponent(0.6)
            flash.userName = "flash"
            page.addAnnotation(flash)
            added.append((page, flash))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for (page, flash) in added { page.removeAnnotation(flash) }
        }
    }

    private func annotateAnchor(_ note: PageComment, in pdf: PDFDocument) {
        guard let rect = note.anchorRect else { return }
        let size: CGFloat = max(14, min(26, rect.height * 0.8))
        // Pastille « ＊ » au coin haut-droit du mot.
        let badge = CGRect(x: rect.x + rect.width - size * 0.3, y: rect.y + rect.height - size * 0.5, width: size, height: size)
        for page in pages(forSource: note.pageIndex, in: pdf) where page.bounds(for: .cropBox).intersects(badge) {
            let annotation = NoteAnchorAnnotation(bounds: badge, forType: .stamp, withProperties: nil)
            annotation.userName = "note:" + note.id
            page.addAnnotation(annotation)
        }
    }

    private func removeAnchor(_ note: PageComment, in pdf: PDFDocument) {
        for page in pages(forSource: note.pageIndex, in: pdf) {
            for annotation in page.annotations where annotation.userName == "note:" + note.id { page.removeAnnotation(annotation) }
        }
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
            let bookmark = Bookmark(documentId: document.id, pageIndex: page, title: "Page \(document.pageLabel(page))")
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
        // Page entière, sans découpe automatique en jeu : on tourne sur place (pas de reconstruction).
        if !isBuilding, let pdf, !settings.splitWidePages, !splitSources.contains(source), let base = originalRotations[source] {
            for page in pages(forSource: source, in: pdf) { page.rotation = ((base + t.rotation) % 360 + 360) % 360 }
            pdfView.layoutDocumentView()
            if pdfView.isAtFit { pdfView.fitToPage() }
            return
        }
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
                // Petits lots autour de la page lue (vite visibles), puis gros lots : chaque lot
                // relance la mise en page de tout le document.
                if batch.count >= (n < 8 ? 4 : 80) || n == ordered.count - 1 {
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
        // Pages affichées de chaque page source, calculées une fois (au lieu d'un parcours par page).
        var pagesBySource: [Int: [PDFPage]] = [:]
        for (i, p) in presented.enumerated() where crops[p.source] != nil {
            if let page = pdf.page(at: i) { pagesBySource[p.source, default: []].append(page) }
        }
        for (index, crop) in crops {
            var t = transforms[index] ?? PageTransform(documentId: documentId, pageIndex: index)
            t.autoCrop = crop
            transforms[index] = t
            toSave.append(t)
            guard !splitSources.contains(index), let box = originalBoxes[index] else { continue }
            for page in pagesBySource[index] ?? [] {
                page.setBounds(ContentBounds.apply(crop, to: box), for: .cropBox)
            }
        }
        model.persist { try $0.save(toSave) }
        pdfView.layoutDocumentView()
        // Les tailles de page ont changé : recalcul de l'échelle « page entière » (sauf si zoomé).
        if pdfView.isAtFit { pdfView.fitToPage() }
    }

    // MARK: Recherche

    /// Résultats reçus mais pas encore affichés : la liste est mise à jour par lots (4 fois par seconde)
    /// au lieu d'être triée et redessinée à chaque résultat (lent sur un mot fréquent).
    private var pendingResults: [SearchResult] = []
    /// Numéro de la recherche en cours : les résultats OCR d'une ancienne recherche sont ignorés.
    private var searchToken = 0
    private var flushScheduled = false
    static let maxSearchResults = 500

    private func enqueue(_ result: SearchResult) {
        guard searchResults.count + pendingResults.count < Self.maxSearchResults else { return }
        pendingResults.append(result)
        if searchResults.count + pendingResults.count >= Self.maxSearchResults {
            pdf?.cancelFindString()
            isSearching = false
            flushResults()
            return
        }
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.flushResults() }
    }

    private func flushResults() {
        flushScheduled = false
        guard !pendingResults.isEmpty else { return }
        // Une page trouvée dans le texte du PDF n'a pas besoin du résultat OCR en plus.
        let pdfPages = Set((searchResults + pendingResults).filter { !$0.fromOCR }.map(\.sourcePage))
        searchResults.removeAll { $0.fromOCR && pdfPages.contains($0.sourcePage) }
        pendingResults.removeAll { $0.fromOCR && pdfPages.contains($0.sourcePage) }
        // Tri par page de lecture (l'ordre interne peut différer en droite → gauche), stable.
        let all = (searchResults + pendingResults).enumerated()
            .sorted { $0.element.sourcePage != $1.element.sourcePage ? $0.element.sourcePage < $1.element.sourcePage : $0.offset < $1.offset }
            .map(\.element)
        pendingResults = []
        searchResults = all
    }

    func search(_ query: String) {
        guard let pdf else { return }
        pdf.cancelFindString()
        searchResults = []
        pendingResults = []
        searchToken += 1
        let token = searchToken
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
        let engines = [OCREngineID.glmocr, OCREngineID.ndlocr, OCREngineID.ppocr5, OCREngineID.vision]
        let service = model.ocr
        Task { [weak self] in
            let hits = await service.search(trimmed, documentId: documentId, engines: engines)
            guard let self, token == self.searchToken else { return }
            let pdfPages = Set((self.searchResults + self.pendingResults).filter { !$0.fromOCR }.map(\.sourcePage))
            for hit in hits where !pdfPages.contains(hit.page) {
                let index = PresentationLayout.presentedIndex(ofSource: hit.page, in: self.presented)
                self.enqueue(SearchResult(selection: nil, presentedIndex: index, sourcePage: hit.page,
                                          context: "📷 " + hit.context.replacingOccurrences(of: "\n", with: " ")))
            }
            self.flushResults()
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

    /// Pages données (sources) en une image : côte à côte dans l'ordre affiché (double page « les deux »).
    func renderSources(_ sources: [Int], maxWidth: CGFloat = 2048) -> UIImage? {
        guard let pdf else { return nil }
        let pages: [PDFPage] = presented.indices.filter { sources.contains(presented[$0].source) }.compactMap { pdf.page(at: $0) }
        guard !pages.isEmpty else { return nil }
        let sizes = pages.map { page -> CGSize in
            let box = page.bounds(for: .cropBox)
            return page.rotation % 180 != 0 ? CGSize(width: box.height, height: box.width) : box.size
        }
        let height = sizes.map(\.height).max() ?? 1
        let totalWidth = sizes.reduce(0) { $0 + $1.width * height / max($1.height, 1) }
        let scale = maxWidth / max(totalWidth, 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: totalWidth * scale, height: height * scale), format: format).image { _ in
            var x: CGFloat = 0
            for (page, size) in zip(pages, sizes) {
                let w = size.width * height / max(size.height, 1) * scale
                let h = height * scale
                page.thumbnail(of: CGSize(width: w, height: h), for: .cropBox).draw(in: CGRect(x: x, y: 0, width: w, height: h))
                x += w
            }
        }
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
    /// Même classe que pendant la construction (fond doux / inversé), pour toute page créée ensuite.
    nonisolated func classForPage() -> AnyClass { TonedPage.self }

    nonisolated func didMatchString(_ instance: PDFSelection) {
        MainActor.assumeIsolated {
            guard let pdf, let page = instance.pages.first else { return }
            // Liste pleine : pas la peine de calculer le contexte (la recherche va s'arrêter).
            // Reste sur le fil principal : le document affiché n'est pas sûr entre fils.
            guard searchResults.count + pendingResults.count < Self.maxSearchResults else { return }
            let index = pdf.index(for: page)
            let context = instance.copy() as? PDFSelection
            context?.extend(atStart: 20)
            context?.extend(atEnd: 30)
            let text = (context?.string ?? instance.string ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let source = presented.indices.contains(index) ? presented[index].source : index
            enqueue(SearchResult(selection: instance, presentedIndex: index, sourcePage: source, context: text))
        }
    }

    nonisolated func documentDidEndDocumentFind(_ notification: Notification) {
        MainActor.assumeIsolated {
            isSearching = false
            flushResults()
        }
    }
}

// MARK: - Vue PDF

/// `PDFView` qui garde l'échelle « page entière » à jour quand la taille change (rotation, Split View).
final class ReaderPDFView: PDFView {
    private var lastSize: CGSize = .zero
    /// Action « Dictionnaire » du menu de sélection d'iOS (Copier, Rechercher…).
    var onLookupSelection: (() -> Void)?

    /// Redessine les pages affichées sans reconstruire le document (page nettoyée prête, réglage changé).
    func redrawVisiblePages() {
        // Les vues seulement (leur calque suit) : forcer les calques eux-mêmes peut vider des images de PDFKit.
        func walk(_ view: UIView) {
            view.setNeedsDisplay()
            view.subviews.forEach(walk)
        }
        walk(self)
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard let onLookupSelection, currentSelection?.string?.isEmpty == false else { return }
        let action = UIAction(title: "Dictionnaire", image: UIImage(systemName: "character.book.closed.ja")) { _ in
            onLookupSelection()
        }
        builder.insertSibling(UIMenu(options: .displayInline, children: [action]), beforeMenu: .standardEdit)
    }
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

/// Ancre d'une note sur la page : pastille couleur annotation avec un astérisque.
final class NoteAnchorAnnotation: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        context.setFillColor(UIColor(red: 0.95, green: 0.68, blue: 0.20, alpha: 0.95).cgColor)
        context.fillEllipse(in: rect)
        context.saveGState()
        // Repère de la page (y vers le haut) : retourner pour écrire le texte à l'endroit.
        context.translateBy(x: 0, y: rect.midY * 2)
        context.scaleBy(x: 1, y: -1)
        let font = UIFont.systemFont(ofSize: rect.height * 0.8, weight: .heavy)
        let text = NSAttributedString(string: "*", attributes: [.font: font, .foregroundColor: UIColor.black])
        let size = text.size()
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height * 0.38))
        context.restoreGState()
    }
}
