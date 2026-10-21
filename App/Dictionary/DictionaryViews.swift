// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Recherche manuelle

/// Page de recherche du dictionnaire : un champ, les résultats, l'historique.
struct DictionarySearchView: View {
    @EnvironmentObject private var dictionaryModel: DictionaryModel
    @StateObject private var session: LookupSession
    @State private var query = ""
    @FocusState private var focused: Bool
    var onAddCard: ((TermResult) -> String?)?
    var added: Set<String> = []

    init(dictionary: DictionaryModel, added: Set<String> = [], onAddCard: ((TermResult) -> String?)? = nil) {
        self.added = added
        _session = StateObject(wrappedValue: LookupSession(dictionary: dictionary))
        self.onAddCard = onAddCard
    }

    var body: some View {
        HStack(alignment: .top, spacing: Atelier.gap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Atelier.Tint.japanese)
                    TextField("Mot, kana ou forme conjuguée", text: $query)
                        .focused($focused)
                        .font(.custom("HiraginoSans-W3", size: 20))
                        .submitLabel(.search)
                        .onSubmit { session.start(query) }
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !query.isEmpty {
                        Button { query = ""; session.clear() } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(Atelier.textTertiary)
                    }
                }
                .padding(14)
                .atelierPanel(radius: 16)
                if session.current == nil {
                    historyList
                } else {
                    LookupPopup(session: session, added: added, onAddCard: onAddCard, close: { session.clear() })
                }
            }
        }
        .padding(Atelier.gap)
        .background(GridBackground())
        .navigationTitle("Dictionnaire")
        .onAppear { focused = true }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            AtelierLabel("Historique", tint: Atelier.Tint.japanese)
            if session.history.isEmpty {
                Text(dictionaryModel.hasTermDictionaries
                     ? "Tape un mot : 食べた, たべる, taberu n'est pas encore accepté (kana ou kanji)."
                     : "Aucun dictionnaire importé : Réglages → Dictionnaires.")
                    .foregroundStyle(Atelier.textSecondary)
            }
            FlowLayout(spacing: 8) {
                ForEach(session.history, id: \.self) { word in
                    Button { query = word; session.start(word) } label: {
                        Text(word).font(.custom("HiraginoSans-W3", size: 17))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Atelier.surfaceHigh, in: Capsule())
                    }
                    .foregroundStyle(Atelier.textPrimary)
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .atelierPanel()
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
