// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import OCRKit
import PDFKit
import ReaderCore
import Combine
import SwiftUI

/// Lecteur « Atelier », pensé pour l'iPad en paysage :
/// page au centre, outils à gauche (une couleur par fonction), panneau d'étude à droite,
/// pellicule des pages en bas. Tout s'efface d'un tap au centre de la page.
struct ReaderScreen: View {
    /// Pas observé : sinon tout le lecteur se redessine à chaque changement d'`AppModel`
    /// (bibliothèque, import…). Les seules valeurs utiles arrivent par `onReceive`.
    private let model: AppModel
    @State private var showOCRBoxes = false
    @EnvironmentObject private var review: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var reader: ReaderController
    @StateObject private var lookup: LookupSession
    @State private var sheet: Sheet?
    @State private var side: Side? = nil
    /// Colonne de droite **réellement réservée** à la page (Issue #69). Elle suit `docked`, mais à la fermeture
    /// elle n'est libérée qu'après l'animation de sortie du panneau : la largeur de PDFKit change une seule fois,
    /// jamais à chaque image (choix du 23/10, `5efd2ca`).
    @State private var reservedSide: Side?
    /// Contenu de la colonne visible (animé) ; faux pendant la sortie et juste avant l'entrée.
    @State private var dockedPanelShown = true
    /// Annule une étape différée devenue obsolète (appuis rapides, rotation).
    @State private var dockGeneration = 0
    @State private var autoOpenedSide = false
    @AppStorage(StudyPanelMotion.storageKey) private var animateTransitions = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var studyTab: StudyPanel.Tab = .text
    @AppStorage(StudyPanelMode.storageKey) private var studyMode = StudyPanelMode.docked
    @AppStorage(StudyPanelMode.restoreKey) private var studyRestore = StudyPanelMode.docked
    /// Réglage général du panneau à l'ouverture du livre, rétabli à la fermeture : la position choisie dans un livre
    /// reste à ce livre (recette 1.3.2 (61), M2).
    @State private var generalPanelMode: StudyPanelMode?
    /// Choix gardé entre les sessions. L'affichage passe par `filmstripVisible` : un changement d'`@AppStorage`
    /// arrive par la notification de `UserDefaults`, hors de la transaction `withAnimation`, et la bande apparaissait
    /// sans transition (RET-049, Issue #79).
    @AppStorage("reader.filmstripShown") private var filmstripShown = true
    @State private var filmstripVisible = UserDefaults.standard.object(forKey: "reader.filmstripShown") as? Bool ?? true
    /// Vrai dès la première ouverture : la bande reste ensuite montée, masquée, pour garder la position de défilement
    /// et ne pas recréer les miniatures à chaque ouverture.
    @State private var filmstripMounted = UserDefaults.standard.object(forKey: "reader.filmstripShown") as? Bool ?? true
    @AppStorage("reader.trackpadScrollPassThrough") private var trackpadScrollPassThrough = true
    @AppStorage("pencil.lookupOption") private var pencilOption = false
    @AppStorage(PageTone.storageKey) private var pageTone = PageTone.normal
    @State private var scanCleaning = ScanSharpening.method
    @AppStorage(FuriganaLayer.storageKey) private var furigana = false
    @AppStorage(FuriganaLayer.Tint.storageKey) private var furiganaTint = FuriganaLayer.Tint.red
    @ObservedObject private var deepl = DeepLService.shared
    @AppStorage(ResourceMonitor.enabledKey) private var monitorEnabled = false
    @AppStorage(ResourceMonitor.shownKey) private var monitorShown = false
    /// Couleur du mode « Surligner l'OCR » (#23), choisie par appui long sur son bouton.
    @AppStorage("highlight.ocrColor") private var ocrHighlightColor = HighlightColor.yellow
    @State private var pageField = ""
    @ObservedObject private var shift = ShiftKey.shared
    @Environment(\.scenePhase) private var scenePhase

    enum Sheet: String, Identifiable {
        case search, ai, settings, pageCards
        var id: String { rawValue }
    }

    enum Side: Equatable { case study, web }

    init(document: LibraryDocument, model: AppModel) {
        self.model = model
        _reader = StateObject(wrappedValue: ReaderController(document: document, model: model))
        _lookup = StateObject(wrappedValue: LookupSession(dictionary: model.dictionary))
    }

    private var chromeVisible: Bool { reader.barsVisible || reader.isDrawing }

    /// Panneau dans la colonne de droite (navigateur, ou panneau d'étude ancré) : la page lui laisse la place.
    private var docked: Side? {
        side == .study && studyMode != .docked ? nil : side
    }

    private var panelAnimation: Animation? {
        StudyPanelMotion.animation(enabled: animateTransitions, reduceMotion: reduceMotion)
    }

    private var panelTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let reservesSide = reservedSide == .web || (reservedSide == .study && landscape)
            let panelWidth: CGFloat = (reservedSide ?? docked) == .web ? 440 : Atelier.panelWidth
            let inset: CGFloat = reservesSide ? Atelier.gap : 0
            let documentWidth = max(1, geo.size.width - (reservesSide ? panelWidth + Atelier.gap * 3 : 0))
            let documentHeight = max(1, geo.size.height - inset * 2)
            HStack(spacing: reservesSide ? Atelier.gap : 0) {
                ZStack {
                    PDFViewHost(view: reader.pdfView)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: docked == nil ? 0 : Atelier.radius, style: .continuous))
                    LookupHighlightLayer(rects: reader.lookupHighlight)
                    if reader.ocrHighlightMode {
                        OCRHighlightDragLayer(reader: reader, color: ocrHighlightColor)
                        OCRHighlightControls(reader: reader)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, chromeVisible ? 110 : 24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if chromeVisible {
                        // Portrait : la bande des pages s'arrête au bord du panneau d'étude flottant (recette 1.3.2 (59), A11).
                        chrome(filmstripTrailing: FilmstripLayout.trailingInset(
                            portraitPanelShown: docked == .study && !landscape, panelWidth: panelWidth, gap: Atelier.gap))
                            .transition(.opacity)
                    }
                    if let request = reader.lookupRequest {
                        GeometryReader { area in
                            let frame = PopupPlacement.frame(for: request, in: area.size)
                            LookupPopup(session: lookup, added: review.keys, onAddCard: { term in
                                review.add(term, sentence: reader.lookupContext?.sentence, source: reader.lookupSourceLabel,
                                           image: review.settings.includeImage ? reader.lookupLineJPEG() : nil,
                                           documentId: reader.document.id, page: reader.lookupContext?.source,
                                           dictionary: model.dictionary)
                            }, close: { reader.endLookup(); lookup.clear() })
                                .frame(width: frame.width, height: frame.height)
                                .offset(x: frame.minX, y: frame.minY)
                                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                        }
                        // Échap (Magic Keyboard) ferme le popup.
                        Button("") { reader.endLookup() }
                            .keyboardShortcut(.escape, modifiers: [])
                            .opacity(0).allowsHitTesting(false)
                    }
                    // Plus de flèches sur les bords de la page (#19) : elles sont rangées de part et d'autre du champ
                    // « page », en haut à droite. ← → au clavier : `ReaderArrowKeys` ; glisser tourne aussi les pages.
                    // Construction du document en tâche de fond (gros PDF, réglages, page coupée).
                    if reader.isBuilding {
                        HStack(spacing: 10) {
                            ProgressView().tint(Atelier.Tint.read)
                            Text("Préparation des pages…").font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Atelier.textSecondary)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .atelierPanel(radius: 22)
                        .allowsHitTesting(false)
                    }
                    if let error = reader.loadError {
                        Text(error).padding().atelierPanel()
                    }
                }
                .frame(width: documentWidth, height: documentHeight)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    // Moniteur fixé puis pastilles IA (#47) ; plus de moniteur flottant à déplacer.
                    ActivityDock(showsMonitor: false)
                        .padding(.leading, Atelier.gap)
                        .padding(.bottom, chromeVisible && filmstripVisible && !reader.isDrawing ? 120 : Atelier.gap)
                }
                .animation(.easeOut(duration: 0.18), value: chromeVisible)
                if reservesSide {
                    // Le panneau possède réellement sa colonne : PDFKit ne peut pas le recouvrir
                    // lors d'une navigation par la pellicule ou d'un changement de mise en page.
                    if let reservedSide {
                        sidePanel(reservedSide).frame(width: panelWidth, height: documentHeight)
                            // Seul le contenu s'anime ; la colonne garde sa largeur pendant l'animation.
                            .offset(x: dockedPanelShown || reduceMotion ? 0 : panelWidth * 0.35)
                            .opacity(dockedPanelShown ? 1 : 0)
                            .allowsHitTesting(dockedPanelShown)
                    }
                }
            }
            .frame(height: documentHeight)
            .padding(inset)
            // Une seule taille finale pour PDFKit : aucune interpolation du document avec les fenêtres.
            .animation(nil, value: studyMode)
            .animation(nil, value: side)
            // Portrait : une page ; paysage : double page (affichage seulement).
            .onChange(of: landscape) {
                reader.adaptLayout(portrait: !$0)
                finishDockTransition()
            }
            .onChange(of: docked) { syncDock(to: $0) }
            // Chaque livre retient sa position du panneau ; le réglage général reste celui des livres sans choix.
            .onChange(of: studyMode) { mode in
                guard mode != .minimized, generalPanelMode != nil else { return }
                reader.toolModes.update(documentId: reader.document.id) { $0.panelMode = mode.rawValue }
            }
            .onAppear {
                reservedSide = docked
                reader.adaptLayout(portrait: !landscape)
                // Paysage (taille réelle de la vue, pas l'orientation de la scène) : panneau d'étude ouvert d'office.
                if landscape, !autoOpenedSide { autoOpenedSide = true; side = .study }
            }
            .overlay(alignment: .trailing) {
                // En portrait seulement, le panneau reste flottant sur la page.
                if docked == .study, !landscape {
                    sidePanel(.study)
                        .padding(.vertical, Atelier.gap)
                        .frame(width: panelWidth, height: documentHeight)
                        .padding(.trailing, Atelier.gap)
                        .transition(panelTransition)
                        .animation(panelAnimation, value: docked)
                }
            }
            .overlay {
                // Panneau d'étude détaché : fenêtre, plein écran ou pastille, par-dessus la page.
                ZStack {
                    if side == .study, studyMode != .docked {
                        DetachedPanel(area: geo.size) {
                            StudyPanel(reader: reader, tab: $studyTab, openSearch: { sheet = .search },
                                       close: { self.side = nil }, fixedWidth: false)
                        }
                        .transition(.opacity)
                    }
                }
                .animation(panelAnimation, value: side)
                .animation(panelAnimation, value: studyMode)
            }
        }
        .background(Atelier.canvas.ignoresSafeArea())
        // ←/→ du clavier physique, prioritaires sur le focus des champs (RET-050, Issue #81).
        .background(ReaderArrowKeysHost(reader: reader).frame(width: 0, height: 0))
        .onChange(of: side) { ReaderArrowKeys.shared.webOpen = $0 == .web }
        .statusBarHidden(!chromeVisible)
        .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
        .onAppear {
            // Position du panneau propre à ce livre, sinon le réglage général (recette 1.3.2 (61), M2).
            generalPanelMode = studyMode
            if let raw = reader.toolModes.modes(documentId: reader.document.id).panelMode,
               let saved = StudyPanelMode(rawValue: raw), saved != .minimized, saved != studyMode {
                studyMode = saved
            }
            reader.load()
            ReaderArrowKeys.shared.webOpen = side == .web
            ReadingTimeTracker.shared.readerOpened(documentId: reader.document.id)
        }
        .onDisappear {
            reader.close()
            ReadingTimeTracker.shared.readerClosed(documentId: reader.document.id)
            // Réglage général rétabli pour les autres livres ; `nil` d'abord, pour ne pas l'enregistrer dans celui-ci.
            if let general = generalPanelMode {
                generalPanelMode = nil
                if studyMode != general { studyMode = general }
            }
        }
        // Temps de lecture active (accueil) : pause en arrière-plan ou iPad verrouillé (RET-037, #52).
        .onChange(of: scenePhase) { ReadingTimeTracker.shared.scenePhaseChanged($0) }
        .task { await deepl.refreshUsage() }
        .onChange(of: reader.lookupRequest) { request in
            if let request { lookup.start(request.text) } else { lookup.clear() }
        }
        .onChange(of: lookup.matchedLength) { reader.setLookupMatchLength($0) }
        .onChange(of: shift.pressed) { pressed in
            // Bulle ouverte au survol avec Maj seule : relâcher Maj la ferme, comme dans le panneau Texte (RET-021, #24).
            if !pressed, HoverLookupMode.closesOnShiftRelease(toggleOn: reader.hoverLookup,
                                                             openedByShiftOnly: reader.lookupOpenedByShiftOnly,
                                                             bubbleOpen: reader.lookupRequest != nil) {
                reader.endLookup()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: reader.lookupRequest)
        .onReceive(model.$readerDefaults.removeDuplicates().dropFirst()) { defaults in
            reader.update(settings: defaults.applying(reader.document.settingsOverride))
        }
        .onReceive(model.$appSettings.map(\.showOCRBoxes).removeDuplicates()) { showOCRBoxes = $0 }
        .onChange(of: trackpadScrollPassThrough) { enabled in
            for swipe in [reader.swipeLeft, reader.swipeRight] {
                swipe?.allowedTouchTypes = enabled
                    ? [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                    : [NSNumber(value: UITouch.TouchType.direct.rawValue),
                       NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
            }
        }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .search: SearchSheet(reader: reader, close: { self.sheet = nil })
                case .ai: AIPageSheet(reader: reader, openWeb: { self.sheet = nil; side = .web })
                case .settings: DocumentSettingsSheet(reader: reader)
                case .pageCards: PageCardsView(reader: reader)
                }
            }
            .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review)
            .preferredColorScheme(.dark)
        }
        .confirmationDialog("Surlignage", isPresented: Binding(get: { reader.tappedHighlight != nil },
                                                               set: { if !$0 { reader.tappedHighlight = nil } })) {
            Button("Copier le texte") { UIPasteboard.general.string = reader.tappedHighlight?.text }
            Button("Supprimer le surlignage", role: .destructive) {
                if let h = reader.tappedHighlight { reader.deleteHighlight(h) }
            }
        } message: {
            Text(reader.tappedHighlight?.text ?? "")
        }
    }

    // MARK: Chrome flottant

    private func chrome(filmstripTrailing: CGFloat) -> some View {
        VStack(spacing: 0) {
            DocumentTabsBar(current: reader.document.id)
                .padding(.horizontal, Atelier.gap)
                .padding(.top, 6)
            HStack(alignment: .top, spacing: Atelier.gap) {
                titleCapsule
                Spacer(minLength: 8)
                if reader.hasSelection {
                    HighlightMenu { reader.highlightSelection(color: $0) }
                        .transition(.scale.combined(with: .opacity))
                }
                // Moniteur rangé en haut à droite, à côté des actions ; il se déroule vers le bas (recette 62, L9).
                if monitorEnabled && monitorShown {
                    ResourceMonitorPanel(expandsDown: true)
                        .fixedSize()
                        // Ne prend que la hauteur de sa ligne : la courbe déroulée passe par-dessus la page, sans
                        // pousser la barre d'outils.
                        .frame(height: 30, alignment: .top)
                        .zIndex(1)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                actionsCapsule
            }
            .padding(.horizontal, Atelier.gap)
            .padding(.top, 8)
            GeometryReader { area in
                ZStack(alignment: .topLeading) {
                    FloatingToolbar(area: area.size) { vertical in toolItems(vertical: vertical) }
                    if let note = reader.openNote {
                        NoteWindow(reader: reader, note: note, area: area.size)
                    }
                    if reader.placingAnchorFor != nil {
                        HStack(spacing: 10) {
                            Text("Touche le mot de la page où ancrer la note").font(.system(size: 14, weight: .semibold))
                            Button("Annuler") { reader.placingAnchorFor = nil }.fontWeight(.bold)
                        }
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Atelier.Tint.annotate, in: Capsule())
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
                .padding(Atelier.gap)
            if !reader.isDrawing {
                ZStack(alignment: .bottom) {
                    if filmstripMounted {
                        PageFilmstrip(reader: reader)
                            .overlay(alignment: .topTrailing) {
                                Button { setFilmstrip(false) } label: {
                                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                                        .frame(width: 28, height: 28).foregroundStyle(Atelier.textPrimary)
                                        .background(Atelier.surfaceHigh, in: Circle())
                                }
                                .buttonStyle(PressScale())
                                .accessibilityLabel("Rentrer la bande des pages")
                                .offset(x: -10, y: -12)
                            }
                            .padding(.horizontal, Atelier.gap)
                            .padding(.bottom, 10)
                            // Masquée sans être retirée : glissement court et fondu, fondu seul avec « Réduire les animations ».
                            .offset(y: filmstripVisible || reduceMotion ? 0 : 24)
                            .opacity(filmstripVisible ? 1 : 0)
                            .allowsHitTesting(filmstripVisible)
                            .accessibilityHidden(!filmstripVisible)
                            // Première ouverture dans la session (bande rangée au lancement) : même mouvement.
                            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 24)))
                    }
                    if !filmstripVisible {
                        Button { setFilmstrip(true) } label: {
                            Label("Pages", systemImage: "chevron.up").font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .foregroundStyle(Atelier.textPrimary)
                                .atelierPanel(radius: 18)
                        }
                        .buttonStyle(PressScale())
                        .padding(.bottom, 10)
                        .transition(.opacity)
                    }
                }
                .padding(.trailing, filmstripTrailing)
                // Suit le panneau qui entre ou sort (le conteneur coupe l'animation des changements de `side`).
                .animation(panelAnimation, value: filmstripTrailing)
            }
        }
    }

    /// Ouvre ou ferme la bande des pages avec l'animation des fenêtres (mêmes réglages que la fenêtre OCR :
    /// « Animer les changements de fenêtre », « Réduire les animations »), puis garde le choix. La bande est en
    /// surimpression : le PDF n'est pas redimensionné, seule la pastille des tâches IA suit. Un appui pendant
    /// l'animation la reprend depuis l'état courant.
    private func setFilmstrip(_ shown: Bool) {
        withAnimation(StudyPanelMotion.animation(enabled: animateTransitions, reduceMotion: reduceMotion)) {
            if shown { filmstripMounted = true }
            filmstripVisible = shown
        }
        filmstripShown = shown
    }

    private var titleCapsule: some View {
        HStack(spacing: 4) {
            CapsuleButton(icon: "chevron.left", label: "Bibliothèque") { dismiss() }
            VStack(alignment: .leading, spacing: 1) {
                Text(reader.document.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(Atelier.textPrimary)
                HStack(spacing: 6) {
                    Text("\(reader.document.pageLabel(reader.currentSourcePage)) / \(reader.document.pageLabel(reader.document.pageCount - 1))")
                        .font(Atelier.mono)
                    OCRStatusDot(reader: reader)
                }
                .foregroundStyle(Atelier.textSecondary)
            }
            .padding(.trailing, 14)
        }
        .padding(4)
        .atelierPanel(radius: 26)
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var actionsCapsule: some View {
        HStack(spacing: 0) {
            pageArrow(left: true)
            TextField(reader.document.pageLabel(reader.currentSourcePage), text: $pageField)
                .font(Atelier.mono)
                .multilineTextAlignment(.center)
                .keyboardType(.numbersAndPunctuation)
                .submitLabel(.go)
                .onSubmit(goToTypedPage)
                .frame(width: 58)
                .padding(.vertical, 8)
                .background(Atelier.surfaceHigh, in: Capsule())
                .accessibilityLabel("Aller à la page")
                .padding(.horizontal, 4)
            pageArrow(left: false)
            CapsuleButton(icon: "magnifyingglass", label: "Rechercher") { sheet = .search }
            CapsuleButton(icon: reader.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark", label: "Signet",
                          active: reader.isCurrentPageBookmarked) { reader.toggleBookmark() }
            CapsuleButton(icon: "character.ja", label: furigana ? "Masquer les furigana de la page" : "Afficher les furigana de la page",
                          active: furigana, tint: Atelier.Tint.japanese) {
                furigana.toggle()
                reader.setFurigana(furigana)
            }
            Menu {
                // Rangé par thème : affichage (pour tous les livres), cette page, ce document.
                Menu {
                    Picker(selection: Binding(get: { pageTone }, set: { pageTone = $0; reader.setPageTone($0) })) {
                        ForEach(PageTone.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    } label: {
                        Label("Fond de page", systemImage: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.menu)
                    Picker(selection: Binding(get: { furiganaTint }, set: { furiganaTint = $0; reader.setFuriganaTint($0) })) {
                        ForEach(FuriganaLayer.Tint.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label("Couleur des furigana", systemImage: "paintpalette")
                    }
                    .pickerStyle(.menu)
                    Picker(selection: Binding(get: { scanCleaning }, set: { scanCleaning = $0; reader.setScanCleaning($0) })) {
                        ForEach(ScanSharpening.Method.allCases.filter { $0 != .degan || ScanSharpening.isInstalled }) {
                            Text($0.title).tag($0)
                        }
                    } label: {
                        Label("Nettoyage des scans", systemImage: "wand.and.stars")
                    }
                    .pickerStyle(.menu)
                    Button { reader.setShowOCRBoxes(!showOCRBoxes) } label: {
                        Label(showOCRBoxes ? "Masquer les zones OCR" : "Montrer les zones OCR",
                              systemImage: "rectangle.dashed")
                    }
                } label: {
                    Label("Affichage", systemImage: "eye")
                }
                Menu {
                    Button { sheet = .pageCards } label: {
                        Label("Créer des cartes de cette page", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button { reader.rotateCurrentPage() } label: { Label("Pivoter la page", systemImage: "rotate.right") }
                    Button { reader.toggleSplitCurrentPage() } label: {
                        Label(reader.isCurrentPageSplit ? "Ne plus couper la page" : "Couper la page en deux",
                              systemImage: "rectangle.split.2x1")
                    }
                    Button { reader.setFirstPage(reader.currentSourcePage) } label: {
                        Label("Cette page est la page 1", systemImage: "1.circle")
                    }
                    if reader.document.firstPageIndex != 0 {
                        Button { reader.setFirstPage(0) } label: {
                            Label("Numéros du PDF (page 1 = début)", systemImage: "arrow.uturn.backward")
                        }
                    }
                } label: {
                    Label("Cette page", systemImage: "doc")
                }
                Button { openStudy(.notes) } label: { Label("Notes de la page", systemImage: "text.bubble") }
                Button { reader.newNote() } label: { Label("Nouvelle note flottante", systemImage: "note.text.badge.plus") }
                if monitorEnabled {
                    Toggle(isOn: $monitorShown) { Label("Moniteur de ressources", systemImage: "gauge.with.dots.needle.33percent") }
                }
                if deepl.hasKey {
                    // Information seulement (mise à jour à l'ouverture du livre et après chaque traduction).
                    Button { Task { await deepl.refreshUsage() } } label: {
                        Label(deepl.usageText.map { "DeepL : \($0)" } ?? "DeepL : quota inconnu (toucher pour actualiser)",
                              systemImage: "character.bubble")
                    }
                }
                Divider()
                Button { sheet = .settings } label: {
                    Label("Pagination et réglages de ce document", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40).foregroundStyle(Atelier.textPrimary)
            }
            Rectangle().fill(Atelier.hairline).frame(width: 1, height: 22).padding(.horizontal, 4)
            CapsuleButton(icon: "sidebar.trailing", label: "Panneau d'étude", active: side == .study,
                          tint: Atelier.Tint.japanese) {
                // Panneau réduit en pastille : le bouton le rouvre au lieu de le fermer.
                if studyMode == .minimized {
                    studyMode = studyRestore == .minimized ? .docked : studyRestore
                    side = .study
                } else {
                    side = side == .study ? nil : .study
                }
            }
        }
        .padding(4)
        .atelierPanel(radius: 26)
    }

    private func railDivider(_ vertical: Bool) -> some View {
        Rectangle().fill(Atelier.hairline)
            .frame(width: vertical ? 26 : 1, height: vertical ? 1 : 26)
            .padding(vertical ? .vertical : .horizontal, 2)
    }

    /// Outils, une couleur par fonction : lecture, annotation, japonais, IA.
    @ViewBuilder
    private func toolItems(vertical: Bool) -> some View {
            ToolButton(icon: "hand.point.up.left", label: "Lire", tint: Atelier.Tint.read, active: !reader.isDrawing) {
                if reader.isDrawing { reader.setDrawing(false) }
            }
            ToolButton(icon: "pencil.tip", label: "Dessiner (Apple Pencil)", tint: Atelier.Tint.annotate,
                       active: reader.isDrawing) {
                reader.setDrawing(!reader.isDrawing)
            }
            railDivider(vertical)
            Button {
                reader.lookupMode.toggle()
                if reader.isDrawing { reader.setDrawing(false) }
                if !reader.lookupMode { reader.endLookup() }
            } label: {
                Text("辞").font(.custom("HiraMinProN-W6", size: 21))
                    .frame(width: 46, height: 46)
                    .foregroundStyle(reader.lookupMode ? Color.black.opacity(0.85) : Atelier.textPrimary)
                    .background(reader.lookupMode ? Atelier.Tint.japanese : Color.clear,
                                in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Dictionnaire au toucher")
            // Survol au curseur : visible dès que la page a du texte (intégré ou analysé par l'OCR).
            if reader.pageHasText {
                ToolButton(icon: "cursorarrow.rays", label: "Dictionnaire au survol (curseur)",
                           tint: Atelier.Tint.japanese, active: reader.hoverLookup) {
                    reader.hoverLookup.toggle()
                    if !reader.hoverLookup { reader.endLookup() }
                }
            }
            // Surligner en glissant sur les zones de l'OCR (#23) ; appui long : couleur.
            ToolButton(icon: "highlighter", label: "Surligner l'OCR en glissant", tint: Color(ocrHighlightColor.uiColor),
                       active: reader.ocrHighlightMode) {
                reader.setOCRHighlightMode(!reader.ocrHighlightMode)
            }
            .contextMenu {
                Picker("Couleur", selection: $ocrHighlightColor) {
                    ForEach(HighlightColor.allCases, id: \.self) { Text(Self.colorName($0)).tag($0) }
                }
            }
            // Pencil → dictionnaire : seulement si l'option est activée dans les réglages.
            if pencilOption {
                ToolButton(icon: "applepencil", label: "Le Pencil cherche dans le dictionnaire",
                           tint: Atelier.Tint.japanese, active: reader.pencilLookup) {
                    reader.pencilLookup.toggle()
                    if reader.pencilLookup, reader.isDrawing { reader.setDrawing(false) }
                }
            }
            railDivider(vertical)
            ToolButton(icon: "character.ja", label: "Texte de la page", tint: Atelier.Tint.japanese,
                       active: side == .study && studyTab == .text) { openStudy(.text) }
            ToolButton(icon: "character.book.closed.ja", label: "Dictionnaire", tint: Atelier.Tint.japanese,
                       active: side == .study && studyTab == .vocab) { openStudy(.vocab) }
            railDivider(vertical)
            ToolButton(icon: "sparkles", label: "Page vers IA", tint: Atelier.Tint.ai) { sheet = .ai }
            ToolButton(icon: "globe", label: "Navigateur à côté", tint: Atelier.Tint.ai, active: side == .web) {
                side = side == .web ? nil : .web
            }
    }

    /// Flèche à côté du champ « page » (#19) : la gauche recule en lecture gauche → droite, avance en droite → gauche.
    private func pageArrow(left: Bool) -> some View {
        let forward = (reader.settings.direction == .rightToLeft) == left
        return CapsuleButton(icon: left ? "chevron.left" : "chevron.right",
                             label: forward ? "Page suivante" : "Page précédente") {
            forward ? reader.next() : reader.previous()
        }
    }

    static func colorName(_ color: HighlightColor) -> String {
        switch color {
        case .yellow: return "Jaune"
        case .green: return "Vert"
        case .blue: return "Bleu"
        case .pink: return "Rose"
        case .orange: return "Orange"
        }
    }

    /// Champ « page » : numéro imprimé (ou chiffre romain des pages d'avant).
    private func goToTypedPage() {
        let typed = pageField.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        pageField = ""
        guard !typed.isEmpty else { return }
        let doc = reader.document
        if let index = (0..<doc.pageCount).first(where: { doc.pageLabel($0) == typed }) {
            reader.go(toSource: index)
        } else if let n = Int(typed) {
            reader.go(toSource: doc.sourceIndex(forPrintedPage: n))
        }
    }

    private func openStudy(_ tab: StudyPanel.Tab) {
        if side == .study && studyTab == tab {
            side = nil
        } else {
            studyTab = tab
            side = .study
            // Panneau réduit : l'ouvrir sur un onglet le rouvre comme avant.
            if studyMode == .minimized { studyMode = studyRestore == .minimized ? .docked : studyRestore }
        }
        if tab == .text, reader.ocrPage == nil, reader.ocrState != .running { reader.runOCR() }
    }

    // MARK: Colonne de droite animée (Issue #69)

    /// Ouverture : la colonne est réservée d'abord (un seul relayout de PDFKit), puis le panneau glisse et apparaît.
    /// Fermeture : le panneau glisse et s'efface dans sa colonne, puis la colonne est libérée en une fois.
    /// iOS 16 n'a pas `withAnimation(_:completion:)` : la libération attend la durée de l'animation.
    private func syncDock(to new: Side?) {
        dockGeneration &+= 1
        let generation = dockGeneration
        guard let animation = panelAnimation else {
            setReserved(new)
            dockedPanelShown = true
            return
        }
        if let new {
            if reservedSide == new {
                // Réouverture pendant une sortie : la colonne n'a pas bougé.
                withAnimation(animation) { dockedPanelShown = true }
            } else if reservedSide != nil {
                // Navigateur ↔ panneau d'étude : remplacement immédiat.
                setReserved(new)
                dockedPanelShown = true
            } else {
                dockedPanelShown = false
                setReserved(new)
                DispatchQueue.main.async {
                    guard generation == dockGeneration else { return }
                    withAnimation(animation) { dockedPanelShown = true }
                }
            }
        } else {
            guard reservedSide != nil else { return }
            withAnimation(animation) { dockedPanelShown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + StudyPanelMotion.duration(reduceMotion: reduceMotion)) {
                guard generation == dockGeneration else { return }
                finishDockTransition()
            }
        }
    }

    /// Termine tout de suite une transition en cours (fin d'animation, rotation).
    private func finishDockTransition() {
        dockGeneration &+= 1
        setReserved(docked)
        dockedPanelShown = true
    }

    /// Change la colonne réservée sans animation : la largeur de PDFKit passe directement à sa valeur finale.
    private func setReserved(_ side: Side?) {
        guard reservedSide != side else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { reservedSide = side }
        Diagnostics.log("Colonne de droite : \(side.map { "\($0)" } ?? "libérée") (relayout PDFKit)", "panneau")
    }

    @ViewBuilder
    private func sidePanel(_ side: Side) -> some View {
        switch side {
        case .study:
            StudyPanel(reader: reader, tab: $studyTab, openSearch: { sheet = .search }, close: { self.side = nil })
        case .web:
            WebPanel(onClose: { self.side = nil })
                .frame(width: 440)
                .clipShape(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous))
                .atelierPanel()
        }
    }
}

// MARK: - Pellicule des pages

/// Bande de miniatures (comme une planche contact) : touche pour aller à la page.
struct PageFilmstrip: View {
    @ObservedObject var reader: ReaderController

    var body: some View {
        // Pages réellement à l'écran : une en page simple, la planche en double page (recette 1.3.2 (59), A2).
        let visible = FilmstripLayout.highlightedPages(current: reader.currentSourcePage, shown: reader.shownSources,
                                                       isDouble: reader.settings.layout == .double)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(0..<reader.document.pageCount, id: \.self) { page in
                        FilmstripCell(thumbnails: reader.model.thumbnails, documentId: reader.document.id, fileURL: reader.fileURL, page: page,
                                      label: reader.document.pageLabel(page),
                                      visible: visible.contains(page))
                            .id(page)
                            .onTapGesture { reader.go(toSource: page) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .environment(\.layoutDirection, reader.settings.direction == .rightToLeft ? .rightToLeft : .leftToRight)
            .onAppear { proxy.scrollTo(reader.currentSourcePage, anchor: .center) }
            .onChange(of: reader.currentSourcePage) { page in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(page, anchor: .center) }
            }
        }
        .frame(height: 96)
        .atelierPanel(radius: 20)
    }
}

struct FilmstripCell: View {
    let thumbnails: ThumbnailCache
    let documentId: String
    let fileURL: URL
    let page: Int
    let label: String
    let visible: Bool
    @State private var image: UIImage?

    /// Repère des pages à l'écran : bleu vif fixe, lisible sur tous les thèmes, là où la teinte « lecture »
    /// (pastel, jaune pâle selon le thème) se voyait mal sur les miniatures (recette 1.3.2 (59), A2).
    static let visibleMark = Color(hex: 0x0A84FF)

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Atelier.surfaceHigh)
                if let image { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 4)) }
            }
            .frame(width: 46, height: 62)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(visible ? Self.visibleMark : .clear, lineWidth: 3))
            Text(label).font(.system(size: 10, weight: visible ? .bold : .semibold, design: .monospaced))
                .foregroundStyle(visible ? Self.visibleMark : Atelier.textTertiary)
        }
        .onAppear(perform: load)
    }

    private func load() {
        if let cached = thumbnails.cached(documentId: documentId, page: page, width: 120) {
            image = cached
        } else {
            thumbnails.thumbnail(documentId: documentId, fileURL: fileURL, page: page, width: 120) { image = $0 }
        }
    }
}

/// Pastille d'état OCR à côté du numéro de page.
struct OCRStatusDot: View {
    @ObservedObject var reader: ReaderController
    /// Moteur affiché, gardé un instant quand le résultat OCR est effacé au changement de page (RET-041, #60).
    @State private var engine: String?
    @State private var clearTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch reader.ocrState {
            case .running:
                HStack(spacing: 4) { ProgressView().controlSize(.mini).tint(Atelier.Tint.japanese); Text("lecture…") }
                    .font(.system(size: 11))
            case .failed:
                Label("OCR", systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
            case .idle:
                if let engine {
                    HStack(spacing: 4) {
                        Circle().fill(Atelier.Tint.japanese).frame(width: 6, height: 6)
                        Text(OCREngineID.displayName(engine)).font(.system(size: 11))
                    }
                }
            }
        }
        .onAppear { engine = reader.ocrPage?.engine }
        .onChange(of: reader.ocrPage?.engine) { incoming in
            switch OCRPillHold.step(shown: engine, incoming: incoming) {
            case .show(let shown):
                clearTask?.cancel()
                engine = shown
            case .holdThenClear:
                clearTask?.cancel()
                clearTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(OCRPillHold.holdDelay * 1_000_000_000))
                    // Toujours rien pour la nouvelle page : la pastille disparaît.
                    if !Task.isCancelled, reader.ocrPage == nil { engine = nil }
                }
            case .keep:
                break
            }
        }
        .onDisappear { clearTask?.cancel() }
    }
}

struct PDFViewHost: UIViewRepresentable {
    let view: ReaderPDFView
    func makeUIView(context: Context) -> ReaderPDFContainer { ReaderPDFContainer(pdfView: view) }
    func updateUIView(_ uiView: ReaderPDFContainer, context: Context) {}
}

/// Conteneur sans taille intrinsèque de PDF : il respecte la place réservée par SwiftUI.
/// La vue PDF est conservée et son point de lecture est capturé AVANT de changer ses dimensions.
final class ReaderPDFContainer: UIView {
    let pdfView: ReaderPDFView
    private var transitionSnapshot: UIView?

    init(pdfView: ReaderPDFView) {
        self.pdfView = pdfView
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(pdfView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non pris en charge") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, pdfView.frame != bounds else { return }
        transitionSnapshot?.removeFromSuperview()
        transitionSnapshot = nil
        let enabled = UserDefaults.standard.object(forKey: StudyPanelMotion.storageKey) as? Bool ?? true
        let oldSize = pdfView.bounds.size
        let snapshot = enabled && window != nil && pdfView.document != nil && oldSize.width > 0 && oldSize.height > 0
            ? pdfView.snapshotView(afterScreenUpdates: false) : nil
        pdfView.resizeViewport(to: bounds)
        guard let snapshot else { return }
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        snapshot.frame = CGRect(x: bounds.midX - oldSize.width / 2, y: bounds.midY - oldSize.height / 2,
                                width: oldSize.width, height: oldSize.height)
        addSubview(snapshot)
        transitionSnapshot = snapshot
        // Le recalage du zoom est déjà en file sur le fil principal : démarrer le fondu après lui.
        DispatchQueue.main.async { [weak self, weak snapshot] in
            guard let self, let snapshot, self.transitionSnapshot === snapshot else { return }
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.14 : 0.24,
                           delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
                snapshot.alpha = 0
            } completion: { [weak self, weak snapshot] _ in
                snapshot?.removeFromSuperview()
                if self?.transitionSnapshot === snapshot { self?.transitionSnapshot = nil }
            }
        }
    }
}

struct HighlightMenu: View {
    var onPick: (HighlightColor) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "highlighter").foregroundStyle(Atelier.Tint.annotate)
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button { onPick(color) } label: {
                    Circle().fill(Color(color.uiColor)).frame(width: 26, height: 26)
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Surligner en \(color.frenchName)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .atelierPanel(radius: 26)
    }
}

extension HighlightColor {
    var frenchName: String {
        switch self {
        case .yellow: return "jaune"
        case .green: return "vert"
        case .blue: return "bleu"
        case .pink: return "rose"
        case .orange: return "orange"
        }
    }
}

/// Surlignage du mot touché (dans le repère de la vue PDF).
struct LookupHighlightLayer: View {
    let rects: [CGRect]

    var body: some View {
        Canvas { context, _ in
            for r in rects where r.width > 0 {
                context.fill(Path(roundedRect: r.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3),
                             with: .color(Atelier.Tint.japanese.opacity(0.32)))
                context.stroke(Path(CGRect(x: r.minX, y: r.maxY + 1, width: r.width, height: 0)).strokedPath(.init(lineWidth: 2)),
                               with: .color(Atelier.Tint.japanese))
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: rects)
    }
}

/// Où poser le popup du dictionnaire sans cacher le mot ni la suite du texte, comme Yomitan :
/// texte horizontal → sous la ligne (au-dessus s'il n'y a pas la place) ;
/// texte vertical → à droite de la colonne (déjà lue), sinon à gauche.
enum PopupPlacement {
    static func frame(for request: ReaderController.LookupRequest, in size: CGSize) -> CGRect {
        let margin: CGFloat = 16, gap: CGFloat = 10
        let word = request.wordRect.isEmpty ? CGRect(origin: request.anchor, size: CGSize(width: 1, height: 1)) : request.wordRect
        let w = min(440, size.width - 2 * margin)
        if request.vertical {
            let h = min(560, size.height - 2 * margin)
            let rightX = word.maxX + gap
            let x = rightX + w <= size.width - margin ? rightX : max(margin, word.minX - gap - w)
            let y = min(max(margin, word.minY - 40), size.height - h - margin)
            return CGRect(x: x, y: y, width: w, height: h)
        }
        let below = size.height - margin - (word.maxY + gap)
        let above = word.minY - gap - margin
        let useBelow = below >= min(320, above) || below >= 420
        let h = max(200, min(520, useBelow ? below : above))
        let x = min(max(margin, word.minX - 30), size.width - w - margin)
        let y = useBelow ? word.maxY + gap : max(margin, word.minY - gap - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// Mode « Surligner l'OCR » (#23) : capte le glisser (doigt, Pencil, souris ou trackpad cliqué) au-dessus de la page
/// et montre l'aperçu ; le défilement à un doigt est suspendu tant que le mode est actif (‹ › et ← → tournent les
/// pages). Repère : celui de la vue PDF (même `ZStack`, comme `LookupHighlightLayer`).
struct OCRHighlightDragLayer: View {
    @ObservedObject var reader: ReaderController
    let color: HighlightColor
    @State private var started = false

    var body: some View {
        Canvas { context, _ in
            for r in reader.ocrHighlightPreview where r.width > 0 {
                context.fill(Path(roundedRect: r.insetBy(dx: -1, dy: -1), cornerRadius: 2),
                             with: .color(Color(color.uiColor).opacity(0.45)))
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !started {
                    started = true
                    Task { await reader.ocrHighlightBegan(at: value.startLocation) }
                } else {
                    reader.ocrHighlightMoved(to: value.location)
                }
            }
            .onEnded { _ in
                started = false
                reader.ocrHighlightEnded(color: color)
            })
        .accessibilityLabel("Zone de surlignage : glisser sur le texte de la page")
    }
}

/// Commandes du mode « Surligner l'OCR » (recette 1.3.2 (62), L5) : surligner ou gommer, annuler (⌘Z), terminer.
struct OCRHighlightControls: View {
    @ObservedObject var reader: ReaderController

    var body: some View {
        HStack(spacing: 12) {
            Picker("Outil", selection: $reader.ocrHighlightErasing) {
                Label("Surligner", systemImage: "highlighter").tag(false)
                Label("Gomme", systemImage: "eraser").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            Button { reader.undoHighlight() } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(reader.highlightUndo.isEmpty)
                .accessibilityLabel("Annuler (⌘ Z)")
            Button("Terminé") { reader.setOCRHighlightMode(false) }
                .fontWeight(.semibold)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .font(.system(size: 14))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .atelierPanel(radius: 20)
    }
}
