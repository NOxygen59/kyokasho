// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import GLMOCRKit
import ONNXOCRKit
import ReaderCore
import DictionaryKit
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
                if reader.shownSources.count > 1 {
                    // Double page : une pilule par page affichée, le panneau travaille sur celle choisie.
                    HStack(spacing: 6) {
                        ForEach(reader.shownSources, id: \.self) { source in
                            let on = source == reader.focusSource
                            Button { reader.focus(source) } label: {
                                Text("p. \(reader.document.pageLabel(source))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .foregroundStyle(on ? Color.black.opacity(0.85) : Atelier.textSecondary)
                                    .background(Capsule().fill(on ? Atelier.Tint.japanese : Atelier.surfaceHigh))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Travailler sur la page \(reader.document.pageLabel(source))")
                        }
                    }
                } else {
                    AtelierLabel("Étude · page \(reader.document.pageLabel(reader.focusSource))", tint: Atelier.textSecondary)
                }
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
    /// Texte mis en forme (titres, paragraphes, tableaux) ou tel que lu, ligne par ligne.
    @AppStorage("study.formattedText") private var formatted = true
    /// Furigana (dictionnaire Yomitan) sur le texte extrait ; un appui ouvre le dictionnaire.
    @AppStorage("study.furigana") private var furigana = false
    /// Moteur de mise en page du mode « Mis en forme » (géométrie seule, PP-DocLayout, DocLayout-YOLO).
    @AppStorage("study.layoutEngine") private var layoutEngineRaw = LayoutDetector.Engine.geometry.rawValue
    @State private var regions: [OCRLayout.Region] = []
    @State private var layoutError: String?
    @State private var lookup: LookupSession?
    @State private var showLookup = false
    @State private var translating = false
    @State private var translateError: String?
    @State private var showCompare = false
    @State private var query = ""
    @State private var matches: [PageTextSearch.Match] = []
    @State private var editingLine: Int?
    @State private var showVerify = false
    @State private var lineDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if reader.ocrPage != nil { PageSearchField(query: $query) }
                engineRow
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
                    if furigana {
                        FuriganaTextView(page: page, formatted: formatted, regions: regions) { text in
                            let session = lookup ?? LookupSession(dictionary: model.dictionary)
                            lookup = session
                            session.start(text)
                            showLookup = true
                        }
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
                                        Button { lineDraft = line.text; editingLine = index } label: {
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
        .sheet(isPresented: $showLookup, onDismiss: { lookup?.clear() }) {
            // Fenêtre compacte du dictionnaire (mot touché dans le texte à furigana).
            if let lookup {
                LookupPopup(session: lookup, added: model.review.keys, onAddCard: { term in
                    model.review.add(term, sentence: reader.ocrPage?.lines.first { $0.text.contains(term.matchedText) }?.text,
                                     source: "\(reader.document.title) · p. \(reader.document.pageLabel(reader.focusSource))",
                                     image: nil, documentId: reader.document.id, page: reader.focusSource,
                                     dictionary: model.dictionary)
                }, close: { showLookup = false })
                .environmentObject(model.dictionary)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
            }
        }
        .alert("Corriger la ligne", isPresented: Binding(get: { editingLine != nil }, set: { if !$0 { editingLine = nil } })) {
            TextField("Texte de la ligne", text: $lineDraft)
            Button("Annuler", role: .cancel) { editingLine = nil }
            Button("Garder") {
                if let editingLine { reader.correctOCRLine(editingLine, text: lineDraft) }
                editingLine = nil
            }
        } message: {
            Text("Ta correction est gardée ; la relecture automatique n'y touchera plus.")
        }
        .sheet(isPresented: $showVerify) { VerifySheet(reader: reader).preferredColorScheme(.dark) }
        .sheet(isPresented: $showCompare) { CompareEnginesView(reader: reader).environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review) }
    }

    /// Zones de mise en page de la page de travail (modèle choisi, gardées en mémoire par page).
    private func loadRegions() async {
        layoutError = nil
        let engine = LayoutDetector.Engine(rawValue: layoutEngineRaw) ?? .geometry
        guard formatted, reader.ocrPage != nil, engine != .geometry else { regions = []; return }
        guard engine.isAvailable() else {
            regions = []
            layoutError = "\(engine.title) n'est pas téléchargé (Réglages → Modèles) : mise en page par géométrie."
            return
        }
        let key = "\(reader.document.id)-\(reader.focusSource)-\(engine.rawValue)"
        if let cached = LayoutRegionsCache.shared.get(key) { regions = cached; return }
        // Zones de l'ancienne page / de l'autre moteur : retirées tout de suite (géométrie en attendant).
        regions = []
        let url = reader.fileURL, page = reader.focusSource
        let work = Task.detached(priority: .userInitiated) {
            Result { try LayoutDetector.regions(.pdfPage(url: url, index: page), engine: engine) }
        }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let found):
            LayoutRegionsCache.shared.set(found, for: key)
            regions = found
        case .failure(let error):
            regions = []
            layoutError = "Mise en page : \(error.localizedDescription) (géométrie utilisée)."
        }
    }

    private var engineRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach([OCREngineID.pdfText, OCREngineID.vision] + OCREngineMenu.extra, id: \.self) { id in
                    Button { reader.runOCR(engine: id) } label: {
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
                        Label(reader.shownSources.count > 1 ? "Vérifier la double page (OvisOCR2)" : "Vérifier la page (OvisOCR2)",
                              systemImage: "checkmark.seal")
                    }
                }
            } label: {
                // Icône seule (le nom s'écrivait en colonne dans le panneau étroit) ; le nom est dans le menu.
                HStack(spacing: 4) {
                    Image(systemName: OCREngineMenu.icon(reader.ocrPage?.engine))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Atelier.surfaceHigh, in: Capsule())
            }
            Picker("Affichage", selection: $formatted) {
                Text("Mis en forme").tag(true)
                Text("Brut").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 190)
            if formatted {
                Menu {
                    LayoutEnginePicker(selection: $layoutEngineRaw)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.3.group")
                        Text(LayoutEngineMenu.engine(layoutEngineRaw).shortTitle)
                            .strikethrough(!LayoutEngineMenu.engine(layoutEngineRaw).isAvailable())
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Atelier.surfaceHigh, in: Capsule())
                }
                .accessibilityLabel("Moteur de mise en page : \(LayoutEngineMenu.engine(layoutEngineRaw).title)")
            }
            Toggle(isOn: $furigana) { Text("ふりがな").font(.system(size: 13, weight: .semibold)) }
                .toggleStyle(.button)
                .accessibilityLabel("Furigana sur le texte extrait")
            Spacer()
            Button {
                guard let page = reader.ocrPage else { return }
                UIPasteboard.general.string = formatted ? OCRLayout.markdown(page) : page.text
            } label: { Image(systemName: "doc.on.doc") }
                .disabled(reader.ocrPage == nil)
                .accessibilityLabel(formatted ? "Copier en Markdown" : "Copier le texte")
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
                Text(count > 0 ? "\(count) caractère\(count > 1 ? "s" : "") douteux" : "\(lines.count) ligne\(lines.count > 1 ? "s" : "") peu sûre\(lines.count > 1 ? "s" : "")")
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

/// Moteur de mise en page : nom court pour le panneau, liste complète (modèles absents grisés).
enum LayoutEngineMenu {
    static func engine(_ raw: String) -> LayoutDetector.Engine { LayoutDetector.Engine(rawValue: raw) ?? .geometry }
}

extension LayoutDetector.Engine {
    var shortTitle: String {
        switch self {
        case .geometry: return "Géo"
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
                Text(engine.isAvailable() ? engine.title : "\(engine.title) — à télécharger (Modèles)")
                    .tag(engine.rawValue)
                    .disabled(!engine.isAvailable())
            }
        }
    }
}

// MARK: - Vocabulaire (V3)

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
                    Text(text).font(.system(size: level == 1 ? 22 : 18, weight: .bold))
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
                                        .overlay(Rectangle().strokeBorder(Atelier.hairline, lineWidth: 1))
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

struct StudyVocabTab: View {
    @EnvironmentObject private var dictionary: DictionaryModel
    @EnvironmentObject private var review: ReviewModel
    @ObservedObject var reader: ReaderController
    @StateObject private var popup = PopupHolder()
    @State private var words: [Word] = []
    @State private var loading = false

    struct Word: Identifiable, Equatable {
        let id: String
        let expression: String
        let reading: String
        let gloss: String
        var count: Int
        let term: TermResult
    }

    /// Une seule session de popup par onglet (créée au premier usage).
    @MainActor final class PopupHolder: ObservableObject {
        var session: LookupSession?
        @Published var shown = false
    }

    /// Kanji de la page, calculés une fois par résultat OCR (dans `reload`), pas à chaque affichage.
    @State private var kanji: [Character] = []

    private static func kanji(in text: String) -> [Character] {
        var seen = Set<Character>()
        return text.filter { c in
            guard let v = c.unicodeScalars.first?.value, (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) else { return false }
            return seen.insert(c).inserted
        }.map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if reader.ocrPage?.lines.isEmpty ?? true {
                    Text("Lis la page (onglet Texte) pour voir son vocabulaire.").foregroundStyle(Atelier.textSecondary)
                } else if !dictionary.hasTermDictionaries {
                    VStack(alignment: .leading, spacing: 6) {
                        AtelierLabel("Aucun dictionnaire", tint: Atelier.textTertiary)
                        Text("Importe un dictionnaire Yomitan dans Réglages → Dictionnaires pour voir les mots de la page.")
                            .font(.footnote).foregroundStyle(Atelier.textSecondary)
                    }
                    .padding(12)
                    .background(Atelier.surfaceHigh.opacity(0.6), in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
                } else {
                    HStack {
                        AtelierLabel("Mots de la page · \(words.count)", tint: Atelier.Tint.japanese)
                        if loading { ProgressView().controlSize(.small).tint(Atelier.Tint.japanese) }
                    }
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(words) { word in
                            Button { open(word.expression) } label: { row(word) }.buttonStyle(.plain)
                        }
                    }
                }
                if !kanji.isEmpty {
                    AtelierLabel("Kanji de la page · \(kanji.count)", tint: Atelier.Tint.japanese)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(kanji, id: \.self) { k in
                            Button { openKanji(String(k)) } label: {
                                Text(String(k))
                                    .font(.custom("HiraMinProN-W6", size: 26))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .foregroundStyle(Atelier.textPrimary)
                                    .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(PressScale())
                        }
                    }
                }
            }
        }
        // Clé légère (pas tout le texte recollé à chaque affichage).
        .task(id: reader.ocrPage.map { "\($0.engine)#\($0.lines.count)#\($0.lines.first?.text ?? "")#\($0.lines.last?.text ?? "")" }) { await reload() }
        .sheet(isPresented: $popup.shown) {
            if let session = popup.session {
                LookupPopup(session: session, added: review.keys, onAddCard: { add($0) }, close: { popup.shown = false })
                    .environmentObject(dictionary)
                    .presentationDetents([.medium, .large])
                    .preferredColorScheme(.dark)
            }
        }
    }

    private func row(_ word: Word) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                if word.reading != word.expression && !word.reading.isEmpty {
                    Text(word.reading).font(.custom("HiraginoSans-W3", size: 11)).foregroundStyle(Atelier.textTertiary)
                }
                Text(word.expression).font(.custom("HiraginoSans-W6", size: 18)).foregroundStyle(Atelier.textPrimary)
            }
            .frame(minWidth: 70, alignment: .leading)
            Text(word.gloss).font(.footnote).foregroundStyle(Atelier.textSecondary).lineLimit(2)
            Spacer(minLength: 0)
            if word.count > 1 { Text("×\(word.count)").font(Atelier.mono).foregroundStyle(Atelier.textTertiary) }
            if review.keys.contains(word.id) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Atelier.Tint.read)
                    .frame(width: 30, height: 30).accessibilityLabel("Déjà dans tes cartes")
            } else {
                Button { _ = add(word.term) } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(Atelier.Tint.japanese)
                        .frame(width: 30, height: 30)
                        .background(Atelier.surfaceHigh, in: Circle())
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Créer une carte")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Atelier.surfaceHigh.opacity(0.7), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Carte depuis l'onglet Mots : phrase = ligne OCR qui contient le mot (pas d'image : pas de position précise).
    private func add(_ term: TermResult) -> String? {
        let sentence = reader.ocrPage?.lines.first { $0.text.contains(term.matchedText) }?.text
        return review.add(term, sentence: sentence,
                          source: "\(reader.document.title) · p. \(reader.document.pageLabel(reader.focusSource))",
                          image: nil, documentId: reader.document.id, page: reader.focusSource,
                          dictionary: dictionary)
    }

    private func session() -> LookupSession {
        if let s = popup.session { return s }
        let s = LookupSession(dictionary: dictionary)
        popup.session = s
        return s
    }

    private func open(_ text: String) {
        session().start(text)
        popup.shown = true
    }

    private func openKanji(_ c: String) {
        let s = session()
        s.clear()
        s.pushKanji(c)
        popup.shown = true
    }

    private func reload() async {
        let text = reader.ocrPage?.text ?? ""
        kanji = Self.kanji(in: text)
        guard !text.isEmpty, dictionary.hasTermDictionaries else { words = []; return }
        loading = true
        defer { loading = false }
        let segments = await dictionary.segment(text)
        guard !Task.isCancelled else { return }
        var order: [String] = []
        var map: [String: Word] = [:]
        for seg in segments {
            guard let term = seg.term, term.expression.contains(where: { !$0.isWhitespace && !$0.isPunctuation }) else { continue }
            // Les particules seules (une kana) n'apprennent rien : on les saute.
            if term.expression.count == 1, term.expression.unicodeScalars.allSatisfy({ (0x3040...0x30FF).contains($0.value) }) { continue }
            if map[term.id] != nil { map[term.id]!.count += 1; continue }
            order.append(term.id)
            map[term.id] = Word(id: term.id, expression: term.expression, reading: term.reading,
                                gloss: GlossaryText.plain(term.definitions.first?.glossaryJSON ?? ""), count: 1, term: term)
        }
        words = order.compactMap { map[$0] }
        review.loadKeys(order)
    }
}

// MARK: - Notes de la page

struct StudyNotesTab: View {
    @ObservedObject var reader: ReaderController
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var page: Int { reader.focusSource }

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
                Button { reader.newNote() } label: { Label("Flottante", systemImage: "note.text.badge.plus") }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Atelier.Tint.annotate)
                Spacer()
                ShareLink(item: MarkdownFile(name: reader.document.title) { [reader] in
                              MarkdownExporter.export(title: reader.document.title, comments: reader.notes,
                                                      highlights: reader.allHighlights, bookmarks: reader.bookmarks)
                          },
                          preview: SharePreview("\(reader.document.title).md")) {
                    Label("Markdown", systemImage: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Atelier.Tint.annotate)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let here = reader.notes.filter { $0.pageIndex == page }
                    let others = reader.notes.filter { $0.pageIndex != page }
                    if here.isEmpty { Text("Aucune note sur cette page.").font(.footnote).foregroundStyle(Atelier.textTertiary) }
                    ForEach(here) { note($0) }
                    if !others.isEmpty {
                        AtelierLabel("Autres pages").padding(.top, 6)
                        ForEach(others) { note($0, showPage: true) }
                    }
                }
            }
        }
    }

    /// Toucher : ouvrir la note dans la fenêtre flottante ; ＊ : aller au mot ancré.
    private func note(_ comment: PageComment, showPage: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Atelier.Tint.annotate).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if showPage { Text("p. \(reader.document.pageLabel(comment.pageIndex))").font(Atelier.mono).foregroundStyle(Atelier.textTertiary) }
                    if comment.drawing != nil { Image(systemName: "scribble").font(.caption).foregroundStyle(Atelier.textTertiary) }
                    if comment.anchorRect != nil {
                        Button { reader.goToAnchor(comment) } label: {
                            Text("＊ \(comment.anchorText ?? "ancre")").font(.caption.weight(.semibold)).foregroundStyle(Atelier.Tint.annotate)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(comment.body.isEmpty ? "(note sans texte)" : comment.body)
                    .foregroundStyle(comment.body.isEmpty ? Atelier.textTertiary : Atelier.textPrimary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { reader.openNote = comment }
        .contextMenu {
            Button { reader.openNote = comment } label: { Label("Ouvrir", systemImage: "macwindow") }
            if showPage { Button { reader.go(toSource: comment.pageIndex) } label: { Label("Aller à la page", systemImage: "arrow.right") } }
            Button(role: .destructive) { reader.deleteNote(comment) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func add() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        reader.saveNote(PageComment(documentId: reader.document.id, pageIndex: page, body: body))
        draft = ""
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
}
