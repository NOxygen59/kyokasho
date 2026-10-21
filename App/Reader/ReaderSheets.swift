// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PDFKit
import ReaderCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Recherche

struct SearchSheet: View {
    @ObservedObject var reader: ReaderController
    /// Fermeture explicite : `close()` avec une recherche active peut fermer aussi le lecteur.
    var close: () -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if reader.isSearching && reader.searchResults.isEmpty {
                    HStack { ProgressView(); Text("Recherche…").foregroundStyle(.secondary) }
                } else if !query.isEmpty && reader.searchResults.isEmpty && !reader.isSearching {
                    Text("Aucun résultat.").foregroundStyle(.secondary)
                }
                ForEach(reader.searchResults) { result in
                    Button {
                        reader.show(result)
                        close()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Page \(reader.document.pageLabel(result.sourcePage))").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(result.context).lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Mot ou phrase")
            .onSubmit(of: .search) { reader.search(query) }
            .onChange(of: query) { if $0.isEmpty { reader.search("") } }
            .navigationTitle(reader.searchResults.isEmpty ? "Rechercher" : "\(reader.searchResults.count) résultat(s)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { close() } } }
        }
    }
}

// MARK: - Signets et sommaire

struct BookmarksSheet: View {
    @ObservedObject var reader: ReaderController
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var renaming: Bookmark?
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Signets").tag(0)
                    Text("Sommaire").tag(1)
                    Text("Surlignages").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                switch tab {
                case 0: bookmarkList
                case 1: OutlineList(reader: reader, onSelect: { dismiss() })
                default: highlightList
                }
            }
            .navigationTitle("Navigation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .alert("Renommer le signet", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Titre", text: $newTitle)
                Button("Annuler", role: .cancel) {}
                Button("OK") { if let renaming { reader.rename(renaming, to: newTitle) } }
            }
        }
    }

    private var bookmarkList: some View {
        List {
            if reader.bookmarks.isEmpty {
                Text("Aucun signet. Touche l'icône signet dans la barre pour marquer une page.").foregroundStyle(.secondary)
            }
            ForEach(reader.bookmarks) { bookmark in
                Button {
                    reader.go(toSource: bookmark.pageIndex)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "bookmark.fill").foregroundStyle(Color.accentColor)
                        Text(bookmark.title)
                        Spacer()
                        Text("p. \(reader.document.pageLabel(bookmark.pageIndex))").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) { reader.delete(bookmark) } label: { Label("Supprimer", systemImage: "trash") }
                    Button { newTitle = bookmark.title; renaming = bookmark } label: { Label("Renommer", systemImage: "pencil") }
                }
            }
        }
    }

    private var highlightList: some View {
        List {
            if reader.allHighlights.isEmpty {
                Text("Aucun surlignage. Sélectionne du texte puis choisis une couleur en haut.").foregroundStyle(.secondary)
            }
            ForEach(reader.allHighlights) { h in
                Button {
                    reader.go(toSource: h.pageIndex)
                    dismiss()
                } label: {
                    HStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(h.color.uiColor)).frame(width: 4)
                        VStack(alignment: .leading) {
                            Text("Page \(reader.document.pageLabel(h.pageIndex))").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(h.text.isEmpty ? "(sans texte)" : h.text).lineLimit(3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) { reader.deleteHighlight(h) } label: { Label("Supprimer", systemImage: "trash") }
                }
            }
        }
    }
}

/// Table des matières intégrée au PDF, s'il en a une.
struct OutlineList: View {
    @ObservedObject var reader: ReaderController
    var onSelect: () -> Void

    struct Entry: Identifiable {
        let id: Int
        let title: String
        let depth: Int
        let destination: PDFDestination?
    }

    private var entries: [Entry] {
        guard let root = reader.pdf?.outlineRoot else { return [] }
        var result: [Entry] = []
        func walk(_ node: PDFOutline, depth: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                result.append(Entry(id: result.count, title: child.label ?? "—", depth: depth, destination: child.destination))
                if depth < 4 { walk(child, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return result
    }

    var body: some View {
        List {
            let items = entries
            if items.isEmpty {
                Text("Ce PDF n'a pas de sommaire intégré.").foregroundStyle(.secondary)
            }
            ForEach(items) { entry in
                Button {
                    if let destination = entry.destination { reader.pdfView.go(to: destination) }
                    onSelect()
                } label: {
                    Text(entry.title).padding(.leading, CGFloat(entry.depth) * 18)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Commentaires de page

struct CommentsSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var reader: ReaderController
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [PageComment] = []
    @State private var draft = ""
    @State private var editing: PageComment?
    @State private var showAll = false

    private var page: Int { reader.currentSourcePage }
    private var shown: [PageComment] { showAll ? comments : comments.filter { $0.pageIndex == page } }

    var body: some View {
        NavigationStack {
            List {
                Picker("Afficher", selection: $showAll) {
                    Text("Cette page").tag(false)
                    Text("Tout le document").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                if !showAll {
                    Section("Nouveau commentaire — page \(reader.document.pageLabel(page))") {
                        TextEditor(text: $draft).frame(minHeight: 90)
                        Button {
                            add()
                        } label: { Label(editing == nil ? "Ajouter" : "Enregistrer", systemImage: "checkmark") }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section(showAll ? "Tous les commentaires (\(comments.count))" : "Sur cette page") {
                    if shown.isEmpty { Text("Aucun commentaire.").foregroundStyle(.secondary) }
                    ForEach(shown) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            if showAll {
                                Button("Page \(reader.document.pageLabel(comment.pageIndex))") {
                                    reader.go(toSource: comment.pageIndex)
                                    dismiss()
                                }
                                .font(.caption.bold())
                            }
                            Text(comment.body)
                        }
                        .swipeActions {
                            Button(role: .destructive) { delete(comment) } label: { Label("Supprimer", systemImage: "trash") }
                            Button { editing = comment; draft = comment.body; showAll = false } label: { Label("Modifier", systemImage: "pencil") }
                        }
                    }
                }
            }
            .navigationTitle("Commentaires")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .confirmationAction) {
                    ShareLink(item: MarkdownFile(text: markdown, name: reader.document.title),
                              preview: SharePreview("\(reader.document.title).md")) {
                        Label("Exporter en Markdown", systemImage: "square.and.arrow.up")
                    }
                    Button("OK") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private var markdown: String {
        MarkdownExporter.export(title: reader.document.title, comments: comments, highlights: reader.allHighlights,
                                bookmarks: reader.bookmarks)
    }

    private func load() {
        comments = (try? model.database.comments(documentId: reader.document.id)) ?? []
    }

    private func add() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        var comment = editing ?? PageComment(documentId: reader.document.id, pageIndex: page, body: body)
        comment.body = body
        comment.updatedAt = Date()
        if let i = comments.firstIndex(where: { $0.id == comment.id }) { comments[i] = comment } else { comments.append(comment) }
        comments.sort { ($0.pageIndex, $0.createdAt) < ($1.pageIndex, $1.createdAt) }
        let saved = comment
        model.persist { try $0.save(saved) }
        draft = ""
        editing = nil
    }

    private func delete(_ comment: PageComment) {
        comments.removeAll { $0.id == comment.id }
        model.persist { try $0.deleteComment(id: comment.id) }
    }
}

/// Fichier Markdown partageable (nom de fichier propre, type .md).
struct MarkdownFile: Transferable {
    let text: String
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: UTType(filenameExtension: "md") ?? .plainText) { file in
            let safe = file.name.replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).md")
            try file.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

// MARK: - Page vers IA

struct AIPageSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var reader: ReaderController
    var openWeb: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var prompts: [AIPrompt] = []
    @State private var copied: String?
    @State private var editingPrompt: AIPrompt?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        Group {
                            if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView() }
                        }
                        .frame(width: 160, height: 210)
                        .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Page \(reader.document.pageLabel(reader.currentSourcePage))").font(.headline)
                            Button { copyImage() } label: { Label("Copier la page en image", systemImage: "photo.on.rectangle") }
                                .buttonStyle(.borderedProminent)
                            Text("Colle-la ensuite dans claude.ai (ou une autre IA), puis colle un prompt ci-dessous.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button { openWeb() } label: { Label("Ouvrir claude.ai à côté", systemImage: "sidebar.trailing") }
                        }
                    }
                }
                Section("Prompts") {
                    ForEach(prompts) { prompt in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(prompt.title).font(.subheadline.bold())
                                Text(prompt.body).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Button("Copier") { copy(prompt.body, label: prompt.title) }.buttonStyle(.bordered)
                            Button("Image + texte") { copyBoth(prompt) }.buttonStyle(.bordered)
                        }
                        .swipeActions {
                            Button(role: .destructive) { deletePrompt(prompt) } label: { Label("Supprimer", systemImage: "trash") }
                            Button { editingPrompt = prompt } label: { Label("Modifier", systemImage: "pencil") }
                        }
                    }
                    Button { editingPrompt = AIPrompt(title: "", body: "", position: prompts.count) } label: {
                        Label("Nouveau prompt", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Page vers IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .overlay(alignment: .bottom) {
                if let copied {
                    Text("Copié : \(copied)").padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule()).padding(.bottom, 20)
                }
            }
            .sheet(item: $editingPrompt) { prompt in
                PromptEditor(prompt: prompt) { saved in
                    if let i = prompts.firstIndex(where: { $0.id == saved.id }) { prompts[i] = saved } else { prompts.append(saved) }
                    model.persist { try $0.save(saved) }
                }
            }
            .onAppear {
                prompts = (try? model.database.aiPrompts()) ?? []
                DispatchQueue.main.async { image = reader.renderCurrentPage(maxWidth: 2048) }
            }
        }
    }

    private func flash(_ text: String) {
        copied = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if copied == text { copied = nil } }
    }

    private func copyImage() {
        guard let image else { return }
        UIPasteboard.general.image = image
        flash("image de la page")
    }

    private func copy(_ text: String, label: String) {
        UIPasteboard.general.string = text
        flash(label)
    }

    /// Deux éléments dans le presse-papiers : l'image puis le texte (les apps qui savent coller
    /// plusieurs éléments récupèrent les deux).
    private func copyBoth(_ prompt: AIPrompt) {
        guard let image, let png = image.pngData() else { return }
        UIPasteboard.general.setItems([[UTType.png.identifier: png], [UTType.utf8PlainText.identifier: prompt.body]])
        flash("image + « \(prompt.title) »")
    }

    private func deletePrompt(_ prompt: AIPrompt) {
        prompts.removeAll { $0.id == prompt.id }
        model.persist { try $0.deletePrompt(id: prompt.id) }
    }
}

struct PromptEditor: View {
    @State var prompt: AIPrompt
    var onSave: (AIPrompt) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titre", text: $prompt.title)
                TextEditor(text: $prompt.body).frame(minHeight: 160)
            }
            .navigationTitle("Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { onSave(prompt); dismiss() }
                        .disabled(prompt.title.isEmpty || prompt.body.isEmpty)
                }
            }
        }
    }
}

// MARK: - claude.ai à côté

struct WebPanel: View {
    var onClose: () -> Void
    @Environment(\.openURL) private var openURL
    static let url = URL(string: "https://claude.ai/new")!

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("claude.ai").font(.headline)
                Spacer()
                Button { openURL(Self.url) } label: { Label("Ouvrir dans Safari", systemImage: "safari") }
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Fermer")
            }
            .padding(12)
            .background(.ultraThinMaterial)
            WebView(url: Self.url)
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    /// Une seule vue web pour toute l'app : la session claude.ai et la page restent ouvertes
    /// quand on ferme et rouvre le panneau.
    @MainActor static let shared: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        // Agent Safari complet : certains sites refusent les vues web intégrées.
        view.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
        return view
    }()

    func makeUIView(context: Context) -> WKWebView {
        let view = Self.shared
        if view.url == nil { view.load(URLRequest(url: url)) }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
