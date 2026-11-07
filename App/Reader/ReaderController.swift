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
/// surlignages, signets, recherche, sauvegarde de la position. Fichier principal : état, chargement, dictionnaire au
/// toucher, notifications ; le reste par thème dans `ReaderController+*.swift`.
@MainActor
final class ReaderController: NSObject, ObservableObject {
    let model: AppModel
    @Published var document: LibraryDocument
    let pdfView = ReaderPDFView()
    let ink: InkStore

    @Published var settings: ReaderSettings
    @Published var pdf: PDFDocument?
    @Published private(set) var presented: [PresentedPage] = []
    @Published var currentIndex = 0
    @Published var barsVisible = true {
        didSet {
            barsChangedAt = ProcessInfo.processInfo.systemUptime
            // La flèche ou un autre geste a déjà décidé : un toucher encore en attente d'OCR ne doit plus rien changer.
            tapLookupGeneration += 1
        }
    }
    /// Change à chaque geste qui rend périmée une recherche lancée par un toucher (nouveau toucher, page, mode, fermeture).
    /// L'OCR peut durer plusieurs secondes : sans cela, le toucher agirait sur une page que l'utilisateur a déjà quittée.
    var tapLookupGeneration = 0
    /// Dernier changement des barres : voir `ReaderBarsPolicy.settleDelay`.
    var barsChangedAt: TimeInterval = 0
    @Published var isDrawing = false
    @Published var hasSelection = false
    @Published var bookmarks: [Bookmark] = []
    @Published var tappedHighlight: Highlight?
    /// Note ouverte dans la fenêtre flottante.
    @Published var openNote: PageComment?
    /// Note qui attend son ancre : le prochain toucher sur la page la pose.
    @Published var placingAnchorFor: PageComment?
    /// Notes du document (ancres affichées sur les pages).
    @Published var notes: [PageComment] = []
    @Published var loadError: String?
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    /// OCR de la page lue (première page lue en double page).
    /// OCR de la page de travail (`focusSource`) : panneau Texte / Mots.
    @Published var ocrPage: OCRPage? {
        // Nouvelle page de travail lue : ses lignes douteuses partent à GLM-OCR (s'il est installé et l'option active).
        didSet {
            if ocrPage != nil, oldValue?.lines != ocrPage?.lines || oldValue == nil {
                DispatchQueue.main.async { [weak self] in self?.refineOCR() }
            }
        }
    }
    /// Pages affichées (deux en double page) et celle choisie dans le panneau (pilules).
    @Published var shownSources: [Int] = []
    @Published var focusSource = 0
    @Published var ocrState: OCRState = .idle

    // MARK: État des extensions (ReaderController+*.swift : une extension ne peut pas en avoir)

    /// Dernier calcul de furigana OCR lancé par page (`showOCR`).
    var furiganaGeneration: [Int: Int] = [:]
    /// Calcul en cours par page : annulé quand un plus récent le remplace, il ne consomme plus pour rien.
    var pageFuriganaTasks: [Int: Task<Void, Never>] = [:]
    /// Orientation de l'écran du lecteur (`adaptLayout`) ; `nil` tant qu'elle n'est pas connue.
    var portraitMode: Bool?
    /// Préparation des pages teintées voisines (`scheduleTone`).
    var toneTask: Task<Void, Never>?
    var isAnimatingTurn = false
    /// Page courante au dernier `pageSettled` (voir `schedulePageSettled`).
    var settledSource: Int?
    /// Page de travail choisie à la main (pilule du panneau) : gardée tant qu'elle reste visible.
    var pinnedFocus: Int?
    @Published var verifyState: VerifyState = .idle
    @Published var verifications: [PageVerification] = []
    /// Acceptations appliquées l'une après l'autre (jamais deux écritures de la même page en même temps).
    var acceptChain: Task<Void, Never>?
    /// Résultats reçus mais pas encore affichés : la liste est mise à jour par lots (4 fois par seconde)
    /// au lieu d'être triée et redessinée à chaque résultat (lent sur un mot fréquent).
    var pendingResults: [SearchResult] = []
    /// Numéro de la recherche en cours : les résultats OCR d'une ancienne recherche sont ignorés.
    var searchToken = 0
    var flushScheduled = false

    // MARK: Dictionnaire au toucher
    /// Modes d'outil gardés **pour ce document** (écriture, 辞, Pencil), relus à l'ouverture (Issue #15).
    let toolModes = ReaderToolModeStore()

    /// Outil « dictionnaire » actif : un tap sur un caractère cherche le mot.
    @Published var lookupMode = false {
        didSet {
            toolModes.update(documentId: document.id) { [lookupMode] in $0.lookup = lookupMode }
            tapLookupGeneration += 1
        }
    }
    /// Mode dessin à rétablir une fois le document installé (les surcouches PencilKit doivent exister).
    var pendingDrawingRestore = false
    /// Demande de recherche (texte à partir du caractère touché, point d'ancrage dans la vue).
    @Published var lookupRequest: LookupRequest?
    /// Rectangles (repère de la vue PDF) du texte touché puis du mot reconnu.
    @Published var lookupHighlight: [CGRect] = []
    /// Mode « Surligner l'OCR » (#23) : glisser sur les zones de l'OCR surligne au lieu de faire défiler.
    @Published var ocrHighlightMode = false
    /// Geste à un doigt du mode surlignage, créé à sa première activation.
    var ocrHighlightPan: UIPanGestureRecognizer?
    /// Toucher simple de la gomme, à côté du glisser (revue après recette 1.4.8, P2 5).
    var ocrEraseTap: UITapGestureRecognizer?
    /// Double page paginée : pan interne limité à un doigt pour laisser démarrer le pincement (`tuneDoublePageGestures`).
    var doublePagePanTuned = false
    /// Recalage « page entière » prévu après le zoom arrière animé ; annulé par la prochaine interaction.
    var pendingFitToPage: DispatchWorkItem?
    /// Aperçu du surlignage en cours (repère de la vue PDF).
    @Published var ocrHighlightPreview: [CGRect] = []
    /// Glisser en cours : page, OCR, cadre et premier caractère (fixés à l'appui).
    var ocrHighlightDrag: OCRHighlightDrag?
    /// +1 à chaque relâchement : un appui dont la lecture de l'OCR finit après le relâchement est ignoré.
    var ocrHighlightGeneration = 0
    /// Gomme du mode « Surligner l'OCR » (recette 62, L5) : glisser efface les surlignages touchés.
    @Published var ocrHighlightErasing = false
    /// Annulation (⌘Z ou bouton) des surlignages faits ou effacés dans le mode, le plus récent en dernier.
    @Published var highlightUndo: [HighlightChange] = []

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
        didSet {
            UserDefaults.standard.set(hoverLookup, forKey: "reader.hoverLookup")
            Diagnostics.log("Survol activé=\(hoverLookup)", "lookup")
        }
    }
    /// La page a du texte (intégré ou OCR) : l'option de survol a un sens.
    var pageHasText: Bool { ocrPage != nil || pageHasPDFText }
    /// Texte intégré à la page lue : calculé une fois par page, hors du fil principal (et plus à
    /// chaque rafraîchissement de l'écran, ce qui relisait tout le texte de la page).
    @Published var pageHasPDFText = false
    /// Texte de la page touchée / survolée, gardé pour les recherches suivantes sur la même page.
    /// Texte de la page sous le curseur + correspondance « index de `characterIndex(at:)` → index du texte ».
    var pageStringCache: (index: Int, string: NSString, map: [Int], hasText: Bool)?
    /// `realOCR` des pages hors panneau (évite une lecture du cache SQLite à chaque survol) ; vidé à chaque OCR.
    var realOCRMemo: [Int: OCRPage?] = [:]
    /// Moteur choisi dans le menu du panneau Texte pour une page, tant que le lecteur est ouvert (décision D2 de
    /// NOxygen59 du 07/11/2026) : il reste celui de la page aux gestes suivants. « Garder pour ce document » en fait
    /// le réglage du document. Vidé quand le réglage du moteur change.
    @Published var pinnedEngines: [Int: String] = [:]
    /// Moteur de l'**OCR retenu** de chaque page (`OCRSelectionPolicy`). Seul un résultat de ce moteur peut alimenter
    /// les zones et les furigana (`showOCR`) : une lecture d'un autre moteur, arrivée en retard ou venue d'un autre
    /// chemin, ne remplace plus les furigana (enquête furigana iPad / Mac du 07/11/2026 : 223 lectures, puis 74).
    var selectedEngines: [Int: String] = [:]
    /// Début de mot par caractère, par ligne de texte (découpage du dictionnaire), pour le survol.
    var wordStartMemo: [String: [Int]] = [:]
    var pageTextTask: Task<Void, Never>?
    var sharpenTask: Task<Void, Never>?
    var furiganaTask: Task<Void, Never>?
    /// File de `ensureOCR` : pages à lire, page en cours, tâche unique.
    var ensureQueue: [Int] = []
    var ensuringPage: Int?
    var ensureTask: Task<Void, Never>?
    var hover: UIHoverGestureRecognizer!
    var pencilTap: UITapGestureRecognizer!
    /// Le Pencil cherche le mot touché dans le dictionnaire (au lieu de dessiner ou d'afficher les barres).
    /// Rétabli seulement si l'option des réglages qui affiche son bouton est encore active.
    @Published var pencilLookup = false {
        didSet {
            toolModes.update(documentId: document.id) { [pencilLookup] in $0.pencilLookup = pencilLookup }
            applyPencilLookupGestures()
        }
    }

    /// Le doigt et la souris gardent le tap normal ; le Pencil passe par `pencilTap`.
    /// Aussi appelé après `configureGestures`, car `didSet` ne s'exécute pas pour la valeur initiale.
    func applyPencilLookupGestures() {
        let all: [UITouch.TouchType] = pencilLookup ? [.direct, .indirect, .indirectPointer] : [.direct, .indirect, .indirectPointer, .pencil]
        singleTap?.allowedTouchTypes = all.map { NSNumber(value: $0.rawValue) }
        pencilTap?.isEnabled = pencilLookup
    }
    var hoverTask: Task<Void, Never>?
    /// Dernière recherche au survol lancée grâce à Maj seule (bouton de survol éteint) : relâcher Maj la ferme
    /// (RET-021, #24).
    var lookupOpenedByShiftOnly = false
    private var lookupDiagnosticTimes: [String: Date] = [:]

    /// Trace bornée du trajet du pointeur, sans texte, titre ou identifiant du document.
    func traceLookup(_ stage: String) {
        guard Diagnostics.enabled, Date().timeIntervalSince(lookupDiagnosticTimes[stage] ?? .distantPast) >= 1 else { return }
        lookupDiagnosticTimes[stage] = Date()
        Diagnostics.log("\(stage) ; page=\(focusSource + 1) ; actif=\(hoverLookup) ; dessin=\(isDrawing) ; fermé=\(closed)", "lookup")
    }

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
    var lookupCharacterRects: [CGRect] = []

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
    @Published var documentOCRProgress: (done: Int, total: Int)?
    var documentOCRTask: Task<Void, Never>?

    var transforms: [Int: PageTransform] = [:]
    var highlights: [Highlight] = []
    /// Boîte et rotation d'origine de chaque page source (avant nos transformations).
    var originalBoxes: [Int: CGRect] = [:]
    var originalRotations: [Int: Int] = [:]
    /// Pages sources coupées en deux (réglage global ou manuel) : jamais rognées en entier.
    var splitSources: Set<Int> = []
    /// Vrai pendant une reconstruction : le changement de page qui en résulte n'est pas un geste.
    var rebuilding = false
    var observers: [NSObjectProtocol] = []
    /// Fin d'une tâche IA (peut-être lancée par un lecteur précédent) : la page affichée est relue du cache.
    var aiFinished: AnyCancellable?
    /// Seul le dernier rechargement demandé peut publier après une attente du cache.
    var ocrReloadRevision: UInt64 = 0
    var savePositionWork: DispatchWorkItem?
    var cropTask: Task<Void, Never>?
    var ocrTask: Task<Void, Never>?
    var settleWork: DispatchWorkItem?
    var pointerSelect: UIPanGestureRecognizer!
    var singleTap: UITapGestureRecognizer!
    var doubleTap: UITapGestureRecognizer!
    var swipeLeft: UISwipeGestureRecognizer!
    var trackpadPageTurn: UIPanGestureRecognizer!
    /// Appui long en cours ou terminé (sélection de texte de PDFKit) : le tap qui suit est ignoré.
    var pressWasLong = false
    /// Début d'une sélection au doigt (page, point dans la page).
    var selectionAnchor: (PDFPage, CGPoint)?
    var longPressWatcher: UILongPressGestureRecognizer!
    var swipeRight: UISwipeGestureRecognizer!

    init(document: LibraryDocument, model: AppModel) {
        self.document = document
        self.model = model
        var initial = model.settings(for: document)
        // « Auto » : double page tant que l'orientation n'est pas connue (`adaptLayout` corrige à l'ouverture).
        if initial.layout == .auto { initial.layout = .double }
        self.settings = initial
        self.currentSourcePage = document.lastPageIndex
        self.ink = InkStore(documentId: document.id, model: model)
        super.init()
        // Modes de ce livre. On n'affecte que les modes actifs (les `didSet` réécrivent alors la même valeur) :
        // si l'option Pencil des réglages est coupée, le choix enregistré du livre est gardé, pas effacé.
        // Les gestes du Pencil sont appliqués par `configureGestures` juste après.
        let saved = toolModes.modes(documentId: document.id)
        if saved.lookup { lookupMode = true }
        if saved.pencilLookup, UserDefaults.standard.bool(forKey: "pencil.lookupOption") { pencilLookup = true }
        pendingDrawingRestore = saved.drawing
        ink.controller = self
        configureGestures()
        pdfView.onLookupSelection = { [weak self] in self?.lookupSelection() }
        observe()
    }

    var fileURL: URL { model.storage.url(for: document.id) }

    /// Page source en cours de lecture. En double page, la première page *lue* de la double page
    /// (celle de droite en lecture droite → gauche), pas la première dans l'ordre interne.
    @Published var currentSourcePage = 0

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
    struct Built: @unchecked Sendable {
        let pdf: PDFDocument
        let boxes: [Int: CGRect]
        let rotations: [Int: Int]
        let splits: Set<Int>
        let presented: [PresentedPage]
        /// Rotations à poser sur le fil principal (voir `install`), moitiés de pages découpées comprises.
        let pendingRotations: [(page: PDFPage, degrees: Int)]
        /// Cadres à poser sur le fil principal : `setBounds` notifie UIKit comme `rotation` (découpe, recette 1.3.2 (74)).
        let pendingBounds: [(page: PDFPage, box: CGRect)]
    }

    /// PDF aux pages de même hauteur (`Caches/Equalized/<id>-<taille>-<date>.pdf`) et cadres d'origine des pages
    /// (`.json`). `nil` : aucune page à changer (le PDF d'origine sert tel quel). Fait une fois par version du
    /// fichier : ajouter des pages change sa taille et sa date, donc la préparation est refaite une fois.
    nonisolated static func equalizedDocument(url: URL, documentId: String) -> (pdf: PDFDocument, sourceBoxes: [CGRect])? {
        let fm = FileManager.default
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let stamp = "\(values?.fileSize ?? 0)-\(Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0))"
        let folder = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Equalized", isDirectory: true)
        let base = folder.appendingPathComponent("\(documentId)-\(stamp)")
        let pdfFile = base.appendingPathExtension("pdf"), boxesFile = base.appendingPathExtension("json")
        if let data = try? Data(contentsOf: boxesFile), let saved = try? JSONDecoder().decode([[CGFloat]].self, from: data) {
            // Déjà préparé : liste vide = rien à changer dans ce PDF.
            guard !saved.isEmpty, let pdf = PDFDocument(url: pdfFile), pdf.pageCount == saved.count else { return nil }
            return (pdf, saved.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) })
        }
        guard let original = PDFDocument(url: url), let common = commonHeight(original) else { return nil }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        // Anciennes versions préparées de ce document : supprimées.
        for old in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix(documentId + "-") { try? fm.removeItem(at: old) }
        var boxes: [CGRect] = []
        var pages: [PDFPage] = []
        var helpers: [PDFDocument] = []
        var rescaled = false
        for i in 0..<original.pageCount {
            guard let page = original.page(at: i) else { return nil }
            let box = page.bounds(for: .cropBox)
            boxes.append(box)
            let height = page.rotation % 180 == 0 ? box.height : box.width
            if height > 0, abs(common / height - 1) > 0.03, let (scaled, doc) = scaledPage(page, factor: common / height) {
                pages.append(scaled)
                helpers.append(doc)
                rescaled = true
            } else {
                pages.append(page)
            }
        }
        guard rescaled else {
            try? JSONEncoder().encode([[CGFloat]]()).write(to: boxesFile, options: .atomic)
            return nil
        }
        let output = PDFDocument()
        for (i, page) in pages.enumerated() {
            guard let copy = page.copy() as? PDFPage else { return nil }
            output.insert(copy, at: i)
        }
        let temporary = folder.appendingPathComponent(UUID().uuidString + ".pdf")
        guard output.write(to: temporary) else { return nil }
        try? fm.removeItem(at: pdfFile)
        guard (try? fm.moveItem(at: temporary, to: pdfFile)) != nil else { return nil }
        _ = helpers
        try? JSONEncoder().encode(boxes.map { [$0.minX, $0.minY, $0.width, $0.height] }).write(to: boxesFile, options: .atomic)
        guard let pdf = PDFDocument(url: pdfFile), pdf.pageCount == boxes.count else { return nil }
        return (pdf, boxes)
    }

    /// Page recréée à `factor` × sa taille (contenu vectoriel, texte intégré gardé), pour que les pages d'un livre
    /// aient la même hauteur (doubles pages égales). Rotation reprise.
    nonisolated static func scaledPage(_ page: PDFPage, factor: CGFloat) -> (PDFPage, PDFDocument)? {
        guard let source = page.pageRef else { return nil }
        let box = page.bounds(for: .cropBox)
        var media = CGRect(x: 0, y: 0, width: (box.width * factor).rounded(), height: (box.height * factor).rounded())
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &media, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.scaleBy(x: factor, y: factor)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(source)
        ctx.endPDFPage()
        ctx.closePDF()
        guard let doc = PDFDocument(data: data as Data) else { return nil }
        doc.delegate = TonedPageProvider.shared
        guard let scaled = doc.page(at: 0) else { return nil }
        // `PDFPage.rotation` notifie UIKit de façon synchrone (voir `install`). Cette page est recopiée dans le PDF
        // préparé, qui doit garder sa rotation : on attend le fil principal, jamais bloqué sur cette construction.
        let rotation = page.rotation
        if rotation != 0 {
            if Thread.isMainThread { scaled.rotation = rotation }
            else { DispatchQueue.main.sync { scaled.rotation = rotation } }
        }
        return (scaled, doc)
    }

    /// Hauteur la plus courante des pages (telles qu'affichées, rotation comprise), arrondie au point.
    nonisolated static func commonHeight(_ pdf: PDFDocument) -> CGFloat? {
        var counts: [Int: Int] = [:]
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let b = page.bounds(for: .cropBox)
            counts[Int((page.rotation % 180 == 0 ? b.height : b.width).rounded()), default: 0] += 1
        }
        return counts.max { $0.value < $1.value }.map { CGFloat($0.key) }
    }

    /// Numéro de la dernière construction demandée : un résultat plus ancien est ignoré.
    var rebuildGeneration = 0
    /// Vrai pendant la construction du document (ouverture, réglages, page coupée).
    @Published private(set) var isBuilding = false
    var buildTask: Task<Void, Never>?
    /// Lecteur fermé : plus rien ne doit réinstaller de document.
    var closed = false

    /// (Re)construit le document affiché à partir du fichier et des transformations.
    /// Le gros du travail (lecture de toutes les pages, copies des pages coupées, ordre droite → gauche)
    /// se fait en tâche de fond ; seule l'installation dans la vue PDF reste sur le fil principal.
    func rebuild(keepingSource source: Int) {
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

    nonisolated static func build(url: URL, documentId: String, transforms: [Int: PageTransform],
                                          settings: ReaderSettings) -> Built? {
        // Pages remises à la même hauteur : préparées une fois par version du PDF (cache disque), ensuite lues
        // directement (plus de « Préparation des pages » à chaque ouverture).
        let equalized = equalizedDocument(url: url, documentId: documentId)
        guard let pdf = equalized?.pdf ?? PDFDocument(url: url) else { return nil }
        pdf.delegate = TonedPageProvider.shared
        let sourceBoxes = equalized?.sourceBoxes
        var boxes: [Int: CGRect] = [:]
        var rotations: [Int: Int] = [:]
        let rtl = settings.direction == .rightToLeft
        var splitPages = Set<Int>()
        var pendingRotations: [(page: PDFPage, degrees: Int)] = []
        var pendingBounds: [(page: PDFPage, box: CGRect)] = []
        let count = pdf.pageCount
        boxes.reserveCapacity(count)
        rotations.reserveCapacity(count)

        // Pages dans l'ordre final, puis un seul rangement du document (voir plus bas).
        var ordered: [PDFPage] = []
        ordered.reserveCapacity(count)
        for index in 0..<count {
            guard let page = pdf.page(at: index) else { continue }
            let box = page.bounds(for: .cropBox)
            // Cadre de la page dans le PDF d'origine (différent si elle a été remise à la hauteur commune).
            let sourceBox = sourceBoxes.flatMap { index < $0.count ? $0[index] : nil } ?? box
            (page as? TonedPage)?.sourceBox = sourceBox
            boxes[index] = box
            rotations[index] = page.rotation
            ordered.append(page)
            // Version nettoyée (DE-GAN) possible : posée sur le cadre d'origine.
            let pageKey = ScanSharpening.key(documentId: documentId, page: index)
            (page as? TonedPage)?.pageKey = pageKey
            (page as? TonedPage)?.originalBox = box
            let transform = transforms[index]
            // Calculée ici, posée par `install` : `PDFPage.rotation` notifie UIKit de façon synchrone, et cette
            // construction tourne hors du fil principal (crash de la recette 1.3.2 (72), 02/11/2026).
            let shownRotation = PageTransform.effectiveRotation(intrinsic: page.rotation, additional: transform?.rotation ?? 0)
            let rotationChanged = shownRotation != page.rotation
            if rotationChanged { pendingRotations.append((page, shownRotation)) }
            let visibleSize = shownRotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
            let split = transform?.split ?? false || (settings.splitWidePages && PresentationLayout.isWide(visibleSize))
            if split, let copy = page.copy() as? PDFPage {
                if rotationChanged { pendingRotations.append((copy, shownRotation)) }
                splitPages.insert(index)
                let first: PresentedPage.Part = rtl ? .right : .left
                let second: PresentedPage.Part = rtl ? .left : .right
                pendingBounds.append((page, PresentationLayout.box(for: first, in: box, rotation: shownRotation)))
                pendingBounds.append((copy, PresentationLayout.box(for: second, in: box, rotation: shownRotation)))
                // `copy()` ne recopie pas les propriétés Swift.
                (copy as? TonedPage)?.pageKey = pageKey
                (copy as? TonedPage)?.originalBox = box
                (copy as? TonedPage)?.sourceBox = sourceBox
                ordered.append(copy)
            } else if settings.autoCrop, let crop = transform?.autoCrop {
                pendingBounds.append((page, ContentBounds.apply(crop, to: box)))
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
        return Built(pdf: pdf, boxes: boxes, rotations: rotations, splits: splitPages, presented: presented,
                     pendingRotations: pendingRotations, pendingBounds: pendingBounds)
    }

    func install(_ built: Built?, source: Int, generation: Int) {
        guard generation == rebuildGeneration, !closed else { return }
        isBuilding = false
        // Page tournée pendant la construction : on reste où l'utilisateur est allé.
        let target = pdf == nil ? source : currentSourcePage
        guard let built else {
            loadError = String(localized: "Impossible d'ouvrir ce PDF.")
            return
        }
        originalBoxes = built.boxes
        originalRotations = built.rotations
        splitSources = built.splits
        presented = built.presented
        let pdf = built.pdf
        // Avant `pdfView.document` : la vue découvre les pages déjà dans leur sens.
        for (page, degrees) in built.pendingRotations { page.rotation = degrees }
        for (page, bounds) in built.pendingBounds { page.setBounds(bounds, for: .cropBox) }
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
        applyDisplaySettings(refit: true)
        go(toSource: target, animated: false)
        // La navigation annule les restaurations précédentes : ajuster le nouveau document après elle.
        pdfView.finishLayout(preserving: nil)
        rebuilding = false
        // Le rognage a besoin des repères de pages : lancé une fois le document installé.
        startAutoCropIfNeeded()
        schedulePageSettled()
        if pendingDrawingRestore {
            pendingDrawingRestore = false
            setDrawing(true)
        }
    }

    func markOpened() {
        let id = document.id
        let page = document.lastPageIndex
        model.persist { try $0.updateReadingPosition(documentId: id, pageIndex: page) }
    }

    /// Cherche le texte sous `point` (vue PDF) : texte intégré du PDF, sinon OCR (fait si besoin).
    /// `fromHover` : survol au curseur → jamais d'OCR lancé (trop lent), et rien ne se ferme
    /// quand le pointeur passe sur un blanc (pour pouvoir aller jusqu'au popup).
    /// `tapGeneration` : le toucher qui a lancé la recherche. Devenu périmé pendant l'attente de l'OCR, il n'ouvre plus de fenêtre.
    func lookup(at point: CGPoint, fromHover: Bool = false, tapGeneration: Int? = nil) async {
        guard document.capabilities.textAnalysis else { return } // Ce chemin lancerait l'OCR.
        // Toute source de recherche (toucher, stylet, survol) devient périmée au prochain geste, changement de page ou fermeture.
        let generation = tapGeneration ?? tapLookupGeneration
        func isStale() -> Bool { generation != tapLookupGeneration || closed || Task.isCancelled }
        traceLookup("Recherche lancée ; survol=\(fromHover)")
        if !fromHover { lookupOpenedByShiftOnly = false }
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
                if !fromHover, !isStale() { lookupHighlight = [] }
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
                    guard !isStale() else { return }
                    present(text: text, rects: rects, anchor: point, context: context)
                    return
                }
                if !fromHover, !isStale() { lookupHighlight = [] }
                return
            }
        }

        // 2. OCR de la page (cache, sinon le moteur choisi : NDLOCR / PP-OCRv5 s'ils sont installés).
        guard let box = originalBoxes[source], let frame = pageFrame(ofSource: source) else { return }
        var ocr = realOCR ?? (source == focusSource ? ocrPage : nil)
        if ocr == nil { ocr = await cachedOCR(source: source) }
        if ocr == nil, fromHover {
            traceLookup("Cache OCR absent : lecture demandée")
            // Survol d'une page jamais lue : on lance l'OCR en fond, le survol marchera dès qu'il a fini.
            ensureOCR([source])
            return
        }
        if ocr == nil {
            let focused = source == focusSource
            if focused { ocrState = .running }
            let engine = await scanEngine(source: source)
            selectedEngines[source] = engine
            ocr = try? await model.ocr.page(documentId: document.id, url: fileURL, pageIndex: source, engine: engine)
            if focused, focusSource == source { ocrState = .idle }
            // `ocrState` revient toujours au repos. Le résultat, lui, reste au cache : un geste plus récent garde l'écran.
            if let ocr, !isStale() { if source == focusSource { ocrPage = ocr }; showOCR(ocr, source: source) }
        }
        // L'OCR a pu durer plusieurs secondes : un résultat périmé reste au cache mais ne touche plus à l'écran.
        guard let ocr, !isStale() else { return }
        // Rotation intrinsèque comprise (photos de pages) : sans elle, le toucher visait à côté.
        let normalized = frame.normalized(pagePoint)
        // Marge de toucher : ~14 pt au doigt, ~4 pt au curseur, convertis en fraction de la page affichée.
        let margin: CGFloat = fromHover ? 4 : 14
        // Largeur affichée de la page (côté qui correspond à l'axe x du repère OCR, rotation comprise).
        let shownWidth = frame.rotation % 180 == 0 ? box.width : box.height
        let tolerance = Double(margin / max(shownWidth * pdfView.scaleFactor, 1))
        guard let hit = ocr.character(at: normalized, tolerance: tolerance) else {
            traceLookup("Aucun caractère OCR sous le pointeur")
            if !fromHover { lookupHighlight = [] }  // Aucune attente depuis le contrôle ci-dessus.
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
        guard !isStale() else { return }  // `wordStart` attend le dictionnaire.
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
    static func stringIndex(near guess: Int, glyph: Int, on page: PDFPage, string ns: NSString) -> Int? {
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

    func present(text: String, rects: [CGRect], anchor: CGPoint, context: LookupContext) {
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
        traceLookup("Présentation du dictionnaire")
        lookupRequest = LookupRequest(text: text, anchor: anchor, wordRect: first, vertical: vertical)
        ReadingTimeTracker.shared.wordLookedUp()
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
    func scanEngine(source: Int) async -> String {
        let choice = settings.ocrEngine
        let id = OCRSelectionPolicy.engineToRead(choice: choice == .pdfText ? .auto : choice, pinned: pinnedEngines[source],
                                                 hasTextLayer: false, isInstalled: Self.isInstalled)
        guard id == OCREngineID.pdfText else { return id }
        return OCRSelectionPolicy.engineToRead(choice: .auto, pinned: nil, hasTextLayer: false, isInstalled: Self.isInstalled)
    }

    /// Modèle d'OCR présent sur l'appareil (Vision et le texte du PDF le sont toujours).
    nonisolated static func isInstalled(_ id: String) -> Bool { OCRService.engine(id)?.isAvailable == true }

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
        traceLookup("Fermeture du dictionnaire")
        lookupRequest = nil
        lookupHighlight = []
        lookupCharacterRects = []
    }

    /// `cropBox` d'origine d'une page source (repère des résultats OCR).
    func originalBox(ofSource source: Int) -> CGRect? { originalBoxes[source] }

    /// Repère des résultats OCR d'une page source (cadre d'origine + rotation intrinsèque du PDF).
    func pageFrame(ofSource source: Int) -> PageFrame? {
        originalBoxes[source].map {
            PageFrame(box: $0, rotation: PageTransform.effectiveRotation(
                intrinsic: originalRotations[source] ?? 0,
                additional: transforms[source]?.rotation ?? 0))
        }
    }

    // MARK: Notifications

    func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pageChanged() }
        })
        observers.append(center.addObserver(forName: .PDFViewSelectionChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hasSelection = ReaderBarsPolicy.isVisibleSelection(self.pdfView.currentSelection?.string)
            }
        })
        // Corrections depuis l'analyse : elles ne passent pas par AITaskCenter.finished.
        observers.append(center.addObserver(forName: OCRService.cacheUpdated, object: nil, queue: .main) { [weak self] note in
            guard let id = note.userInfo?["documentId"] as? String,
                  let source = note.userInfo?["pageIndex"] as? Int,
                  let engine = note.userInfo?["engine"] as? String else { return }
            MainActor.assumeIsolated {
                guard let self, !self.closed, id == self.document.id, source == self.focusSource,
                      engine == self.ocrPage?.engine else { return }
                Diagnostics.log("Cache OCR enregistré : rafraîchissement p. \(source + 1)", "ocr-ui")
                self.reloadOCRAfterAITask()
            }
        })
        aiFinished = AITaskCenter.shared.$finished.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.reloadOCRAfterAITask() }
        }
        // Page lue par l'IA (scan du document) : ses furigana sont refaits d'après ce texte si elle est affichée.
        observers.append(center.addObserver(forName: .aiPageRead, object: nil, queue: .main) { [weak self] note in
            guard let read = note.object as? DocumentScan.PageRead else { return }
            MainActor.assumeIsolated {
                self?.refreshFurigana(afterAIRead: read)
                if read.documentId == self?.document.id { self?.recheckDoubtsAfterAIRead(page: read.page) }
            }
        })
        // Pages pas encore lues par l'IA : lecture en tâche de l'app (continue après la fermeture du lecteur).
        DocumentScan.start(document, url: fileURL, ocr: model.ocr)
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

    /// Résultats de tâches de fond (nettoyage, teinte, furigana) : ils arrivent coup sur coup après chaque page posée,
    /// et chacun ferait redessiner et redécoder toute la page. Un seul redessin les regroupe. Les changements de
    /// réglage, eux, gardent le redessin immédiat.
    func requestRedraw() {
        guard !redrawRequested else { return }
        redrawRequested = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.redrawDelay) { [weak self] in
            self?.redrawRequested = false
            self?.redrawVisiblePages()
        }
    }

    private static let redrawDelay: TimeInterval = 0.12
    private var redrawRequested = false

    /// « Tout sélectionner » (⌘A, clic droit) : les pages affichées. PDFKit prendrait tout le document, jusqu'à figer un gros livre.
    override func selectAll(_ sender: Any?) {
        let selection = PDFSelection(document: document ?? PDFDocument())
        for page in visiblePages {
            if let text = page.selection(for: page.bounds(for: .cropBox)) { selection.add(text) }
        }
        guard selection.string?.isEmpty == false else { return }
        setCurrentSelection(selection, animate: false)
    }

    /// « Copier » : le texte de la sélection, écrit nous-mêmes. Une sélection bâtie page par page (`selectAll`)
    /// donnait à PDFKit un presse-papiers vide alors que son texte existait (recette iPad 1.5.0, point 1.2).
    override func copy(_ sender: Any?) {
        guard copySelectionText() else { return super.copy(sender) }
    }

    /// Texte brut de la sélection dans le presse-papiers, seul type écrit : une app qui préfère le texte riche ne
    /// colle plus un contenu vide. Faux si rien n'est sélectionné.
    @discardableResult
    func copySelectionText() -> Bool {
        guard let text = currentSelection?.string, ReaderBarsPolicy.isVisibleSelection(text) else { return false }
        UIPasteboard.general.string = text
        return true
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        // « Copier » du menu (clic droit, appui) part vers une vue interne de PDFKit, pas vers `copy(_:)` ci-dessus :
        // la copie restait vide (recette iPad 1.5.1, points 3.1 et 3.2). L'entrée du menu est donc remplacée par la nôtre.
        if ReaderBarsPolicy.isVisibleSelection(currentSelection?.string) {
            let copyAction = UIAction(title: String(localized: "Copier"), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                self?.copySelectionText()
            }
            var replaced = false
            builder.replaceChildren(ofMenu: .standardEdit) { children in
                children.map { element in
                    if let command = element as? UICommand, command.action == #selector(UIResponderStandardEditActions.copy(_:)) {
                        replaced = true
                        return copyAction
                    }
                    return element
                }
            }
            // Menu sans entrée « Copier » reconnue : la nôtre est ajoutée en tête, pour ne jamais rester sans copie.
            if !replaced { builder.insertChild(UIMenu(options: .displayInline, children: [copyAction]), atStartOfMenu: .root) }
        }
        guard let onLookupSelection, currentSelection?.string?.isEmpty == false else { return }
        let action = UIAction(title: String(localized: "Dictionnaire"), image: UIImage(systemName: "character.book.closed.ja")) { _ in
            onLookupSelection()
        }
        builder.insertSibling(UIMenu(options: .displayInline, children: [action]), beforeMenu: .standardEdit)
    }
    static let preserveViewportKey = "reader.preserveViewport"
    private var lastFit: CGFloat = 0
    private var layoutWork: DispatchWorkItem?
    private var pendingViewport: ViewportSnapshot?
    private var layoutGeneration = 0
    private var requiresFit = false

    struct ViewportSnapshot {
        let document: PDFDocument
        let page: PDFPage
        let point: CGPoint
        let scale: CGFloat
        let fitted: Bool
    }

    /// Vrai si la page est affichée « entière » (pas de zoom de l'utilisateur).
    var isAtFit: Bool {
        lastFit == 0 || abs(scaleFactor - lastFit) / lastFit < 0.02
    }

    func fitToPage() {
        cancelPendingViewportRestoration()
        layoutDocumentView()
        let fit = scaleFactorForSizeToFit
        guard fit.isFinite, fit > 0 else { return }
        minScaleFactor = fit
        maxScaleFactor = max(6, fit * 6)
        scaleFactor = fit
        lastFit = fit
    }

    /// Au centre du lecteur, dans les coordonnées de la page : ni défilement interne ni vue recréée.
    func captureViewport() -> ViewportSnapshot? {
        if requiresFit { return nil }
        if let pendingViewport, pendingViewport.document === document { return pendingViewport }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        guard bounds.width > 0, bounds.height > 0, scaleFactor > 0,
              let document, let page = page(for: center, nearest: true) else { return nil }
        return ViewportSnapshot(document: document, page: page, point: convert(center, to: page),
                                scale: scaleFactor, fitted: isAtFit)
    }

    func resizeViewport(to frame: CGRect) {
        let viewport = captureViewport()
        self.frame = frame
        layoutIfNeeded()
        finishLayout(preserving: viewport)
    }

    /// Coalescer les recalages : seul le dernier résultat peut modifier la vue.
    func finishLayout(preserving viewport: ViewportSnapshot?) {
        layoutWork?.cancel()
        layoutGeneration += 1
        let generation = layoutGeneration
        pendingViewport = viewport
        requiresFit = viewport == nil
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.layoutGeneration else { return }
            self.pendingViewport = nil
            self.requiresFit = false
            self.layoutWork = nil
            guard let viewport, viewport.document === self.document,
                  viewport.document.index(for: viewport.page) != NSNotFound else {
                self.fitToPage()
                return
            }
            let preserve = UserDefaults.standard.object(forKey: Self.preserveViewportKey) as? Bool ?? true
            if viewport.fitted {
                self.fitToPage()
            } else if preserve {
                self.restoreViewport(viewport)
            } else {
                self.minScaleFactor = self.scaleFactorForSizeToFit
            }
        }
        layoutWork = work
        DispatchQueue.main.async(execute: work)
    }

    /// Une navigation explicite prend toujours le pas sur un recalage encore en attente.
    func cancelPendingViewportRestoration() {
        layoutGeneration += 1
        layoutWork?.cancel()
        layoutWork = nil
        pendingViewport = nil
        requiresFit = false
    }

    private func restoreViewport(_ viewport: ViewportSnapshot) {
        layoutDocumentView()
        let fit = scaleFactorForSizeToFit
        guard fit.isFinite, fit > 0, viewport.scale.isFinite, viewport.scale > 0 else { return }
        // Agrandir la zone disponible ne doit pas forcer un zoom minimum supérieur au zoom choisi.
        minScaleFactor = min(fit, viewport.scale)
        maxScaleFactor = max(6, fit * 6, viewport.scale)
        scaleFactor = viewport.scale
        layoutDocumentView()
        // PDFDestination vise le coin supérieur gauche : décaler le point pour conserver le centre.
        // Les conversions PDFKit prennent aussi en charge les pages pivotées et la double page.
        let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: viewport.page)
        let corner = convert(CGPoint(x: bounds.minX, y: bounds.minY), to: viewport.page)
        let destination = PDFDestination(page: viewport.page,
            at: CGPoint(x: viewport.point.x + corner.x - center.x, y: viewport.point.y + corner.y - center.y))
        destination.zoom = viewport.scale
        go(to: destination)
        lastFit = fit
        Diagnostics.log("Vue conservée : zoom \(viewport.scale), page \(viewport.document.index(for: viewport.page))", "affichage")
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
