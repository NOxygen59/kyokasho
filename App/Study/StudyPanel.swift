// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import ReaderCore
import SwiftUI

/// Panneau d'étude, à droite du lecteur : tout ce qui sert à **comprendre** la page.
/// Texte (OCR) + traduction, vocabulaire de la page (V3), notes, signets.
struct StudyPanel: View {
    enum Tab: Hashable { case text, vocab, notes, marks }

    @EnvironmentObject private var model: AppModel
    @ObservedObject var reader: ReaderController
    @Binding var tab: Tab
    var openSearch: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AtelierLabel("Étude · page \(reader.currentSourcePage + 1)", tint: Atelier.textSecondary)
                Spacer()
                Button(action: close) {
                    Image(systemName: "sidebar.trailing").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Atelier.textSecondary)
                }
                .accessibilityLabel("Fermer le panneau d'étude")
            }
            PillTabs(items: [(Tab.text, "character.ja", "Texte"), (.vocab, "character.book.closed.ja", "Mots"),
                             (.notes, "text.bubble", "Notes"), (.marks, "bookmark", "Repères")],
                     selection: $tab, tint: tint)
            Group {
                switch tab {
                case .text: StudyTextTab(reader: reader)
                case .vocab: StudyVocabTab(reader: reader)
                case .notes: StudyNotesTab(reader: reader)
                case .marks: StudyMarksTab(reader: reader, openSearch: openSearch)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .frame(width: Atelier.panelWidth)
        .frame(maxHeight: .infinity)
        .atelierPanel()
    }

    private var tint: Color {
        switch tab {
        case .text, .vocab: return Atelier.Tint.japanese
        case .notes: return Atelier.Tint.annotate
        case .marks: return Atelier.Tint.read
        }
    }
}

// MARK: - Texte + traduction

struct StudyTextTab: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var reader: ReaderController
    @ObservedObject private var deepl = DeepLService.shared
    @State private var translation: String?
    @State private var translating = false
    @State private var translateError: String?
    @State private var showCompare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                engineRow
                switch (reader.ocrPage, reader.ocrState) {
                case (_, .running):
                    HStack(spacing: 10) { ProgressView().tint(Atelier.Tint.japanese); Text("Lecture de la page…") }
                        .foregroundStyle(Atelier.textSecondary)
                case (_, .failed(let message)):
                    Text(message).foregroundStyle(Atelier.textSecondary)
                    Button("Lire avec Apple Vision") { reader.runOCR(engine: OCREngineID.vision) }
                        .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.japanese))
                case (let page?, _):
                    Text(page.text)
                        .font(Atelier.jp)
                        .lineSpacing(7)
                        .foregroundStyle(Atelier.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    translationBlock(for: page.text)
                default:
                    Text("La page n'a pas encore été lue.").foregroundStyle(Atelier.textSecondary)
                    Button { reader.runOCR() } label: { Label("Lire la page", systemImage: "text.viewfinder") }
                        .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.japanese))
                }
                documentOCRRow
            }
        }
        .onChange(of: reader.currentSourcePage) { _ in
            translation = nil
            translateError = nil
        }
        .sheet(isPresented: $showCompare) { CompareEnginesView(reader: reader).environmentObject(model) }
    }

    private var engineRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Texte du PDF") { reader.runOCR(engine: OCREngineID.pdfText) }
                Button("Apple Vision") { reader.runOCR(engine: OCREngineID.vision) }
                Divider()
                Button("Relancer") { reader.runOCR(engine: reader.ocrPage?.engine, force: true) }
                Button("Comparer les moteurs") { showCompare = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                    Text(reader.ocrPage.map { OCREngineID.displayName($0.engine) } ?? "Moteur")
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Atelier.surfaceHigh, in: Capsule())
            }
            Spacer()
            Button { UIPasteboard.general.string = reader.ocrPage?.text } label: { Image(systemName: "doc.on.doc") }
                .disabled(reader.ocrPage == nil)
                .accessibilityLabel("Copier le texte")
        }
        .foregroundStyle(Atelier.textPrimary)
    }

    @ViewBuilder
    private func translationBlock(for text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AtelierLabel("Traduction", tint: Atelier.Tint.ai)
            if let translation {
                Text(translation)
                    .font(.system(size: 15))
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
                        HStack { if translating { ProgressView().tint(.black) }; Text("Traduire en français") }
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
                        .font(.system(size: 14, weight: .semibold))
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

// MARK: - Vocabulaire (V3)

struct StudyVocabTab: View {
    @ObservedObject var reader: ReaderController

    /// Kanji de la page (aperçu en attendant le dictionnaire de la V3).
    private var kanji: [Character] {
        guard let text = reader.ocrPage?.text else { return [] }
        var seen = Set<Character>()
        return text.filter { c in
            guard let v = c.unicodeScalars.first?.value, (0x4E00...0x9FFF).contains(v) else { return false }
            return seen.insert(c).inserted
        }.map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if kanji.isEmpty {
                    Text("Lis la page (onglet Texte) pour voir ses kanji.").foregroundStyle(Atelier.textSecondary)
                } else {
                    AtelierLabel("Kanji de la page · \(kanji.count)", tint: Atelier.Tint.japanese)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(kanji, id: \.self) { k in
                            Text(String(k))
                                .font(.custom("HiraMinProN-W6", size: 26))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(Atelier.textPrimary)
                                .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .textSelection(.enabled)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    AtelierLabel("Bientôt (V3)", tint: Atelier.textTertiary)
                    Text("Touche un mot sur la page : lecture, sens, accent, fréquence, kanji, et création de carte de révision — façon Yomitan.")
                        .font(.footnote).foregroundStyle(Atelier.textSecondary)
                }
                .padding(12)
                .background(Atelier.surfaceHigh.opacity(0.6), in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
            }
        }
    }
}

// MARK: - Notes de la page

struct StudyNotesTab: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var reader: ReaderController
    @State private var comments: [PageComment] = []
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var page: Int { reader.currentSourcePage }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Note sur cette page…").foregroundStyle(Atelier.textTertiary).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $draft)
                    .focused($focused)
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
                Spacer()
                ShareLink(item: MarkdownFile(text: MarkdownExporter.export(title: reader.document.title, comments: comments,
                                                                           highlights: reader.allHighlights, bookmarks: reader.bookmarks),
                                             name: reader.document.title),
                          preview: SharePreview("\(reader.document.title).md")) {
                    Label("Markdown", systemImage: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Atelier.Tint.annotate)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let here = comments.filter { $0.pageIndex == page }
                    let others = comments.filter { $0.pageIndex != page }
                    if here.isEmpty { Text("Aucune note sur cette page.").font(.footnote).foregroundStyle(Atelier.textTertiary) }
                    ForEach(here) { note($0) }
                    if !others.isEmpty {
                        AtelierLabel("Autres pages").padding(.top, 6)
                        ForEach(others) { comment in
                            Button { reader.go(toSource: comment.pageIndex) } label: { note(comment, showPage: true) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func note(_ comment: PageComment, showPage: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Atelier.Tint.annotate).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                if showPage { Text("p. \(comment.pageIndex + 1)").font(Atelier.mono).foregroundStyle(Atelier.textTertiary) }
                Text(comment.body).foregroundStyle(Atelier.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contextMenu {
            Button(role: .destructive) { delete(comment) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func load() {
        comments = (try? model.database.comments(documentId: reader.document.id)) ?? []
    }

    private func add() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let comment = PageComment(documentId: reader.document.id, pageIndex: page, body: body)
        comments.append(comment)
        model.persist { try $0.save(comment) }
        draft = ""
        focused = false
    }

    private func delete(_ comment: PageComment) {
        comments.removeAll { $0.id == comment.id }
        model.persist { try $0.deleteComment(id: comment.id) }
    }
}

// MARK: - Repères : signets, sommaire, surlignages

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
                AtelierLabel("Signets · \(reader.bookmarks.count)", tint: Atelier.Tint.read)
                if reader.bookmarks.isEmpty {
                    Text("Touche ★ en haut pour marquer une page.").font(.footnote).foregroundStyle(Atelier.textTertiary)
                }
                ForEach(reader.bookmarks) { b in
                    row(icon: "bookmark.fill", tint: Atelier.Tint.read, title: b.title, page: b.pageIndex)
                }
                AtelierLabel("Surlignages · \(reader.allHighlights.count)", tint: Atelier.Tint.annotate)
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
                Text("\(page + 1)").font(Atelier.mono).foregroundStyle(Atelier.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
