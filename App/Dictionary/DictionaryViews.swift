// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Bibliothèque du dictionnaire

/// La même bibliothèque de mots depuis l'accueil et le panneau du lecteur.
struct DictionarySearchView: View {
    private enum Shelf: String, CaseIterable {
        case words = "Mots", kanji = "Kanji", saved = "Enregistrés"
    }

    @EnvironmentObject private var dictionaryModel: DictionaryModel
    @EnvironmentObject private var review: ReviewModel
    @ObservedObject private var lexicon = DomainLexicon.shared
    @StateObject private var session: LookupSession
    @State private var query = ""
    @State private var shelf: Shelf = .words
    @State private var suggestions: [DictionaryWord] = []
    @State private var searching = false
    @State private var showManager = false
    @State private var showLexicon = false
    @FocusState private var focused: Bool
    var onAddCard: ((TermResult) -> String?)?
    var added: Set<String> = []
    var compact = false

    init(dictionary: DictionaryModel, added: Set<String> = [], compact: Bool = false,
         onAddCard: ((TermResult) -> String?)? = nil) {
        self.added = added
        self.compact = compact
        _session = StateObject(wrappedValue: LookupSession(dictionary: dictionary))
        self.onAddCard = onAddCard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dictionnaire japonais").font(Atelier.display(27)).foregroundStyle(Atelier.textPrimary)
                    Text("Retrouve un mot, explore ses kanji et garde ceux que tu veux revoir.")
                        .font(.subheadline).foregroundStyle(Atelier.textSecondary)
                }
            }
            searchField
            HStack(spacing: 7) {
                ForEach(Shelf.allCases, id: \.self) { item in
                    Button {
                        shelf = item
                        session.clear()
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: compact ? 12 : 14, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(shelf == item ? Atelier.onAccentInk.opacity(0.85) : Atelier.textSecondary)
                            .background(shelf == item ? Atelier.Tint.japanese : Atelier.surfaceHigh,
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if session.current != nil {
                LookupPopup(session: session, added: added.union(review.keys), onAddCard: onAddCard,
                            close: { session.clear() })
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch shelf {
                        case .words: wordShelf
                        case .kanji: kanjiShelf
                        case .saved: savedShelf
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .atelierPanel()
            }
        }
        .padding(compact ? 0 : Atelier.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if compact { Atelier.surface } else { GridBackground() }
        }
        .task(id: query + "|" + dictionaryModel.dictionaries.map { "\($0.id ?? 0):\($0.enabled)" }.joined()) {
            let prefix = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty else { suggestions = []; searching = false; return }
            searching = true
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            let found = await dictionaryModel.words(startingWith: prefix)
            guard !Task.isCancelled else { return }
            suggestions = found
            searching = false
        }
        .onChange(of: query) { _ in session.clear() }
        .task(id: session.currentTerms.map(\.id).joined(separator: ";")) {
            review.loadKeys(session.currentTerms.map(\.id))
        }
        .sheet(isPresented: $showManager) {
            NavigationStack {
                DictionaryManagerView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { showManager = false }
                    } }
            }
            .environmentObject(dictionaryModel)
            .preferredColorScheme(AppStyle.current.colorScheme)
        }
        .sheet(isPresented: $showLexicon) {
            NavigationStack {
                DomainLexiconView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { showLexicon = false }
                    } }
            }
            .preferredColorScheme(AppStyle.current.colorScheme)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Atelier.Tint.japanese)
            TextField(shelf == .kanji ? "Chercher un kanji" : "Mot ou lecture en japonais", text: $query)
                .focused($focused)
                .font(.custom("HiraginoSans-W3", size: compact ? 15 : 19))
                .submitLabel(.search)
                .onSubmit { openQuery() }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if searching { ProgressView().controlSize(.small).tint(Atelier.Tint.japanese) }
            if !query.isEmpty {
                Button { query = ""; focused = false } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(Atelier.textTertiary)
            }
            Button { focused = false; showManager = true } label: {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(Atelier.textSecondary).frame(width: 30, height: 30)
            }
            .accessibilityLabel("Gérer les dictionnaires")
        }
        .padding(compact ? 11 : 14)
        .atelierPanel(radius: 16)
    }

    private var wordShelf: some View {
        Group {
            if !dictionaryModel.hasTermDictionaries {
                emptyState("Aucun dictionnaire de mots",
                           "Importe un dictionnaire Yomitan dans Réglages → Japonais → Dictionnaires.")
            } else if !query.isEmpty {
                AtelierLabel("Mots trouvés · \(suggestions.count)", tint: Atelier.Tint.japanese)
                if suggestions.isEmpty && !searching {
                    emptyState("Aucun mot à ce début", "Essaie la forme de base ou une lecture en kana.")
                }
                ForEach(suggestions) { word in
                    wordRow(word.expression, reading: word.reading, gloss: word.gloss)
                }
            } else {
                if !dictionaryModel.notebook.saved.filter({ $0.kind == .word }).isEmpty {
                    AtelierLabel("Mots enregistrés", tint: Atelier.Tint.japanese)
                    ForEach(dictionaryModel.notebook.saved.filter { $0.kind == .word }.prefix(8)) { entry in
                        wordRow(entry.expression, reading: entry.reading)
                    }
                }
                AtelierLabel("Récemment consultés", tint: Atelier.Tint.japanese)
                let recent = dictionaryModel.notebook.recent.filter { $0.kind == .word }
                if recent.isEmpty {
                    Text("Cherche un mot pour commencer. Les dernières recherches apparaîtront ici.")
                        .font(.subheadline).foregroundStyle(Atelier.textSecondary)
                } else {
                    ForEach(recent.prefix(25)) { entry in
                        wordRow(entry.expression, reading: entry.reading)
                    }
                }
            }
        }
    }

    private var kanjiShelf: some View {
        Group {
            let characters = Array(Set(query.filter { $0.unicodeScalars.contains {
                (0x3400...0x9FFF).contains($0.value)
            } })).sorted()
            if !characters.isEmpty {
                AtelierLabel("Kanji saisis", tint: Atelier.Tint.japanese)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58))], spacing: 8) {
                    ForEach(characters, id: \.self) { character in
                        Button { openKanji(String(character)) } label: {
                            Text(String(character)).font(.custom("HiraMinProN-W6", size: 28))
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .foregroundStyle(Atelier.textPrimary)
                                .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.corner(10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            AtelierLabel("Kanji enregistrés", tint: Atelier.Tint.japanese)
            let saved = dictionaryModel.notebook.saved.filter { $0.kind == .kanji }
            if saved.isEmpty {
                Text("Saisis un kanji ou touche-en un dans une fiche pour voir ses lectures et ses sens.")
                    .font(.subheadline).foregroundStyle(Atelier.textSecondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(saved) { entry in
                        Button { openKanji(entry.expression) } label: {
                            Text(entry.expression).font(.custom("HiraMinProN-W6", size: 25))
                                .padding(10).foregroundStyle(Atelier.textPrimary)
                                .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.corner(10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var savedShelf: some View {
        Group {
            let saved = dictionaryModel.notebook.saved.filter {
                query.isEmpty || $0.expression.localizedCaseInsensitiveContains(query)
                    || $0.reading.localizedCaseInsensitiveContains(query)
            }
            AtelierLabel("Ma liste · \(saved.count)", tint: Atelier.Tint.japanese)
            if saved.isEmpty {
                emptyState(query.isEmpty ? "Ta liste est vide" : "Aucun élément trouvé",
                           query.isEmpty ? "Touche l'étoile d'une fiche ou d'un mot pour l'enregistrer ici."
                                         : "Essaie un autre mot ou une autre lecture.")
            } else {
                ForEach(saved) { entry in
                    if entry.kind == .kanji {
                        wordRow(entry.expression, reading: "", kind: .kanji)
                    } else {
                        wordRow(entry.expression, reading: entry.reading)
                    }
                }
            }
            AtelierLabel("Lexique personnel · \(lexicon.entries.count)", tint: Atelier.Tint.japanese)
            Text("Tes termes spécialisés, leurs lectures et leurs sens en français.")
                .font(.subheadline).foregroundStyle(Atelier.textSecondary)
            ForEach(lexicon.entries.prefix(compact ? 4 : 8)) { entry in
                Button { showLexicon = true } label: {
                    HStack(spacing: 10) {
                        Text(entry.term).font(.custom("HiraginoSans-W6", size: compact ? 16 : 19))
                            .foregroundStyle(Atelier.textPrimary)
                        if !entry.reading.isEmpty {
                            Text(entry.reading).font(.footnote).foregroundStyle(Atelier.textTertiary)
                        }
                        Spacer()
                        Text(entry.meaning).font(.footnote).lineLimit(1)
                            .foregroundStyle(Atelier.textSecondary)
                    }
                    .padding(10)
                    .background(Atelier.surfaceHigh.opacity(0.65),
                                in: RoundedRectangle(cornerRadius: Atelier.smallRadius))
                }
                .buttonStyle(.plain)
            }
            Button { showLexicon = true } label: {
                Label("Ouvrir et modifier mon lexique", systemImage: "text.book.closed")
            }
            .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.japanese))
        }
    }

    private func wordRow(_ expression: String, reading: String, gloss: String = "",
                         kind: DictionaryModel.SavedEntry.Kind = .word) -> some View {
        let entry = DictionaryModel.SavedEntry(kind: kind, expression: expression, reading: reading)
        return HStack(spacing: 8) {
            Button {
                if kind == .kanji { openKanji(expression) } else { openWord(expression, reading: reading) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(expression).font(.custom("HiraginoSans-W6", size: compact ? 16 : 19))
                            .foregroundStyle(Atelier.textPrimary)
                        if !reading.isEmpty && reading != expression {
                            Text(reading).font(.footnote).foregroundStyle(Atelier.textTertiary)
                        }
                    }
                    if !gloss.isEmpty && !compact {
                        Text(gloss).font(.footnote).lineLimit(2).foregroundStyle(Atelier.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Atelier.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { dictionaryModel.toggleSaved(entry) } label: {
                Image(systemName: dictionaryModel.isSaved(entry) ? "star.fill" : "star")
                    .foregroundStyle(Atelier.Tint.japanese).frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dictionaryModel.isSaved(entry) ? "Retirer de ma liste" : "Enregistrer")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Atelier.surfaceHigh.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: Atelier.smallRadius))
    }

    private func emptyState(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(Atelier.textPrimary)
            Text(detail).font(.subheadline).foregroundStyle(Atelier.textSecondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Atelier.surfaceHigh.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: Atelier.smallRadius))
    }

    private func openWord(_ word: String, reading: String? = nil) {
        focused = false
        session.start(word, preferredReading: reading)
    }

    private func openKanji(_ kanji: String) {
        focused = false
        session.clear()
        session.pushKanji(kanji)
    }

    private func openQuery() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if shelf == .kanji, let character = text.first(where: {
            $0.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
        }) {
            openKanji(String(character))
        } else {
            openWord(text)
        }
    }
}

/// Disposition en lignes qui passent à la ligne (pastilles).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Gestion des dictionnaires

struct DictionaryManagerView: View {
    @EnvironmentObject private var dictionaryModel: DictionaryModel
    @AppStorage(DictionaryModel.firstLanguageKey) private var firstLanguage = "fr"
    @State private var showCatalog = false
    @State private var showImporter = false
    @State private var deleting: DictionaryInfo?

    var body: some View {
        List {
            if let state = dictionaryModel.importState {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.fileName).font(.subheadline.bold())
                        Text(state.step).font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: state.fraction).tint(Atelier.Tint.japanese)
                        Button("Annuler", role: .destructive) { dictionaryModel.cancelImport() }.font(.footnote)
                    }
                }
            }
            Section {
                if dictionaryModel.dictionaries.isEmpty {
                    Text("Aucun dictionnaire. Importe des dictionnaires au format Yomitan (.zip) : JMdict, JPDB, accents (Kanjium), fréquences (JPDB, BCCWJ), KANJIDIC…")
                        .foregroundStyle(.secondary)
                }
                ForEach(dictionaryModel.dictionaries) { d in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(d.title).font(.body.weight(.semibold))
                            Text("\(d.kind) · rév. \(d.revision) · \(counts(d))").font(.caption).foregroundStyle(.secondary)
                            if let a = d.attribution, !a.isEmpty { Text(a).font(.caption2).foregroundStyle(.tertiary).lineLimit(2) }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { d.enabled }, set: { dictionaryModel.setEnabled(d, $0) })).labelsHidden()
                    }
                    .swipeActions {
                        Button(role: .destructive) { deleting = d } label: { Label("Supprimer", systemImage: "trash") }
                    }
                }
                .onMove { dictionaryModel.move(from: $0, to: $1) }
            } header: {
                Text("Dictionnaires (glisse pour l'ordre de priorité)")
            } footer: {
                Text("Mettre à jour : réimporte le nouveau .zip d'un dictionnaire (même titre) ; son ordre est gardé. Les dictionnaires ne sont jamais chargés entièrement en mémoire.")
            }
            Section {
                // Catalogue (#50) : un bouton et une feuille, pas un lien : la liste est toujours en mode « réordonner »,
                // qui grise les liens (recette 1.3.2 (67), D6).
                Button { showCatalog = true } label: {
                    Label("Catalogue : télécharger des dictionnaires", systemImage: "books.vertical")
                }
                // Langue des définitions qui passe en premier (#50, D2) ; réordonne les dictionnaires du catalogue.
                Picker("Langue en premier", selection: $firstLanguage) {
                    Text("Français").tag("fr")
                    Text("Anglais").tag("en")
                }
                .onChange(of: firstLanguage) { _ in dictionaryModel.applyFirstLanguage() }
                Button { showImporter = true } label: { Label("Importer des dictionnaires (.zip)", systemImage: "plus") }
                    .disabled(dictionaryModel.importState != nil)
            }
            Section("Profil de recherche") {
                ProfileSettings()
            }
            Section {
                AudioSettings()
            } header: {
                Text("Audio")
            } footer: {
                Text("Fichiers locaux : dépose-les dans Fichiers → Sur mon iPad → Kyōkasho → Audio (ex. 食べる_たべる.mp3). Sources en ligne : utilisées seulement quand tu touches ▶︎.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .sheet(isPresented: $showCatalog) {
            NavigationStack {
                DictionaryCatalogView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showCatalog = false } } }
            }
            .environmentObject(dictionaryModel)
        }
        .navigationTitle("Dictionnaires")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { dictionaryModel.importDictionaries(urls) }
        }
        .confirmationDialog("Supprimer « \(deleting?.title ?? "") » ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { if let deleting { dictionaryModel.delete(deleting) } }
        }
        .alert("Dictionnaire", isPresented: Binding(get: { dictionaryModel.lastError != nil }, set: { if !$0 { dictionaryModel.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(dictionaryModel.lastError ?? "") }
    }

    private func counts(_ d: DictionaryInfo) -> String {
        var parts: [String] = []
        if d.termCount > 0 { parts.append("\(d.termCount.formatted()) termes") }
        if d.kanjiCount > 0 { parts.append("\(d.kanjiCount.formatted()) kanji") }
        if d.termMetaCount > 0 { parts.append("\(d.termMetaCount.formatted()) méta") }
        if d.mediaCount > 0 { parts.append("\(d.mediaCount) images") }
        return parts.joined(separator: ", ")
    }
}

/// Profils (comme Yomitan) : choix du profil actif, création, réglages de recherche et d'affichage.
struct ProfileSettings: View {
    @EnvironmentObject private var dictionaryModel: DictionaryModel
    @State private var newName = ""
    @State private var naming = false

    var body: some View {
        Picker("Profil actif", selection: $dictionaryModel.profiles.activeId) {
            ForEach(dictionaryModel.profiles.profiles) { Text($0.name).tag($0.id) }
        }
        Button { naming = true } label: { Label("Nouveau profil (copie de l'actif)", systemImage: "plus.square.on.square") }
            .alert("Nom du profil", isPresented: $naming) {
                TextField("Nom", text: $newName)
                Button("Annuler", role: .cancel) {}
                Button("Créer") {
                    var copy = dictionaryModel.profile
                    copy.id = UUID().uuidString
                    copy.name = newName.isEmpty ? "Profil" : newName
                    dictionaryModel.profiles.profiles.append(copy)
                    dictionaryModel.profiles.activeId = copy.id
                    newName = ""
                }
            }
        Stepper("Caractères examinés : \(dictionaryModel.profile.lookup.scanLength)", value: $dictionaryModel.profile.lookup.scanLength, in: 4...40)
        Stepper("Résultats max : \(dictionaryModel.profile.lookup.maxResults)", value: $dictionaryModel.profile.lookup.maxResults, in: 1...100)
        Toggle("Filtrer par partie du discours", isOn: $dictionaryModel.profile.lookup.partsOfSpeechFilter)
        Stepper("Taille du texte : \(Int(dictionaryModel.profile.display.fontSize))", value: $dictionaryModel.profile.display.fontSize, in: 12...28)
        Toggle("Furigana", isOn: $dictionaryModel.profile.display.showFurigana)
        Toggle("Fréquences", isOn: $dictionaryModel.profile.display.showFrequencies)
        Toggle("Accent (graphique)", isOn: $dictionaryModel.profile.display.showPitch)
        Toggle("Étiquettes", isOn: $dictionaryModel.profile.display.showTags)
        Toggle("Définitions compactes", isOn: $dictionaryModel.profile.display.compactGlossary)
        Toggle("Lire l'audio automatiquement", isOn: $dictionaryModel.profile.autoPlayAudio)
        if dictionaryModel.profiles.profiles.count > 1 {
            Button("Supprimer ce profil", role: .destructive) {
                let id = dictionaryModel.profiles.activeId
                dictionaryModel.profiles.profiles.removeAll { $0.id == id }
                dictionaryModel.profiles.activeId = dictionaryModel.profiles.profiles.first?.id ?? DictionaryProfile.standard.id
            }
        }
    }
}

struct AudioSettings: View {
    @EnvironmentObject private var dictionaryModel: DictionaryModel
    @State private var adding = false
    @State private var name = ""
    @State private var template = "https://"

    var body: some View {
        ForEach($dictionaryModel.profile.audioSources) { $source in
            VStack(alignment: .leading, spacing: 4) {
                Toggle(source.name, isOn: $source.enabled)
                Text(source.template).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .onMove { dictionaryModel.profile.audioSources.move(fromOffsets: $0, toOffset: $1) }
        .onDelete { dictionaryModel.profile.audioSources.remove(atOffsets: $0) }
        Button { adding = true } label: { Label("Ajouter une source en ligne", systemImage: "plus") }
            .alert("Source audio", isPresented: $adding) {
                TextField("Nom", text: $name)
                TextField("URL avec {term} et {reading}", text: $template)
                Button("Annuler", role: .cancel) {}
                Button("Ajouter") {
                    dictionaryModel.profile.audioSources.append(AudioSource(name: name.isEmpty ? "Source" : name, kind: .url, template: template))
                    name = ""
                    template = "https://"
                }
            }
        Button("Tester : 食べる") { Task { await dictionaryModel.playAudio(term: "食べる", reading: "たべる") } }
    }
}
