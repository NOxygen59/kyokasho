// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import OCRKit
import PDFKit
import ReaderCore
import SwiftUI

/// Lecteur « Atelier », pensé pour l'iPad en paysage :
/// page au centre, outils à gauche (une couleur par fonction), panneau d'étude à droite,
/// pellicule des pages en bas. Tout s'efface d'un tap au centre de la page.
struct ReaderScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var review: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var reader: ReaderController
    @StateObject private var lookup: LookupSession
    @State private var sheet: Sheet?
    @State private var side: Side? = nil
    @State private var studyTab: StudyPanel.Tab = .text

    enum Sheet: String, Identifiable {
        case search, ai, settings
        var id: String { rawValue }
    }

    enum Side: Equatable { case study, web }

    init(document: LibraryDocument, model: AppModel) {
        _reader = StateObject(wrappedValue: ReaderController(document: document, model: model))
        _lookup = StateObject(wrappedValue: LookupSession(dictionary: model.dictionary))
    }

    private var chromeVisible: Bool { reader.barsVisible || reader.isDrawing }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            HStack(spacing: Atelier.gap) {
                ZStack {
                    PDFViewHost(view: reader.pdfView)
                        .clipShape(RoundedRectangle(cornerRadius: side == nil ? 0 : Atelier.radius, style: .continuous))
                    LookupHighlightLayer(rects: reader.lookupHighlight)
                    if chromeVisible {
                        chrome.transition(.opacity)
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
                    if let error = reader.loadError {
                        Text(error).padding().atelierPanel()
                    }
                }
                .animation(.easeOut(duration: 0.18), value: chromeVisible)
                if let side, landscape || side == .web {
                    sidePanel(side)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(side == nil ? 0 : Atelier.gap)
            .overlay(alignment: .trailing) {
                // Portrait : le panneau d'étude passe par-dessus la page.
                if side == .study, !landscape {
                    sidePanel(.study).padding(Atelier.gap).transition(.move(edge: .trailing))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.88), value: side)
        }
        .background(Atelier.canvas.ignoresSafeArea())
        .statusBarHidden(!chromeVisible)
        .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
        .onAppear {
            reader.load()
            // En paysage, le panneau d'étude est ouvert d'office : il y a la place.
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            if scene?.interfaceOrientation.isLandscape == true { side = .study }
        }
        .onDisappear { reader.close() }
        .onChange(of: reader.lookupRequest) { request in
            if let request { lookup.start(request.text) } else { lookup.clear() }
        }
        .onChange(of: lookup.matchedLength) { reader.setLookupMatchLength($0) }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: reader.lookupRequest)
        .onChange(of: model.readerDefaults) { defaults in
            reader.update(settings: defaults.applying(reader.document.settingsOverride))
        }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .search: SearchSheet(reader: reader, close: { self.sheet = nil })
                case .ai: AIPageSheet(reader: reader, openWeb: { self.sheet = nil; side = .web })
                case .settings: DocumentSettingsSheet(reader: reader)
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

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Atelier.gap) {
                titleCapsule
                Spacer(minLength: 8)
                if reader.hasSelection {
                    HighlightMenu { reader.highlightSelection(color: $0) }
                        .transition(.scale.combined(with: .opacity))
                }
                actionsCapsule
            }
            .padding(.horizontal, Atelier.gap)
            .padding(.top, 8)
            HStack {
                toolRail
                Spacer()
            }
            .padding(.horizontal, Atelier.gap)
            .frame(maxHeight: .infinity)
            if !reader.isDrawing {
                PageFilmstrip(reader: reader)
                    .padding(.horizontal, Atelier.gap)
                    .padding(.bottom, 10)
            }
        }
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
            CapsuleButton(icon: "magnifyingglass", label: "Rechercher") { sheet = .search }
            CapsuleButton(icon: reader.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark", label: "Signet",
                          active: reader.isCurrentPageBookmarked) { reader.toggleBookmark() }
            Menu {
                Button { reader.rotateCurrentPage() } label: { Label("Pivoter la page", systemImage: "rotate.right") }
                Button { reader.toggleSplitCurrentPage() } label: {
                    Label(reader.isCurrentPageSplit ? "Ne plus couper la page" : "Couper la page en deux",
                          systemImage: "rectangle.split.2x1")
                }
                Button { reader.setShowOCRBoxes(!model.appSettings.showOCRBoxes) } label: {
                    Label(model.appSettings.showOCRBoxes ? "Masquer les zones OCR" : "Montrer les zones OCR",
                          systemImage: "rectangle.dashed")
                }
                Divider()
                Button { reader.setFirstPage(reader.currentSourcePage) } label: {
                    Label("Cette page est la page 1", systemImage: "1.circle")
                }
                if reader.document.firstPageIndex != 0 {
                    Button { reader.setFirstPage(0) } label: {
                        Label("Numéros du PDF (page 1 = début)", systemImage: "arrow.uturn.backward")
                    }
                }
                Divider()
                Button { sheet = .settings } label: { Label("Réglages du document", systemImage: "slider.horizontal.3") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40).foregroundStyle(Atelier.textPrimary)
            }
            Rectangle().fill(Atelier.hairline).frame(width: 1, height: 22).padding(.horizontal, 4)
            CapsuleButton(icon: "sidebar.trailing", label: "Panneau d'étude", active: side == .study,
                          tint: Atelier.Tint.japanese) {
                side = side == .study ? nil : .study
            }
        }
        .padding(4)
        .atelierPanel(radius: 26)
    }

    /// Outils, une couleur par fonction : lecture (turquoise), annotation (ambre),
    /// japonais (vermillon), IA (violet).
    private var toolRail: some View {
        VStack(spacing: 6) {
            ToolButton(icon: "hand.point.up.left", label: "Lire", tint: Atelier.Tint.read, active: !reader.isDrawing) {
                if reader.isDrawing { reader.setDrawing(false) }
            }
            ToolButton(icon: "pencil.tip", label: "Dessiner (Apple Pencil)", tint: Atelier.Tint.annotate,
                       active: reader.isDrawing) {
                reader.setDrawing(!reader.isDrawing)
            }
            Rectangle().fill(Atelier.hairline).frame(width: 26, height: 1).padding(.vertical, 2)
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
            ToolButton(icon: "character.ja", label: "Texte de la page", tint: Atelier.Tint.japanese,
                       active: side == .study && studyTab == .text) { openStudy(.text) }
            ToolButton(icon: "character.book.closed.ja", label: "Mots de la page", tint: Atelier.Tint.japanese,
                       active: side == .study && studyTab == .vocab) { openStudy(.vocab) }
            ToolButton(icon: "text.bubble", label: "Notes", tint: Atelier.Tint.annotate,
                       active: side == .study && studyTab == .notes) { openStudy(.notes) }
            Rectangle().fill(Atelier.hairline).frame(width: 26, height: 1).padding(.vertical, 2)
            ToolButton(icon: "sparkles", label: "Page vers IA", tint: Atelier.Tint.ai) { sheet = .ai }
            ToolButton(icon: "globe", label: "claude.ai à côté", tint: Atelier.Tint.ai, active: side == .web) {
                side = side == .web ? nil : .web
            }
        }
        .padding(6)
        .atelierPanel(radius: 16)
    }

    private func openStudy(_ tab: StudyPanel.Tab) {
        if side == .study && studyTab == tab {
            side = nil
        } else {
            studyTab = tab
            side = .study
        }
        if tab == .text, reader.ocrPage == nil, reader.ocrState != .running { reader.runOCR() }
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
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(0..<reader.document.pageCount, id: \.self) { page in
                        FilmstripCell(documentId: reader.document.id, fileURL: reader.fileURL, page: page,
                                      label: reader.document.pageLabel(page),
                                      current: page == reader.currentSourcePage)
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
    @EnvironmentObject private var model: AppModel
    let documentId: String
    let fileURL: URL
    let page: Int
    let label: String
    let current: Bool
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Atelier.surfaceHigh)
                if let image { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 4)) }
            }
            .frame(width: 46, height: 62)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(current ? Atelier.Tint.read : .clear, lineWidth: 2))
            Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(current ? Atelier.Tint.read : Atelier.textTertiary)
        }
        .onAppear(perform: load)
    }

    private func load() {
        if let cached = model.thumbnails.cached(documentId: documentId, page: page, width: 120) {
            image = cached
        } else {
            model.thumbnails.thumbnail(documentId: documentId, fileURL: fileURL, page: page, width: 120) { image = $0 }
        }
    }
}

/// Pastille d'état OCR à côté du numéro de page.
struct OCRStatusDot: View {
    @ObservedObject var reader: ReaderController

    var body: some View {
        switch reader.ocrState {
        case .running:
            HStack(spacing: 4) { ProgressView().controlSize(.mini).tint(Atelier.Tint.japanese); Text("lecture…") }
                .font(.system(size: 11))
        case .failed:
            Label("OCR", systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
        case .idle:
            if let page = reader.ocrPage {
                HStack(spacing: 4) {
                    Circle().fill(Atelier.Tint.japanese).frame(width: 6, height: 6)
                    Text(OCREngineID.displayName(page.engine)).font(.system(size: 11))
                }
            }
        }
    }
}

struct PDFViewHost: UIViewRepresentable {
    let view: PDFView
    func makeUIView(context: Context) -> PDFView { view }
    func updateUIView(_ uiView: PDFView, context: Context) {}
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
