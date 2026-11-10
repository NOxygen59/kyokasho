// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
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
                    ForEach(feed.words) { word in
                        Button { open(word) } label: { LexiconRow(word: word) }
                            .buttonStyle(.plain)
                            .onAppear { wordAppeared(word) }
                    }
                    footer
                }
                .padding(14)
            }
            .atelierPanel()
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
            if feed.accept(page, request: start.request) { loadError = nil }
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
