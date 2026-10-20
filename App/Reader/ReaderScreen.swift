// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PDFKit
import ReaderCore
import SwiftUI

struct ReaderScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var reader: ReaderController
    @State private var sheet: Sheet?
    @State private var showWeb = false
    @State private var scrubbing: Double?

    enum Sheet: String, Identifiable {
        case search, bookmarks, comments, ai, settings
        var id: String { rawValue }
    }

    init(document: LibraryDocument, model: AppModel) {
        _reader = StateObject(wrappedValue: ReaderController(document: document, model: model))
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ZStack {
                    PDFViewHost(view: reader.pdfView)
                        .ignoresSafeArea(edges: .vertical)
                    if reader.barsVisible || reader.isDrawing {
                        VStack(spacing: 0) {
                            topBar
                            Spacer()
                            if !reader.isDrawing { bottomBar }
                        }
                        .transition(.opacity)
                    }
                    if let error = reader.loadError {
                        Text(error).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .clipped()
                .animation(.easeInOut(duration: 0.18), value: reader.barsVisible)
                if showWeb {
                    Divider()
                    WebPanel(onClose: { showWeb = false })
                        .frame(width: max(360, geo.size.width * 0.4))
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showWeb)
        }
        .statusBarHidden(!reader.barsVisible)
        .persistentSystemOverlays(reader.barsVisible ? .automatic : .hidden)
        .onAppear { reader.load() }
        .onDisappear { reader.close() }
        .onChange(of: model.readerDefaults) { defaults in
            reader.update(settings: defaults.applying(reader.document.settingsOverride))
        }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .search: SearchSheet(reader: reader, close: { self.sheet = nil })
                case .bookmarks: BookmarksSheet(reader: reader)
                case .comments: CommentsSheet(reader: reader)
                case .ai: AIPageSheet(reader: reader, openWeb: { self.sheet = nil; showWeb = true })
                case .settings: DocumentSettingsSheet(reader: reader)
                }
            }
            .environmentObject(model)
            .preferredColorScheme(model.colorScheme)
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

    // MARK: Barres

    private var topBar: some View {
        HStack(spacing: 18) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title3.weight(.semibold)) }
                .accessibilityLabel("Bibliothèque")
            Text(reader.document.title).font(.headline).lineLimit(1)
            Spacer(minLength: 8)
            if reader.hasSelection {
                HighlightMenu { reader.highlightSelection(color: $0) }
            }
            barButton("magnifyingglass", "Rechercher") { sheet = .search }
            barButton(reader.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark", "Signet") { reader.toggleBookmark() }
            barButton("list.bullet", "Signets et sommaire") { sheet = .bookmarks }
            barButton("text.bubble", "Commentaires") { sheet = .comments }
            Button { reader.setDrawing(!reader.isDrawing) } label: {
                Image(systemName: "pencil.tip.crop.circle")
                    .symbolVariant(reader.isDrawing ? .fill : .none)
                    .foregroundStyle(reader.isDrawing ? Color.accentColor : Color.primary)
            }
            .accessibilityLabel(reader.isDrawing ? "Terminer le dessin" : "Dessiner")
            barButton("sparkles", "Page vers IA") { sheet = .ai }
            barButton(showWeb ? "sidebar.trailing" : "globe", "claude.ai") { showWeb.toggle() }
            Menu {
                Button { reader.rotateCurrentPage() } label: { Label("Pivoter la page", systemImage: "rotate.right") }
                Button { reader.toggleSplitCurrentPage() } label: {
                    Label(reader.isCurrentPageSplit ? "Ne plus couper la page" : "Couper la page en deux",
                          systemImage: "rectangle.split.2x1")
                }
                Divider()
                Button { sheet = .settings } label: { Label("Réglages du document", systemImage: "slider.horizontal.3") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .font(.title3)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func barButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }.accessibilityLabel(label)
    }

    private var bottomBar: some View {
        let count = max(reader.presented.count, 1)
        let shown = scrubbing.map { Int($0) } ?? reader.currentIndex
        let source = scrubbing == nil ? reader.currentSourcePage
            : (reader.presented.indices.contains(shown) ? reader.presented[shown].source : shown)
        return VStack(spacing: 8) {
            if scrubbing != nil {
                ScrubPreview(documentId: reader.document.id, fileURL: reader.fileURL, page: source)
            }
            HStack(spacing: 14) {
                Text("\(source + 1) / \(reader.document.pageCount)")
                    .font(.footnote.monospacedDigit()).frame(minWidth: 84, alignment: .leading)
                if count > 1 {
                    Slider(value: Binding(get: { scrubbing ?? Double(reader.currentIndex) },
                                          set: { scrubbing = $0 }),
                           in: 0...Double(count - 1), step: 1) { editing in
                        if !editing, let value = scrubbing {
                            reader.go(toPresented: Int(value))
                            scrubbing = nil
                        }
                    }
                    // Lecture droite → gauche : la barre se lit aussi de droite à gauche.
                    .environment(\.layoutDirection, reader.settings.direction == .rightToLeft ? .rightToLeft : .leftToRight)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
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
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button { onPick(color) } label: {
                    Circle().fill(Color(color.uiColor)).frame(width: 24, height: 24)
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                }
                .accessibilityLabel("Surligner en \(color.frenchName)")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}

struct ScrubPreview: View {
    @EnvironmentObject private var model: AppModel
    let documentId: String
    let fileURL: URL
    let page: Int
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.15))
            if let image { Image(uiImage: image).resizable().scaledToFit().padding(4) }
        }
        .frame(width: 150, height: 200)
        .shadow(radius: 8)
        .onAppear(perform: load)
        .onChange(of: page) { _ in load() }
    }

    private func load() {
        if let cached = model.thumbnails.cached(documentId: documentId, page: page, width: 240) {
            image = cached
        } else {
            model.thumbnails.thumbnail(documentId: documentId, fileURL: fileURL, page: page, width: 240) { image = $0 }
        }
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
