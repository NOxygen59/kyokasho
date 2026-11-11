// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import ReviewKit
import SwiftUI
import YomitanKit

/// Catégorie « Lexique » de l'accueil (PLAN-LEX-001, étapes E2 et E3) : tous les mots des dictionnaires installés et
/// actifs, rangés par lecture, avec leur sens en français et en anglais. Toucher un mot ouvre sa fiche (la fenêtre du
/// dictionnaire, avec ⭐ et « + carte ») ; le champ de recherche garde les mots qui commencent par le texte tapé.
///
/// Cette vue n'a pas de logique propre : l'état de la liste est `LexiconFeed` (testé sur Mac), la lecture est
/// `DictionaryModel.lexiconPage` (hors du fil principal, annulable). Elle n'écrit rien dans les bases.
///
/// Invariants d'affichage : un sens absent dans une langue s'affiche « — », jamais l'autre langue à sa place
/// (DEC-02) ; la lecture n'est pas affichée quand elle répète le mot (DEC-04) ; les sens sont coupés à deux lignes
/// (DEC-05) ; les dictionnaires désactivés n'apparaissent pas (DEC-06, même règle que la recherche).
struct LexiconView: View {
    @EnvironmentObject private var dictionaryModel: DictionaryModel
    @EnvironmentObject private var review: ReviewModel
    @ObservedObject private var catalog = DictionaryCatalogService.shared
    /// Fiche du mot touché : la même pile de recherches que le dictionnaire (`LookupSession`), rien de réécrit.
    @StateObject private var session: LookupSession
    @State private var showEntry = false
    /// Début de mot tapé (DEC-07), en kana ou en kanji.
    @State private var query = ""
    @FocusState private var searching: Bool
    /// Ajoute une carte depuis la fiche ; renvoie un court message (doublon, erreur) ou `nil`.
    var onAddCard: ((TermResult) -> String?)?
    @State private var feed = LexiconFeed()
    @State private var loadError: String?
    /// Lecture de la page suivante demandée par le défilement ; annulée si l'écran se ferme.
    @State private var moreTask: Task<Void, Never>?
    /// Filtre « Mes mots » (11/11/2026) : seulement les mots enregistrés d'une étoile, lus d'un coup (liste courte).
    @State private var savedOnly = false
    @State private var savedWords: [LexiconWord] = []
    /// Cartes créées depuis une ligne pendant cet écran : ✓ tout de suite, la création finit en tâche de fond.
    @State private var addedNow: Set<String> = []
    @State private var toast: String?

    init(dictionary: DictionaryModel, onAddCard: ((TermResult) -> String?)? = nil) {
        _session = StateObject(wrappedValue: LookupSession(dictionary: dictionary))
        self.onAddCard = onAddCard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Lexique").font(Atelier.display(27)).foregroundStyle(Atelier.textPrimary)
                Text("Tous les mots de tes dictionnaires actifs, rangés par lecture.")
                    .font(.subheadline).foregroundStyle(Atelier.textSecondary)
            }
            searchField
            scopeChips
            if updating {
                // État discret : la liste reste utilisable, elle se relit seule à la fin (voir `reloadKey`).
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Atelier.Tint.japanese)
                    Text("Dictionnaires en cours de mise à jour : la liste se rafraîchira à la fin.")
                        .font(.footnote).foregroundStyle(Atelier.textSecondary)
                }
            }
            list
        }
        .padding(Atelier.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { GridBackground() }
        // Première page, puis relecture complète dès que la liste des dictionnaires consultés change (activation,
        // installation ou mise à jour finie, langue du lexique fourni). La tâche précédente est annulée par SwiftUI.
        .task(id: reloadKey + "\u{1}" + LexiconFeed.cleanPrefix(query)) {
            // Frappe en cours : on attend un court instant avant de relire (la tâche est annulée à la lettre suivante).
            // La liste affichée reste en place pendant l'attente, puis repart du début pour la nouvelle recherche.
            if LexiconFeed.cleanPrefix(query) != feed.prefix {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
            }
            moreTask?.cancel()
            feed.reset(prefix: query)
            await loadNext()
        }
        .onDisappear { moreTask?.cancel() }
        // « Mes mots » : relu quand le filtre s'allume, quand une étoile change ou quand les dictionnaires changent.
        .task(id: savedKey) {
            guard savedOnly else { return }
            guard let words = try? await dictionaryModel.savedLexiconWords(), !Task.isCancelled else { return }
            savedWords = words
            review.loadKeys(words.map(cardKey))
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(Atelier.font(14, weight: .semibold)).foregroundStyle(Atelier.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .atelierPanel(radius: 14)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
        // Cartes déjà créées pour les mots de la fiche (✓ à la place de « + carte »), comme dans le dictionnaire.
        .task(id: session.currentTerms.map(\.id).joined(separator: ";")) {
            review.loadKeys(session.currentTerms.map(\.id))
        }
        .sheet(isPresented: $showEntry, onDismiss: { session.clear() }) {
            LookupPopup(session: session, added: review.keys, onAddCard: onAddCard, close: { showEntry = false })
                .padding(Atelier.gap)
                .environmentObject(dictionaryModel).environmentObject(review)
                .preferredColorScheme(Theme.current.colorScheme)
                .atelierSheet()
        }
    }

    /// Champ de recherche simple (DEC-07) : début de mot. En kana, il est comparé à la lecture ; sinon à la forme
    /// écrite (règle de `DictionaryDatabase.lexiconPage`).
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Atelier.Tint.japanese)
            TextField(String(localized: "Début d'un mot, en kana ou en kanji"), text: $query)
                .focused($searching)
                .font(.custom("HiraginoSans-W3", size: 19))
                .submitLabel(.search)
                .onSubmit { searching = false }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = ""; searching = false } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(Atelier.textTertiary)
                    .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(14)
        .atelierPanel(radius: 16)
    }

    /// « Tous les mots » ou « Mes mots » (ceux enregistrés d'une étoile, ici ou dans le dictionnaire).
    private var scopeChips: some View {
        let count = dictionaryModel.notebook.saved.filter { $0.kind == .word }.count
        return HStack(spacing: 7) {
            chip(String(localized: "Tous les mots"), on: !savedOnly) { savedOnly = false }
            chip(String(localized: "Mes mots · \(count)"), on: savedOnly) { savedOnly = true }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(Atelier.font(14, weight: .semibold)).lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(on ? Atelier.onAccentInk.opacity(0.85) : Atelier.textSecondary)
                .background(on ? Atelier.Tint.japanese : Atelier.surfaceHigh, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var savedKey: String {
        guard savedOnly else { return "" }
        return reloadKey + "\u{1}" + dictionaryModel.notebook.saved.filter { $0.kind == .word }.map(\.id).joined(separator: ",")
    }

    /// Mots à afficher : la liste paginée, ou « Mes mots » filtrés par la recherche (même règle de début de mot).
    private var shownWords: [LexiconWord] {
        savedOnly ? savedWords.filter { $0.matches(prefix: query) } : feed.words
    }

    private func savedEntry(_ word: LexiconWord) -> DictionaryModel.SavedEntry {
        // Même identité que les lignes du dictionnaire : forme et lecture réelle (jamais la lecture masquée, DEC-04).
        .init(kind: .word, expression: word.expression, reading: word.sortReading)
    }

    private func cardKey(_ word: LexiconWord) -> String {
        StudyCard.key(expression: word.expression, reading: word.sortReading)
    }

    /// Étoile et « + carte » d'une ligne : les mêmes actions que dans la fiche, sans l'ouvrir.
    private func rowActions(_ word: LexiconWord) -> some View {
        let entry = savedEntry(word)
        let saved = dictionaryModel.isSaved(entry)
        let hasCard = addedNow.contains(cardKey(word)) || review.keys.contains(cardKey(word))
        return HStack(spacing: 0) {
            Button { dictionaryModel.toggleSaved(entry) } label: {
                Image(systemName: saved ? "star.fill" : "star")
                    .foregroundStyle(Atelier.Tint.japanese).frame(width: 40, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(saved ? String(localized: "Retirer de ma liste") : String(localized: "Enregistrer"))
            if onAddCard != nil {
                Button { addCard(word) } label: {
                    Image(systemName: hasCard ? "checkmark.rectangle.stack" : "rectangle.stack.badge.plus")
                        .foregroundStyle(hasCard ? Atelier.textTertiary : Atelier.Tint.japanese).frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(hasCard)
                .accessibilityLabel(hasCard ? String(localized: "Déjà dans tes cartes") : String(localized: "Créer une carte"))
            }
        }
    }

    /// Carte créée par le chemin habituel du dictionnaire (`onAddCard`) : la fiche du mot est d'abord relue, pour que
    /// la carte porte les mêmes définitions que si elle venait de la fiche. Rien n'est créé si la fiche est introuvable.
    private func addCard(_ word: LexiconWord) {
        guard let onAddCard else { return }
        Task {
            let results = await dictionaryModel.lookup(word.expression)
            guard let term = results.first(where: { $0.expression == word.expression && $0.reading == word.sortReading }) else {
                show(String(localized: "Fiche introuvable pour ce mot : carte non créée."))
                return
            }
            let message = onAddCard(term)
            if message == nil { addedNow.insert(cardKey(word)) } else { review.loadKeys([cardKey(word)]) }
            show(message ?? String(localized: "Carte ajoutée"))
        }
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == message { toast = nil }
        }
    }

    /// Fiche complète du mot : sa lecture passe en premier quand plusieurs mots s'écrivent pareil.
    private func open(_ word: LexiconWord) {
        searching = false
        session.start(word.expression, preferredReading: word.sortReading)
        showEntry = true
    }

    /// Change quand la liste des dictionnaires consultés change : mêmes identifiants, même nombre de termes.
    private var reloadKey: String {
        let active = dictionaryModel.activeTermDictionaryIds
        return dictionaryModel.dictionaries.filter { active.contains($0.id ?? -1) }
            .map { "\($0.id ?? 0):\($0.termCount):\($0.revision)" }.joined(separator: ",")
    }

    private var updating: Bool { dictionaryModel.importState != nil || catalog.working != nil }

    @ViewBuilder
    private var list: some View {
        if !dictionaryModel.hasTermDictionaries {
            message(String(localized: "Aucun dictionnaire installé"),
                    String(localized: "Importe un dictionnaire Yomitan dans Réglages → Japonais → Dictionnaires."))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(shownWords) { word in
                        HStack(spacing: 2) {
                            Button { open(word) } label: { LexiconRow(word: word) }
                                .buttonStyle(.plain)
                            rowActions(word)
                        }
                        .onAppear { if !savedOnly { wordAppeared(word) } }
                    }
                    if savedOnly { savedFooter } else { footer }
                }
                .padding(14)
            }
            .atelierPanel()
        }
    }

    /// Bas de la liste « Mes mots » : pourquoi elle est vide, le cas échéant.
    @ViewBuilder
    private var savedFooter: some View {
        if shownWords.isEmpty {
            let none = dictionaryModel.notebook.saved.allSatisfy { $0.kind != .word }
            Text(none ? String(localized: "Aucun mot enregistré. Touche l'étoile d'un mot pour le retrouver ici.")
                 : savedWords.isEmpty ? String(localized: "Tes mots enregistrés ne sont pas dans les dictionnaires actifs.")
                 : String(localized: "Aucun mot à ce début"))
                .font(.footnote).foregroundStyle(Atelier.textTertiary)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let loadError {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lecture du lexique impossible : \(loadError)")
                    .font(.subheadline).foregroundStyle(Atelier.textSecondary)
                Button("Réessayer") { startLoadingMore() }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.japanese))
            }
            .padding(.vertical, 8)
        } else if feed.isLoading {
            HStack { Spacer(); ProgressView().tint(Atelier.Tint.japanese); Spacer() }.padding(.vertical, 12)
        } else if feed.reachedEnd {
            Text(feed.words.isEmpty
                 ? (feed.prefix.isEmpty ? String(localized: "Aucun mot dans les dictionnaires actifs.")
                    : String(localized: "Aucun mot à ce début") + " · " + String(localized: "Essaie la forme de base ou une lecture en kana."))
                 : String(localized: "Fin du lexique · \(feed.words.count) mots"))
                .font(.footnote).foregroundStyle(Atelier.textTertiary)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(Atelier.textPrimary)
            Text(detail).font(.subheadline).foregroundStyle(Atelier.textSecondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .atelierPanel()
    }

    // MARK: Défilement sans fin

    private func wordAppeared(_ word: LexiconWord) {
        guard feed.shouldLoadMore(appearing: word.id) else { return }
        startLoadingMore()
    }

    private func startLoadingMore() {
        moreTask?.cancel()
        moreTask = Task { await loadNext() }
    }

    /// Lit la page suivante si aucune lecture n'est en cours. Une réponse arrivée après un `reset` est jetée par
    /// `LexiconFeed.accept` (numéro de demande) : jamais de mots d'une ancienne liste dans la nouvelle.
    private func loadNext() async {
        guard let start = feed.beginLoading() else { return }
        do {
            let page = try await dictionaryModel.lexiconPage(after: start.after, prefix: start.prefix)
            if feed.accept(page, request: start.request) {
                loadError = nil
                // Cartes déjà créées pour ces mots : ✓ sur la ligne, sans attendre l'ouverture d'une fiche.
                review.loadKeys(page.words.map(cardKey))
            }
        } catch is CancellationError {
            feed.fail(request: start.request)
        } catch {
            feed.fail(request: start.request)
            if feed.request == start.request { loadError = error.localizedDescription }
        }
    }
}

/// Une ligne du Lexique : forme japonaise avec sa lecture au-dessus, puis le sens en français et en anglais.
struct LexiconRow: View {
    let word: LexiconWord

    var body: some View {
        // Large (paysage) : trois colonnes ; étroit (portrait, Split View) : la forme puis les sens dessous.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                LexiconFurigana(word: word).frame(width: 220, alignment: .leading)
                sense(.french, tag: "FR").frame(maxWidth: .infinity, alignment: .leading)
                sense(.english, tag: "EN").frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 620)
            VStack(alignment: .leading, spacing: 4) {
                LexiconFurigana(word: word)
                sense(.french, tag: "FR")
                sense(.english, tag: "EN")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Atelier.surfaceHigh.opacity(0.65), in: RoundedRectangle(cornerRadius: Atelier.smallRadius))
        .accessibilityElement(children: .combine)
    }

    /// DEC-02 : « — » quand la langue n'a pas de sens pour ce mot ; rien n'est recopié ni traduit.
    private func sense(_ language: LexiconLanguage, tag: String) -> some View {
        let text = word.summary(language)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: tag).font(Atelier.font(10, weight: .semibold)).foregroundStyle(Atelier.textTertiary)
            Text(verbatim: text ?? "—").font(.footnote).lineLimit(2)
                .foregroundStyle(text == nil ? Atelier.textTertiary : Atelier.textSecondary)
        }
    }
}

/// Forme japonaise, lecture répartie au-dessus des kanji (`JapaneseText.distributeFurigana`, comme les fiches).
private struct LexiconFurigana: View {
    let word: LexiconWord

    var body: some View {
        let segments = word.furigana
        let hasReading = segments.contains { !$0.reading.isEmpty }
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                VStack(spacing: 0) {
                    // Ligne de lecture gardée vide sous les kana : toutes les formes restent sur la même ligne de base.
                    if hasReading {
                        Text(verbatim: segment.reading.isEmpty ? " " : segment.reading)
                            .font(.custom("HiraginoSans-W3", size: 10)).foregroundStyle(Atelier.textTertiary)
                            .lineLimit(1).fixedSize()
                    }
                    Text(verbatim: segment.text).font(.custom("HiraginoSans-W6", size: 19))
                        .foregroundStyle(Atelier.textPrimary).lineLimit(1).fixedSize()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: word.reading.map { "\(word.expression)、\($0)" } ?? word.expression))
    }
}
