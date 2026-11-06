// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import GLMOCRKit
import ONNXOCRKit
import ReaderCore
import DictionaryKit
import SwiftUI

/// Panneau d'étude, à droite du lecteur : tout ce qui sert à **comprendre** la page.
/// Texte (OCR) + traduction, dictionnaire, notes, signets.
struct StudyPanel: View {
    enum Tab: Hashable { case text, vocab, notes, marks, chat }

    @EnvironmentObject private var model: AppModel
    @ObservedObject var reader: ReaderController
    @Binding var tab: Tab
    var openSearch: () -> Void
    /// Présentée par `ReaderScreen` : ce panneau est recréé quand l'iPad tourne, et la fenêtre fermée avec lui.
    var openLineEditor: () -> Void
    var close: () -> Void
    /// Colonne de droite : largeur fixe ; fenêtre ou plein écran (`DetachedPanel`) : toute la place donnée.
    var fixedWidth = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if tab != .vocab && tab != .chat && reader.shownSources.count > 1 {
                    // Double page : une pilule par page affichée, le panneau travaille sur celle choisie.
                    HStack(spacing: 6) {
                        ForEach(reader.shownSources, id: \.self) { source in
                            let on = source == reader.focusSource
                            Button { reader.focus(source) } label: {
                                Text("p. \(reader.document.pageLabel(source))")
                                    .font(Atelier.font(13, weight: .semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .foregroundStyle(on ? Atelier.onAccentInk.opacity(0.85) : Atelier.textSecondary)
                                    .background(Capsule().fill(on ? Atelier.Tint.japanese : Atelier.surfaceHigh))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Travailler sur la page \(reader.document.pageLabel(source))")
                        }
                    }
                } else if tab == .vocab || tab == .chat {
                    AtelierLabel(tab == .chat ? String(localized: "Chat du livre") : String(localized: "Dictionnaire"), tint: tab == .chat ? Atelier.Tint.ai : Atelier.Tint.japanese)
                } else {
                    AtelierLabel(String(localized: "Étude · page \(reader.document.pageLabel(reader.focusSource))"), tint: Atelier.textSecondary)
                }
                Spacer()
                StudyWindowButtons()
                Button(action: close) {
                    Image(systemName: "xmark").font(Atelier.font(14, weight: .semibold))
                        .foregroundStyle(Atelier.textSecondary)
                        .frame(minWidth: 22, minHeight: 22)
                }
                .padding(.leading, 6)
                .accessibilityLabel("Fermer le panneau d'étude")
            }
            PillTabs(items: [(Tab.text, "character.ja", String(localized: "Texte")), (.vocab, "character.book.closed.ja", String(localized: "Dico")),
                             (.notes, "text.bubble", String(localized: "Notes")), (.marks, "bookmark", String(localized: "Repères")),
                             (.chat, "bubble.left.and.bubble.right", String(localized: "Chat"))]
                                .filter { $0.0 != .chat || reader.document.capabilities.chat },
                     selection: $tab, tint: tint)
            Group {
                switch tab {
                case .text: StudyTextTab(reader: reader, openLineEditor: openLineEditor)
                case .vocab:
                    DictionarySearchView(dictionary: model.dictionary, added: model.review.keys, compact: true) { term in
                        let sentence = reader.ocrPage?.lines.first { $0.text.contains(term.matchedText) }?.text
                        return model.review.add(term,
                                         sentence: sentence,
                                         source: sentence == nil ? nil :
                                             "\(reader.document.title) · p. \(reader.document.pageLabel(reader.focusSource))",
                                         image: nil, documentId: sentence == nil ? nil : reader.document.id,
                                         page: sentence == nil ? nil : reader.focusSource,
                                         dictionary: model.dictionary)
                    }
                case .notes: StudyNotesTab(reader: reader)
                case .marks: StudyMarksTab(reader: reader, openSearch: openSearch)
                // Onglet repris d'un document précédent : pas de chat sur un manga.
                case .chat where !reader.document.capabilities.chat: StudyTextTab(reader: reader, openLineEditor: openLineEditor)
                case .chat: QwenChatView(document: reader.document, embedded: true,
                                         focusPage: reader.document.pageLabel(reader.focusSource),
                                         openPage: { reader.go(toSource: $0) },
                                         saveToNotes: { text in
                                             reader.saveNote(PageComment(documentId: reader.document.id, pageIndex: reader.focusSource,
                                                                         body: String(localized: "Chat IA :\n") + text))
                                         }, database: model.database)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .frame(width: fixedWidth ? Atelier.panelWidth : nil)
        .frame(maxWidth: fixedWidth ? nil : .infinity, maxHeight: .infinity)
        .atelierPanel()
        // Onglet Chat repris d'un document qui l'avait : ramené sur Texte dès la reprise, titre et pilules compris
        // (revue après recette 1.4.8, P3 1).
        .onAppear(perform: normalizeTab)
        .onChange(of: reader.document.id) { _ in normalizeTab() }
    }

    private func normalizeTab() {
        if tab == .chat && !reader.document.capabilities.chat { tab = .text }
    }

    private var tint: Color {
        switch tab {
        case .text, .vocab: return Atelier.Tint.japanese
        case .notes: return Atelier.Tint.annotate
        case .marks: return Atelier.Tint.read
        case .chat: return Atelier.Tint.ai
        }
    }
}

// MARK: - Texte + traduction

struct StudyTextTab: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var reader: ReaderController
    var openLineEditor: () -> Void
    /// `reader.rereading` vient d'ici.
    @ObservedObject private var aiTasks = AITaskCenter.shared
    @ObservedObject private var deepl = DeepLService.shared
    @State private var translation: String?
    /// Texte mis en forme (titres, paragraphes, tableaux) ou tel que lu, ligne par ligne.
    @AppStorage("study.formattedText") private var formatted = true
    /// 3e affichage : la page mise en forme par OvisOCR2 (`AILayoutView`).
    @AppStorage("study.aiLayout") private var aiLayout = false
    /// Furigana (dictionnaire Yomitan) sur le texte extrait ; un appui ouvre le dictionnaire.
    @AppStorage("study.furigana") private var furigana = false
    /// Moteur de mise en page du mode « Mis en forme » (géométrie seule, PP-DocLayout, DocLayout-YOLO).
    @AppStorage("study.layoutEngine") private var layoutEngineRaw = LayoutDetector.Engine.geometry.rawValue
    @State private var regions: [OCRLayout.Region] = []
    @State private var layoutError: String?
    /// Session réutilisée pendant toute la vie du panneau (les résultats restent en mémoire entre deux mots).
    @State private var lookup: LookupSession?
    /// Vue agrandie (« Agrandir » dans la bulle) : la feuille reçoit **cette valeur** (`sheet(item:)`), pas une
    /// capture de `lookup`. Avec `sheet(isPresented:)`, le contenu lisait encore `lookup == nil` au premier
    /// toucher après l'ouverture du livre, et la feuille s'ouvrait vide (RET-009, Issue #12).
    @State private var presentedLookup: LookupSession?
    /// Bulle de contexte ancrée au mot (Issue #13), à la place de la feuille plein écran.
    @State private var bubble: PanelBubble?
    /// Pointeur (souris, trackpad) au-dessus de la bulle : elle ne se ferme pas tant qu'il y reste.
    @State private var pointerInBubble = false
    /// Annule les fermetures différées devenues caduques (RET-042, #61).
    @State private var hoverGate = HoverBubbleGate()
    /// Incrémenté à chaque fermeture : la vue web oublie le mot survolé (sinon il ne rouvrirait pas).
    @State private var hoverReset = 0
    @ObservedObject private var shift = ShiftKey.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var translating = false
    @State private var translateError: String?
    @State private var showCompare = false
    @State private var query = ""
    @State private var matches: [PageTextSearch.Match] = []
    /// Les indices de lignes ne valent que pour cet OCR et cette page, capturés à l'ouverture du dialogue.
    private struct LineCorrectionDraft {
        let index: Int
        let page: OCRPage
        let source: Int
    }
    @State private var editingLine: LineCorrectionDraft?
    @State private var showVerify = false
    @State private var lineDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Barre de langue de la mise en page IA, hors du défilement : visible même en bas de la page (#17).
            if aiLayout, query.isEmpty, reader.ocrPage != nil { AILayoutLanguageBar(reader: reader) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if reader.ocrPage != nil { PageSearchField(query: $query) }
                    engineRow
                    verificationRow
                    switch (reader.ocrPage, reader.ocrState) {
                    case (_, .running):
                        HStack(spacing: 10) { ProgressView().tint(Atelier.Tint.japanese); Text("Lecture de la page…") }
                            .foregroundStyle(Atelier.textSecondary)
                    case (_, .failed(let message)):
                        Text(message).foregroundStyle(Atelier.textSecondary)
                        Button("Lire avec Apple Vision") { reader.runOCR(engine: OCREngineID.vision) }
                            .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.japanese))
                    case (_, _) where !query.isEmpty && reader.ocrPage != nil:
                        PageSearchResults(matches: matches)
                    case (let page?, _):
                        if let layoutError, formatted {
                            Text(layoutError).font(.caption).foregroundStyle(Atelier.textTertiary)
                        }
                        doubtRow(page)
                        if aiLayout {
                            AILayoutView(reader: reader, furigana: furigana, hoverReset: hoverReset) { handleLookup($0) }
                        } else if furigana {
                            FuriganaTextView(page: page, formatted: formatted, regions: regions, hoverReset: hoverReset) { handleLookup($0) }
                        } else if formatted {
                            FormattedOCRText(page: page, regions: regions)
                        } else {
                            // Brut : une ligne par ligne lue, caractères douteux soulignés, appui long → corriger.
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(Array(page.lines.enumerated()), id: \.offset) { index, line in
                                    Text(Self.marked(line))
                                        .font(Atelier.jp)
                                        .foregroundStyle(Atelier.textPrimary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contextMenu {
                                            Button {
                                                lineDraft = line.text
                                                editingLine = LineCorrectionDraft(index: index, page: page, source: reader.focusSource)
                                            } label: {
                                                Label("Corriger cette ligne", systemImage: "pencil")
                                            }
                                        }
                                }
                            }
                        }
                        translationBlock(for: page.text)
                    default:
                        Text("La page n'a pas encore été lue.").foregroundStyle(Atelier.textSecondary)
                        Button { reader.runOCR() } label: { Label("Lire la page", systemImage: "text.viewfinder") }
                            .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.japanese))
                    }
                    documentOCRRow
                }
            }
        }
        .task(id: "\(query)|\(reader.focusSource)|\(reader.ocrPage?.hashValue ?? 0)") {
            guard let page = reader.ocrPage, !query.isEmpty else { matches = []; return }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let q = query
            let found = await Task.detached { PageTextSearch.search(q, in: page) }.value
            if !Task.isCancelled { matches = found }
        }
        .onChange(of: reader.focusSource) { _ in
            translation = nil
            translateError = nil
        }
        .task(id: "\(reader.focusSource)|\(layoutEngineRaw)|\(formatted)|\(reader.ocrPage != nil)") { await loadRegions() }
        // OvisOCR2 par défaut, une seule fois (#39) ; ensuite le choix de l'utilisateur reste.
        .onAppear {
            let defaults = UserDefaults.standard
            if OvisDefaultView.shouldSwitch(ovisInstalled: OvisOCR2Reader().isAvailable,
                                            alreadyApplied: defaults.bool(forKey: OvisDefaultView.appliedKey)) {
                aiLayout = true
                defaults.set(true, forKey: OvisDefaultView.appliedKey)
            }
        }
        .overlay(alignment: .topLeading) { bubbleOverlay }
        .onChange(of: shift.pressed) { pressed in
            // Bulle ouverte au survol avec Maj : relâcher Maj la ferme (Issue #13).
            if !pressed, bubble?.hover == true { closeBubble() }
        }
        .onChange(of: reader.focusSource) { _ in closeBubble() }
        .sheet(item: $presentedLookup, onDismiss: { lookup?.clear() }) { lookup in
            // Fenêtre compacte du dictionnaire (mot touché dans le texte à furigana).
            LookupPopup(session: lookup, added: model.review.keys, onAddCard: { term in
                model.review.add(term, sentence: reader.ocrPage?.lines.first { $0.text.contains(term.matchedText) }?.text,
                                 source: "\(reader.document.title) · p. \(reader.document.pageLabel(reader.focusSource))",
                                 image: nil, documentId: reader.document.id, page: reader.focusSource,
                                 dictionary: model.dictionary)
            }, close: { presentedLookup = nil })
            .environmentObject(model.dictionary)
            .presentationDetents([.medium, .large])
            .preferredColorScheme(Theme.current.colorScheme)
        }
        .alert("Corriger la ligne", isPresented: Binding(get: { editingLine != nil }, set: { if !$0 { editingLine = nil } })) {
            TextField("Texte de la ligne", text: $lineDraft)
            Button("Annuler", role: .cancel) { editingLine = nil }
            Button("Garder") {
                if let editingLine {
                    reader.correctOCRLine(editingLine.index, text: lineDraft,
                                          original: editingLine.page, source: editingLine.source)
                }
                editingLine = nil
            }
        } message: {
            Text("Ta correction est gardée ; la relecture automatique n'y touchera plus.")
        }
        .sheet(isPresented: $showVerify) { VerifySheet(reader: reader).preferredColorScheme(Theme.current.colorScheme) }
        .sheet(isPresented: $showCompare) { CompareEnginesView(reader: reader).environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review) }
    }

    @ViewBuilder
    private var verificationRow: some View {
        if OvisOCR2Reader().isAvailable {
            let current = reader.verifications.filter { reader.shownSources.contains($0.source) }
            let count = current.reduce(0) { $0 + $1.suggestions.count }
            HStack(spacing: 10) {
                Button {
                    if !aiTasks.isRunning(reader.verifyKey) &&
                        (reader.verifyState != .done || current.count != reader.shownSources.count) {
                        reader.verifyShownPages()
                    }
                    showVerify = true
                } label: {
                    Label(count > 0 ? String(localized: "Corrections IA (\(count))") : String(localized: "Corrections IA"),
                          systemImage: "checkmark.seal")
                }
                Button {
                    reader.verifyShownPages(force: true)
                    showVerify = true
                } label: {
                    Label("Rescanner", systemImage: "arrow.clockwise")
                }
                .disabled(aiTasks.isRunning(reader.verifyKey))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Atelier.Tint.ai)
            Text("Comparer au texte OCR de la page · accepter les corrections dans la vérification.")
                .font(.caption2).foregroundStyle(Atelier.textTertiary)
        }
        // Hors de la condition : corriger le texte ne dépend d'aucun modèle.
        Button { openLineEditor() } label: {
            Label("Corriger le texte", systemImage: "pencil")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Atelier.Tint.ai)
        .disabled(reader.ocrPage == nil || reader.ocrState == .running)
    }

    /// Zones de mise en page de la page de travail (modèle choisi, gardées en mémoire par page).
    // MARK: Bulle de contexte du dictionnaire (Issue #13)

    struct PanelBubble: Identifiable {
        /// Gardé d'un mot à l'autre au survol (`HoverBubbleGate.reusesBubble`) : pas de nouvelle apparition à chaque mot.
        var id = UUID()
        let session: LookupSession
        /// Mot en coordonnées de la fenêtre (`.global`).
        let wordRect: CGRect
        /// Ouverte au survol avec Maj (fermée en quittant le mot ou en relâchant Maj) ou par un toucher/clic.
        let hover: Bool
    }

    private var bubbleAnimation: Animation { reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.18, dampingFraction: 0.9) }

    private func handleLookup(_ event: PanelLookupEvent) {
        switch event {
        case .open(let text, let wordRect, let hover):
            let session = lookup ?? LookupSession(dictionary: model.dictionary)
            lookup = session
            // Même mot déjà ouvert au survol : rien à refaire (évite de relancer la recherche à chaque mouvement).
            if let bubble, bubble.hover, hover, bubble.wordRect == wordRect { return }
            session.start(text)
            pointerInBubble = false
            hoverGate.opened()
            if let current = bubble, HoverBubbleGate.reusesBubble(currentIsHover: current.hover, incomingIsHover: hover) {
                // Autre mot survolé : la même bulle suit le pointeur, sans rejouer son apparition (RET-042, #61).
                var moved = PanelBubble(session: session, wordRect: wordRect, hover: hover)
                moved.id = current.id
                bubble = moved
            } else {
                withAnimation(bubbleAnimation) { bubble = PanelBubble(session: session, wordRect: wordRect, hover: hover) }
            }
        case .hoverEnd:
            guard bubble?.hover == true else { return }
            // Laisser le temps au pointeur d'entrer dans la bulle (elle est collée au mot). Si un autre mot s'ouvre
            // entre-temps, cette fermeture ne s'applique plus (RET-042, #61).
            let token = hoverGate.token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if hoverGate.shouldClose(token: token), bubble?.hover == true, !pointerInBubble { closeBubble() }
            }
        case .tapOutside:
            closeBubble()
        }
    }

    /// Ferme la bulle ; `keepSession` quand la vue agrandie reprend la même session.
    private func closeBubble(keepSession: Bool = false) {
        guard bubble != nil else { return }
        withAnimation(bubbleAnimation) { bubble = nil }
        pointerInBubble = false
        hoverReset &+= 1
        if !keepSession {
            // Après l'animation de sortie, pour ne pas vider la bulle pendant qu'elle disparaît.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if bubble == nil, presentedLookup == nil { lookup?.clear() } }
        }
    }

    @ViewBuilder private var bubbleOverlay: some View {
        GeometryReader { area in
            if let bubble {
                let origin = area.frame(in: .global).origin
                let word = bubble.wordRect.offsetBy(dx: -origin.x, dy: -origin.y)
                let frame = ContextBubbleLayout.frame(word: word, in: area.size)
                // La bulle « sort » du mot : ancre de l'animation sur le mot, en haut ou en bas selon le placement.
                let anchor = UnitPoint(x: frame.width > 0 ? min(max((word.midX - frame.minX) / frame.width, 0), 1) : 0.5,
                                       y: frame.minY >= word.maxY ? 0 : 1)
                LookupPopup(session: bubble.session, added: model.review.keys, onAddCard: { term in
                    model.review.add(term, sentence: reader.ocrPage?.lines.first { $0.text.contains(term.matchedText) }?.text,
                                     source: "\(reader.document.title) · p. \(reader.document.pageLabel(reader.focusSource))",
                                     image: nil, documentId: reader.document.id, page: reader.focusSource,
                                     dictionary: model.dictionary)
                }, compact: true, close: { closeBubble() })
                .environmentObject(model.dictionary)
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        let session = bubble.session
                        closeBubble(keepSession: true)
                        presentedLookup = session
                    } label: {
                        Label("Agrandir", systemImage: "arrow.up.left.and.arrow.down.right").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent).tint(Atelier.Tint.japanese).controlSize(.small)
                    .padding(8)
                }
                .frame(width: frame.width, height: frame.height)
                .onHover { inside in
                    if inside { pointerInBubble = true } else if pointerInBubble { closeBubble() }
                }
                .offset(x: frame.minX, y: frame.minY)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.85, anchor: anchor).combined(with: .opacity))
                .id(bubble.id)
            }
        }
    }

    private func loadRegions() async {
        layoutError = nil
        let engine = LayoutDetector.Engine(rawValue: layoutEngineRaw) ?? .geometry
        guard formatted, reader.ocrPage != nil, engine != .geometry else { regions = []; return }
        guard engine.isAvailable() else {
            regions = []
            layoutError = String(localized: "\(engine.title) n'est pas téléchargé (Réglages → Modèles) : mise en page par géométrie.")
            return
        }
        let key = "\(reader.document.id)-\(reader.focusSource)-\(engine.rawValue)"
        if let cached = LayoutRegionsCache.shared.get(key) { regions = cached; return }
        // Zones de l'ancienne page / de l'autre moteur : retirées tout de suite (géométrie en attendant).
        regions = []
        let url = reader.fileURL, page = reader.focusSource
        let rotation = await reader.model.ocr.additionalRotation(documentId: reader.document.id, pageIndex: page)
        let work = Task.detached(priority: .userInitiated) {
            Result {
                try LayoutDetector.regions(.pdfPage(url: url, index: page, additionalRotation: rotation), engine: engine)
            }
        }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let found):
            LayoutRegionsCache.shared.set(found, for: key)
            regions = found
        case .failure(let error):
            regions = []
            layoutError = String(localized: "Mise en page : \(error.localizedDescription) (géométrie utilisée).")
        }
    }

    private var engineRow: some View {
        HStack(spacing: 8) {
            Menu {
                // OvisOCR2 en tête (#39) : sa lecture s'affiche dans « Mise en page IA ».
                if OvisOCR2Reader().isAvailable {
                    Button { aiLayout = true } label: {
                        Label("OvisOCR2 (mise en page IA)", systemImage: "sparkles.rectangle.stack")
                    }
                    Divider()
                }
                ForEach([OCREngineID.pdfText, OCREngineID.vision] + OCREngineMenu.extra, id: \.self) { id in
                    // Quitter la mise en page IA : sinon le texte du moteur choisi resterait caché.
                    Button { aiLayout = false; reader.runOCR(engine: id) } label: {
                        Label(OCREngineID.displayName(id), systemImage: OCREngineMenu.icon(id))
                    }
                }
                Divider()
                Button("Relancer") { reader.runOCR(engine: reader.ocrPage?.engine, force: true) }
                Button("Comparer les moteurs") { showCompare = true }
                if OvisOCR2Reader().isAvailable {
                    Button {
                        reader.verifyShownPages()
                        showVerify = true
                    } label: {
                        Label(reader.shownSources.count > 1 ? String(localized: "Vérifier la double page (OvisOCR2)") : String(localized: "Vérifier la page (OvisOCR2)"),
                              systemImage: "checkmark.seal")
                    }
                }
            } label: {
                // Icône seule (le nom s'écrivait en colonne dans le panneau étroit) ; le nom est dans le menu.
                HStack(spacing: 4) {
                    Image(systemName: OCREngineMenu.icon(reader.ocrPage?.engine))
                    Image(systemName: "chevron.down").font(Atelier.font(10, weight: .bold))
                }
                .font(Atelier.font(13, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Atelier.surfaceHigh, in: Capsule())
            }
            Picker("Affichage", selection: Binding(get: { aiLayout ? 2 : (formatted ? 0 : 1) },
                                                   set: { aiLayout = $0 == 2; if $0 < 2 { formatted = $0 == 0 } })) {
                Text("Mis en forme").tag(0)
                Text("Brut").tag(1)
                Image(systemName: "sparkles").tag(2).accessibilityLabel("Mise en page IA")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 230)
            if formatted && !aiLayout {
                Menu {
                    LayoutEnginePicker(selection: $layoutEngineRaw)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.3.group")
                        Text(LayoutEngineMenu.engine(layoutEngineRaw).shortTitle)
                            .strikethrough(!LayoutEngineMenu.engine(layoutEngineRaw).isAvailable())
                    }
                    .font(Atelier.font(13, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Atelier.surfaceHigh, in: Capsule())
                }
                .accessibilityLabel("Moteur de mise en page : \(LayoutEngineMenu.engine(layoutEngineRaw).title)")
            }
            Toggle(isOn: $furigana) { Text("ふりがな").font(Atelier.font(13, weight: .semibold)) }
                .toggleStyle(.button)
                .accessibilityLabel("Furigana sur le texte extrait")
            Spacer()
            Button {
                guard let page = reader.ocrPage else { return }
                UIPasteboard.general.string = formatted ? OCRLayout.markdown(page) : page.text
            } label: { Image(systemName: "doc.on.doc") }
                .disabled(reader.ocrPage == nil)
                .accessibilityLabel(formatted ? String(localized: "Copier en Markdown") : String(localized: "Copier le texte"))
        }
        .foregroundStyle(Atelier.textPrimary)
    }

    /// Ligne avec ses caractères douteux soulignés (orange).
    static func marked(_ line: OCRLine) -> AttributedString {
        let doubt = Set(line.doubt ?? [])
        guard !doubt.isEmpty else { return AttributedString(line.text) }
        var out = AttributedString()
        for (i, c) in line.text.enumerated() {
            var piece = AttributedString(String(c))
            if doubt.contains(i) {
                piece.underlineStyle = Text.LineStyle(pattern: .solid, color: .orange)
                piece.backgroundColor = Color.orange.opacity(0.18)
            }
            out += piece
        }
        return out
    }

    /// « N caractères douteux » + relecture par l'IA (GLM-OCR) ou indication pour corriger à la main.
    @ViewBuilder
    private func doubtRow(_ page: OCRPage) -> some View {
        let lines = OCRProofreader.doubtful(page)
        let count = page.lines.reduce(0) { $0 + ($1.doubt?.count ?? 0) }
        if reader.rereading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Relecture par l'IA des lignes douteuses…").font(.caption)
            }
            .foregroundStyle(Atelier.textSecondary)
        } else if !lines.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(count > 0 ? String(localized: "\(count) caractère\(count > 1 ? "s" : "") douteux") : String(localized: "\(lines.count) ligne\(lines.count > 1 ? "s" : "") peu sûre\(lines.count > 1 ? "s" : "")"))
                    .font(.caption)
                Spacer()
                if GLMOCREngine().isAvailable {
                    Button("Relire avec l'IA") { reader.rereadDoubtful(force: true) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Atelier.Tint.ai)
                }
            }
            .foregroundStyle(Atelier.textSecondary)
            if formatted {
                Text("Pour corriger à la main : « Brut », puis appui long sur la ligne.")
                    .font(.caption2).foregroundStyle(Atelier.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func translationBlock(for text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AtelierLabel(String(localized: "Traduction"), tint: Atelier.Tint.ai)
            if let translation {
                Text(translation)
                    .font(Atelier.font(15))
                    .foregroundStyle(Atelier.textPrimary)
                    .textSelection(.enabled)
                Text("DeepL").font(.caption2).foregroundStyle(Atelier.textTertiary)
            } else if let translateError {
                Text(translateError).font(.footnote).foregroundStyle(Atelier.textSecondary)
            }
            if translation == nil {
                if deepl.hasKey {
                    Button {
                        Task { await translate(text) }
                    } label: {
                        HStack { if translating { ProgressView().tint(Atelier.onAccentInk) }; Text("Traduire en français") }
                    }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.ai))
                    .disabled(translating)
                } else {
                    Text("Traduction DeepL : ajoute ta clé dans Réglages → Traduction.")
                        .font(.footnote).foregroundStyle(Atelier.textTertiary)
                }
            }
        }
        .padding(12)
        .background(Atelier.surfaceHigh.opacity(0.6), in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
    }

    private var documentOCRRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Atelier.hairline)
            if let p = reader.documentOCRProgress {
                HStack {
                    ProgressView(value: Double(p.done), total: Double(max(p.total, 1))).tint(Atelier.Tint.japanese)
                    Text("\(p.done)/\(p.total)").font(Atelier.mono).foregroundStyle(Atelier.textSecondary)
                    Button { reader.cancelWholeDocumentOCR() } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(Atelier.textSecondary)
                }
            } else {
                Button { reader.ocrWholeDocument() } label: {
                    Label("Lire tout le document", systemImage: "doc.text.viewfinder")
                        .font(Atelier.font(14, weight: .semibold))
                }
                .foregroundStyle(Atelier.Tint.japanese)
                Text("Rend les pages photo (scans) cherchables. Une seule fois : le résultat est gardé.")
                    .font(.caption).foregroundStyle(Atelier.textTertiary)
            }
        }
    }

    private func translate(_ text: String) async {
        translating = true
        translateError = nil
        defer { translating = false }
        do { translation = try await DeepLService.shared.translate(text) }
        catch { translateError = error.localizedDescription }
    }
}

/// Moteur de mise en page : nom court pour le panneau, liste complète (modèles absents grisés).
enum LayoutEngineMenu {
    static func engine(_ raw: String) -> LayoutDetector.Engine { LayoutDetector.Engine(rawValue: raw) ?? .geometry }
}

extension LayoutDetector.Engine {
    var shortTitle: String {
        switch self {
        case .geometry: return String(localized: "Géo")
        case .ppDocLayout: return "PP"
        case .docLayoutYOLO: return "YOLO"
        }
    }
}

/// Choix du moteur de mise en page (panneau et Réglages) ; un modèle pas encore téléchargé est grisé.
struct LayoutEnginePicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Mise en page", selection: $selection) {
            ForEach(LayoutDetector.Engine.allCases, id: \.rawValue) { engine in
                Text(engine.isAvailable() ? engine.title : String(localized: "\(engine.title) — à télécharger (Modèles)"))
                    .tag(engine.rawValue)
                    .disabled(!engine.isAvailable())
            }
        }
    }
}

// MARK: - Texte OCR mis en forme

/// Texte OCR mis en forme : titres, paragraphes, tableaux (`OCRLayout`), calculé une fois par page.
struct FormattedOCRText: View {
    let page: OCRPage
    var regions: [OCRLayout.Region] = []
    @State private var blocks: [OCRLayout.Block] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks.indices, id: \.self) { i in
                switch blocks[i] {
                case .heading(let level, let text):
                    Text(text).font(Atelier.font(level == 1 ? 22 : 18, weight: .bold))
                        .foregroundStyle(Atelier.textPrimary).padding(.top, i == 0 ? 0 : 6)
                case .paragraph(let text):
                    Text(text).font(Atelier.jp).lineSpacing(7).foregroundStyle(Atelier.textPrimary)
                case .table(let rows):
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        ForEach(rows.indices, id: \.self) { r in
                            GridRow {
                                ForEach(rows[r].indices, id: \.self) { c in
                                    Text(rows[r][c]).font(r == 0 ? Atelier.jp.bold() : Atelier.jp)
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .overlay(Rectangle().strokeBorder(Atelier.hairline, lineWidth: Atelier.border(1)))
                                }
                            }
                        }
                    }
                    .foregroundStyle(Atelier.textPrimary)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(page.hashValue)|\(regions.hashValue)") {
            blocks = regions.isEmpty ? OCRLayout.blocks(page) : OCRLayout.blocks(page, regions: regions)
        }
    }
}

// MARK: - Notes de la page

struct StudyNotesTab: View {
    @ObservedObject var reader: ReaderController
    /// Texte affiché ; sa source de vérité est `NoteDraftStore` (un brouillon par page source, RET-008).
    /// Cet onglet est recréé à chaque changement de mode et à chaque ouverture du livre : rien ne doit
    /// vivre seulement dans ce `@State`.
    @State private var draft = ""
    /// Page à laquelle appartient `draft`. Toujours mise à jour **avant** `draft`, pour qu'une
    /// modification ne soit jamais enregistrée sur la page qu'on vient de quitter.
    @State private var draftPage: Int?
    @FocusState private var focused: Bool
    /// Pages dont le brouillon n'est pas encore ajouté (RET-051). Relu depuis `NoteDraftStore` à l'ouverture,
    /// au changement de page et après chaque enregistrement : le disque reste la seule source de vérité.
    @State private var pendingPages: [Int] = []
    @State private var markdownFile: SharedFile?
    /// Note en cours de modification dans la liste, et son texte (recette 1.3.2 (62), N1).
    @State private var editingID: String?
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    private var page: Int { reader.focusSource }
    private let drafts = NoteDraftStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Note sur cette page…").foregroundStyle(Atelier.textTertiary).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $draft)
                    .focused($focused)
                    .onChange(of: draft) { saveDraft($0) }
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90, maxHeight: 140)
                    .foregroundStyle(Atelier.textPrimary)
            }
            .padding(8)
            .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
            HStack {
                Button("Ajouter") { add() }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.annotate))
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button { reader.newNote() } label: { Label("Flottante", systemImage: "note.text.badge.plus") }
                    .font(Atelier.font(13, weight: .semibold))
                    .foregroundStyle(Atelier.Tint.annotate)
                Spacer()
                // Notes, surlignages et signets du livre en fichier `.md`, écrit d'abord puis partagé (recette
                // 1.3.2 (61) : l'ancien partage n'ouvrait rien sur l'iPad).
                Button { shareMarkdown() } label: {
                    Label("Markdown", systemImage: "square.and.arrow.up").font(Atelier.font(13, weight: .semibold))
                }
                .foregroundStyle(Atelier.Tint.annotate)
                .accessibilityHint("Partage les notes, surlignages et signets du livre en fichier Markdown")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // Un avertissement par brouillon : il reste tant que « Ajouter » n'a pas créé la note.
                    ForEach(pendingPages, id: \.self) { pendingWarning($0) }
                    let here = reader.notes.filter { $0.pageIndex == page }
                    let others = reader.notes.filter { $0.pageIndex != page }
                    if here.isEmpty { Text("Aucune note sur cette page.").font(.footnote).foregroundStyle(Atelier.textTertiary) }
                    dayGroups(here, showPage: false)
                    if !others.isEmpty {
                        AtelierLabel(String(localized: "Autres pages")).padding(.top, 6)
                        dayGroups(others, showPage: true)
                    }
                }
            }
        }
        .sheet(item: $markdownFile) { ActivityShareSheet(url: $0.url) }
        .onAppear { loadDraft(page); refreshPending() }
        .onChange(of: page) { loadDraft($0); refreshPending() }
    }

    private func refreshPending() {
        pendingPages = NoteDraftStore.pendingPages(drafts.drafts(documentId: reader.document.id))
    }

    /// Petit avertissement d'un brouillon non ajouté ; toucher celui d'une autre page y mène.
    private func pendingWarning(_ pending: Int) -> some View {
        Button { if pending != page { reader.go(toSource: pending) } } label: {
            Label(pending == page ? String(localized: "Brouillon non ajouté sur cette page")
                                  : String(localized: "Brouillon non ajouté · p. \(reader.document.pageLabel(pending))"),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint(pending == page ? String(localized: "Touche Ajouter pour créer la note") : String(localized: "Ouvre la page du brouillon"))
    }

    /// Affiche le brouillon de `page`. Celui de la page quittée est déjà sur disque (écrit à chaque frappe).
    private func shareMarkdown() {
        let text = MarkdownExporter.export(title: reader.document.title, comments: reader.notes,
                                           highlights: reader.allHighlights, bookmarks: reader.bookmarks)
        do {
            markdownFile = SharedFile(url: try MarkdownShareFile.write(text, title: reader.document.title))
        } catch {
            Diagnostics.error("Export Markdown impossible : \(error.localizedDescription)", "notes")
        }
    }

    private func loadDraft(_ page: Int) {
        guard draftPage != page else { return }
        draftPage = page
        draft = drafts.draft(documentId: reader.document.id, page: page)
    }

    /// Écrit à chaque modification (fichier atomique, quelques octets) : survit à un arrêt brutal de l'app.
    private func saveDraft(_ text: String) {
        guard let draftPage else { return }
        do {
            try drafts.setDraft(text, documentId: reader.document.id, page: draftPage)
        } catch {
            Diagnostics.error("Brouillon de note non enregistré : \(error.localizedDescription)", "notes")
        }
        refreshPending()
    }

    /// Toucher : ouvrir la note dans la fenêtre flottante ; ＊ : aller au mot ancré.
    /// Notes séparées par jour de création (« Aujourd'hui », « Hier », date), du plus récent au plus ancien
    /// (RET-019, #22).
    @ViewBuilder private func dayGroups(_ notes: [PageComment], showPage: Bool) -> some View {
        ForEach(NoteDayGroups.group(notes), id: \.day) { group in
            Text(group.title).font(.caption.weight(.semibold)).foregroundStyle(Atelier.textTertiary).padding(.top, 2)
            ForEach(group.notes) { note($0, showPage: showPage) }
        }
    }

    private func note(_ comment: PageComment, showPage: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: Atelier.corner(2)).fill(Atelier.Tint.annotate).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if showPage { Text("p. \(reader.document.pageLabel(comment.pageIndex))").font(Atelier.mono).foregroundStyle(Atelier.textTertiary) }
                    if comment.drawing != nil { Image(systemName: "scribble").font(.caption).foregroundStyle(Atelier.textTertiary) }
                    if comment.anchorRect != nil {
                        Button { reader.goToAnchor(comment) } label: {
                            Text("＊ \(comment.anchorText ?? String(localized: "ancre"))").font(.caption.weight(.semibold)).foregroundStyle(Atelier.Tint.annotate)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if editingID == comment.id {
                    // Modification sur place : la fenêtre flottante ne montrait pas le texte (recette 62, N1).
                    TextEditor(text: $editText)
                        .focused($editFocused)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 70, maxHeight: 160)
                        .padding(4)
                        .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
                    HStack {
                        Button("Enregistrer") { saveEdit(comment) }
                            .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.annotate))
                            .keyboardShortcut(.return, modifiers: .command)
                        Button("Annuler") { editingID = nil }
                            .font(Atelier.font(13, weight: .semibold))
                            .keyboardShortcut(.cancelAction)
                    }
                } else {
                    Text(comment.body.isEmpty ? String(localized: "(note sans texte)") : comment.body)
                        .foregroundStyle(comment.body.isEmpty ? Atelier.textTertiary : Atelier.textPrimary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .trailing, spacing: 6) {
                // Heure de création, discrète sur le côté (RET-019, #22).
                Text(NoteDayGroups.time(comment.createdAt)).font(Atelier.mono).foregroundStyle(Atelier.textTertiary)
                    .accessibilityLabel("créée à \(NoteDayGroups.time(comment.createdAt))")
                // Modifier : le texte se modifie ici même (recette 1.3.2 (62), N1). Toucher la note ouvre toujours
                // sa fenêtre flottante, pour le dessin.
                Button { startEdit(comment) } label: {
                    Image(systemName: "square.and.pencil").font(Atelier.font(13, weight: .semibold))
                        .foregroundStyle(Atelier.Tint.annotate)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Modifier la note")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if editingID != comment.id { reader.openNote = comment } }
        .contextMenu {
            Button { startEdit(comment) } label: { Label("Modifier le texte", systemImage: "square.and.pencil") }
            Button { reader.openNote = comment } label: { Label("Ouvrir en fenêtre (dessin)", systemImage: "macwindow") }
            if showPage { Button { reader.go(toSource: comment.pageIndex) } label: { Label("Aller à la page", systemImage: "arrow.right") } }
            Button(role: .destructive) { reader.deleteNote(comment) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func startEdit(_ comment: PageComment) {
        editText = comment.body
        editingID = comment.id
        editFocused = true
    }

    /// Enregistre seulement un vrai changement ; la note relue dans `reader.notes` (une fenêtre a pu la changer).
    private func saveEdit(_ comment: PageComment) {
        let current = reader.notes.first { $0.id == comment.id } ?? comment
        if let edited = current.editing(body: editText) { reader.saveNote(edited) }
        editingID = nil
    }

    private func add() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        reader.saveNote(PageComment(documentId: reader.document.id, pageIndex: page, body: body))
        draft = "" // `onChange` efface aussi le brouillon enregistré de cette page.
        focused = false
    }
}

struct StudyMarksTab: View {
    @ObservedObject var reader: ReaderController
    var openSearch: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: openSearch) {
                    Label("Rechercher dans le document", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
                }
                .foregroundStyle(Atelier.textPrimary)
                AtelierLabel(String(localized: "Signets · \(reader.bookmarks.count)"), tint: Atelier.Tint.read)
                if reader.bookmarks.isEmpty {
                    // Même symbole que le bouton « Signet » de la barre du haut (`bookmark`), pas une étoile (RET-028, #43).
                    Text("Touche \(Image(systemName: "bookmark")) en haut pour marquer une page.")
                        .font(.footnote).foregroundStyle(Atelier.textTertiary)
                        .accessibilityLabel("Touche le bouton Signet en haut pour marquer une page.")
                }
                ForEach(reader.bookmarks) { b in
                    row(icon: "bookmark.fill", tint: Atelier.Tint.read, title: b.title, page: b.pageIndex)
                }
                AtelierLabel(String(localized: "Surlignages · \(reader.allHighlights.count)"), tint: Atelier.Tint.annotate)
                ForEach(reader.allHighlights) { h in
                    row(icon: "highlighter", tint: Color(h.color.uiColor), title: h.text.isEmpty ? "—" : h.text, page: h.pageIndex)
                }
            }
        }
    }

    private func row(icon: String, tint: Color, title: String, page: Int) -> some View {
        Button { reader.go(toSource: page) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).lineLimit(2).foregroundStyle(Atelier.textPrimary)
                Spacer()
                Text(reader.document.pageLabel(page)).font(Atelier.mono).foregroundStyle(Atelier.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Zones de mise en page déjà calculées (mémoire, quelques pages).
@MainActor
final class LayoutRegionsCache {
    static let shared = LayoutRegionsCache()
    private var entries: [String: [OCRLayout.Region]] = [:]
    private var order: [String] = []

    func get(_ key: String) -> [OCRLayout.Region]? { entries[key] }

    func set(_ regions: [OCRLayout.Region], for key: String) {
        entries[key] = regions
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > 30 { entries[order.removeFirst()] = nil }
    }

    func clear() { entries = [:]; order = [] }
}

/// Identité d'objet : `sheet(item:)` présente la session elle-même (RET-009).
extension LookupSession: Identifiable {}

/// Correction du texte de la page : lignes de l'OCR, ou lecture OvisOCR2 entière. Écran à part : dans le panneau,
/// l'appui long sur une ligne sélectionnable est pris par la sélection de texte et le menu « Corriger cette ligne »
/// n'apparaît pas. Travaille sur le résultat présent à l'ouverture : les numéros de ligne ne valent que pour lui.
struct OCRLineEditor: View {
    private enum Source: Hashable { case ocr, ovis }

    @ObservedObject var reader: ReaderController
    @Environment(\.dismiss) private var dismiss
    private let original: OCRPage?
    private let source: Int
    private let ovisOriginal: String?
    @State private var drafts: [Int: String] = [:]
    @State private var ovisDraft: String
    @State private var kind: Source
    @State private var outdated = false
    @State private var confirmingUndo = false
    @State private var confirmingDiscard = false

    /// Saisie non enregistrée : la fermeture demande confirmation, y compris d'un toucher à côté.
    private var isDirty: Bool {
        if let ovisOriginal, ovisDraft != ovisOriginal { return true }
        guard let original else { return false }
        return drafts.contains { original.lines.indices.contains($0.key) && original.lines[$0.key].text != $0.value }
    }

    init(reader: ReaderController) {
        self.reader = reader
        original = reader.ocrPage
        source = reader.focusSource
        let ovis = DocumentAITextStore.read(documentId: reader.document.id, reader: ModelSpec.ovisocr2.id, page: reader.focusSource)
        ovisOriginal = ovis
        _ovisDraft = State(initialValue: ovis ?? "")
        _kind = State(initialValue: ovis == nil ? .ocr : .ovis)
    }

    var body: some View {
        NavigationStack {
            List {
                if outdated {
                    Label("Le texte de cette page a changé pendant ta correction : rien n'a été enregistré. Ferme cet écran et recommence.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if ovisOriginal != nil, original != nil {
                    Picker("Texte", selection: $kind) {
                        Text("Lecture OvisOCR2").tag(Source.ovis)
                        Text("Lignes de l'OCR").tag(Source.ocr)
                    }
                    .pickerStyle(.segmented)
                }
                switch kind {
                case .ovis:
                    TextEditor(text: $ovisDraft).font(Atelier.jp).frame(minHeight: 320)
                case .ocr:
                    ForEach(Array((original?.lines ?? []).enumerated()), id: \.offset) { index, line in
                        TextField("Texte de la ligne", text: Binding(
                            get: { drafts[index] ?? line.text },
                            set: { drafts[index] = $0 }
                        ), axis: .vertical)
                        .font(Atelier.jp)
                    }
                }
            }
            // Barre fixe en haut : dans la liste il s'affichait coupé (recette 1.4.1, 2.3), en bas la barre du clavier le
            // cachait (recette 1.4.5, 5.1).
            .safeAreaInset(edge: .top, spacing: 0) {
                if reader.hasCorrections {
                    Button("Annuler mes corrections de cette page", role: .destructive) { confirmingUndo = true }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(.bar)
                }
            }
            .navigationTitle("Corriger le texte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { if isDirty { confirmingDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Garder") { save() }.disabled(outdated)
                }
            }
            .interactiveDismissDisabled(isDirty)
            .alert("Abandonner les modifications ?", isPresented: $confirmingDiscard) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Le texte que tu viens de corriger ne sera pas enregistré.")
            }
            .alert("Annuler les corrections ?", isPresented: $confirmingUndo) {
                Button("Annuler les corrections", role: .destructive) {
                    reader.undoCorrections()
                    dismiss()
                }
                Button("Retour", role: .cancel) {}
            } message: {
                Text("La page revient à ce que l'OCR et OvisOCR2 avaient lu, sans rien relancer.")
            }
        }
    }

    private func save() {
        // Contrôle d'abord : le message « rien n'a été enregistré » doit rester vrai.
        if let original, !reader.ocrUnchanged(since: original, source: source) {
            outdated = true
            return
        }
        if let ovisOriginal, ovisDraft != ovisOriginal,
           !ovisDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reader.saveOvisCorrection(ovisDraft, source: source)
        }
        if let original {
            let changes = drafts.filter { original.lines.indices.contains($0.key) && original.lines[$0.key].text != $0.value }
            reader.correctOCRLines(changes, ifStill: original, source: source)
        }
        dismiss()
    }
}
