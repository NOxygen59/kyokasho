// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import MorphologyKit
import OCRKit
import ReviewKit
import ReaderCore
import SwiftUI

/// La page est figée à l'ouverture, même en double page : celle choisie dans le panneau d'étude.
///
/// PLAN-CARTES-001, étape E2 (plan approuvé par NOxygen59 le 11/11/2026, DEC-CA-02, 03 et 06 = A) : deux sections.
/// « Lexique du cours » : termes du lexique trouvés sur la page, cochés. « Autres mots » : tous les autres mots de la
/// page découpés par MeCab/UniDic (`PageWordCandidates`, mots grammaticaux retirés) et **trouvés dans les
/// dictionnaires actifs**, décochés, dans l'ordre de la page. Un mot qui a déjà sa carte est signalé (« déjà en
/// carte », « … (autre livre) ») et décoché ; l'ajout reste le même chemin (`addPageCards`, anti-doublon dans la
/// transaction). Sans analyseur ou sans dictionnaire : le lexique seul, avec un message qui dit quoi installer.
/// Découpage et recherches hors du fil principal, arrêtés si l'écran se ferme ; durée notée dans le Diagnostic
/// (objectif < 2 s sur une page dense, à mesurer sur l'iPad).
struct PageCardsView: View {
    /// Un mot proposé (lexique ou dictionnaire), modifiable avant l'ajout.
    struct PageWord: Identifiable, Equatable {
        let id = UUID()
        var term: String
        /// Forme telle qu'écrite sur la page (phrase d'exemple d'un mot conjugué).
        var surface: String
        var reading: String
        var meaning: String
        let fromLexicon: Bool
        /// Carte déjà créée pour ce mot : document d'où elle vient (`""` : aucun) ; `nil` : pas encore de carte.
        var existingDocumentId: String?
    }

    private let reader: ReaderController
    private let document: LibraryDocument
    @State private var page: Int
    @EnvironmentObject private var review: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PageWord] = []
    /// Pourquoi « Autres mots » est vide ou absent (analyseur ou dictionnaire manquant).
    @State private var otherWordsNote: String?
    @State private var selected: Set<UUID> = []
    @State private var text = ""
    @State private var loading = true
    @State private var saving = false
    @State private var message: String?
    @State private var error: String?
    /// Mode du panneau Texte (même clé que `StudyPanel`) : « Mise en page IA » = texte d'OvisOCR2.
    @AppStorage("study.aiLayout") private var panelShowsOvis = false

    init(reader: ReaderController) {
        self.reader = reader
        document = reader.document
        _page = State(initialValue: reader.focusSource)
    }

    private var chosen: [PageWord] {
        entries.filter { selected.contains($0.id) && !$0.reading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !$0.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(document.title) · p. \(document.pageLabel(page))")
                    Text("Vérifie les lectures et les sens avant l'ajout. Les doublons sont ignorés. Les cartes restent liées à ce livre et à cette page ; tu peux les exporter en Anki depuis la bibliothèque.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if loading {
                    ProgressView("Recherche des mots de la page…")
                } else if entries.isEmpty, error == nil {
                    Text("Aucun mot à proposer sur cette page.")
                }
                if !loading {
                    wordSection(lexicon: true)
                    wordSection(lexicon: false)
                    if let otherWordsNote { Text(otherWordsNote).font(.footnote).foregroundStyle(.secondary) }
                }
                if !entries.isEmpty {
                    Text("Une lecture et un sens sont nécessaires. Les corrections ici s'appliquent seulement aux cartes créées.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
                if let message { Text(message) }
            }
            .navigationTitle("Cartes de la page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? String(localized: "Ajout…") : String(localized: "Ajouter (\(chosen.count))")) { Task { await add() } }
                        .disabled(loading || saving || chosen.isEmpty || message != nil)
                }
            }
            .interactiveDismissDisabled(saving)
            .task { await load() }
        }
    }

    /// Une section de mots. Mot coché : lecture et sens modifiables ; décoché : une ligne (liste légère, même longue).
    @ViewBuilder
    private func wordSection(lexicon: Bool) -> some View {
        let ids = entries.filter { $0.fromLexicon == lexicon }.map(\.id)
        if !ids.isEmpty {
            // Revue D-07 F13 : « cochés / proposés » dans l'en-tête, « Tout cocher » sur une vraie ligne de la section.
            let checked = ids.filter(selected.contains).count
            Section {
                let allOn = checked == ids.count
                Button(allOn ? String(localized: "Tout décocher") : String(localized: "Tout cocher")) {
                    if allOn { selected.subtract(ids) } else { selected.formUnion(ids) }
                }
                .buttonStyle(.borderless)
                .disabled(saving || message != nil)
                ForEach($entries) { $entry in
                    if entry.fromLexicon == lexicon { wordRow($entry) }
                }
            } header: {
                Text(lexicon ? String(localized: "Lexique du cours (\(checked)/\(ids.count))")
                     : String(localized: "Autres mots (\(checked)/\(ids.count))"))
            }
        }
    }

    private func wordRow(_ entry: Binding<PageWord>) -> some View {
        let word = entry.wrappedValue
        let on = selected.contains(word.id)
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { on }, set: { value in
                if value { selected.insert(word.id) } else { selected.remove(word.id) }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: word.term).font(.body.bold())
                        if !on, !word.reading.isEmpty, word.reading != word.term {
                            Text(verbatim: word.reading).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if !on, !word.meaning.isEmpty {
                        Text(verbatim: word.meaning).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let other = word.existingDocumentId {
                        Text(other.isEmpty || other == document.id ? String(localized: "Déjà en carte")
                             : String(localized: "Déjà en carte (autre livre)"))
                            .font(.caption.bold()).foregroundStyle(.orange)
                    }
                }
            }
            if on {
                TextField("Lecture en kana (à renseigner)", text: entry.reading)
                TextField("Sens en français", text: entry.meaning, axis: .vertical)
            }
        }
        // Recette 1.5.5 (5.8) : seuls les champs sont figés pendant et après l'ajout ; figer tout le
        // formulaire bloquait aussi son défilement (on ne voyait plus les termes du bas).
        .disabled(saving || message != nil)
    }

    private func load() async {
        defer { loading = false }
        let lexicon = DomainLexicon.shared.entries
        let documentId = document.id
        // C3.2 (audit du 09/11/2026, décision A de NOxygen59) : les termes viennent du texte affiché dans le panneau.
        // Panneau sur un moteur OCR (texte corrigé compris) : son texte ; en « Mise en page IA » : la lecture OvisOCR2.
        let shown = !panelShowsOvis && page == reader.focusSource && reader.ocrState == .idle ? reader.ocrPage?.text : nil
        let cachedText = shown == nil ? await Task.detached(priority: .utility) {
            DocumentAITextStore.read(documentId: documentId, reader: ModelSpec.ovisocr2.id, page: page)
        }.value : nil
        do {
            if let shown, !shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = shown
            } else if let cachedText, !cachedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = cachedText
            } else if let cached = await reader.cachedOCR(source: page) {
                text = cached.text
            } else {
                let url = reader.fileURL, choice = reader.settings.ocrEngine
                let engine = await Task.detached(priority: .utility) {
                    OCRService.resolve(choice, url: url, pageIndex: page)
                }.value
                let result = try await Diagnostics.measure("Cartes : lecture p. \(page)", "cartes") {
                    try await reader.model.ocr.page(documentId: document.id, url: url, pageIndex: page, engine: engine)
                }
                text = result.text
            }
            try Task.checkCancellation()
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                error = String(localized: "La page n'a pas de texte exploitable. Relance sa lecture OCR puis réessaie.")
                return
            }
            var seen: Set<String> = []
            let pageText = text
            // Termes du lexique dans l'ordre où la page les montre (DEC-CA-02 : en tête, cochés).
            let found = lexicon.filter { !$0.term.isEmpty && pageText.contains($0.term) && seen.insert($0.term).inserted }
                .sorted { a, b in
                    // Relecture finale f2b3d49 (N6) : même position (木 / 木材) → le plus long d'abord, puis l'ordre alphabétique.
                    let pa = pageText.range(of: a.term)?.lowerBound ?? pageText.endIndex
                    let pb = pageText.range(of: b.term)?.lowerBound ?? pageText.endIndex
                    return pa != pb ? pa < pb : a.term.count != b.term.count ? a.term.count > b.term.count : a.term < b.term
                }
            // Lectures du lexique prioritaires ; suggestion locale à vérifier pour les entrées sans lecture.
            var words = await Task.detached(priority: .utility) {
                found.map { entry in
                    PageWord(term: entry.term, surface: entry.term,
                             reading: entry.reading.isEmpty ? Self.suggestedReading(entry.term) : entry.reading,
                             meaning: entry.meaning, fromLexicon: true)
                }
            }.value
            try Task.checkCancellation()
            // Revue D-07 F9 : le lexique ne dépend jamais des dictionnaires ; leur échec laisse le lexique et un message.
            do {
                words += try await otherWords(in: pageText, excluding: Set(found.map(\.term)))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                otherWordsNote = String(localized: "Autres mots illisibles : \(error.localizedDescription)")
                Diagnostics.error("Cartes p. \(page), autres mots : \(error.localizedDescription)", "cartes")
            }
            // DEC-CA-03 : une seule carte par mot ; celles qui existent déjà sont signalées et décochées.
            let store = review.store
            let keys = words.map { StudyCard.key(expression: $0.term, reading: $0.reading.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let existing = (try? await Task.detached(priority: .utility) { try store.existingCardDocuments(keys) }.value) ?? [:]
            for i in words.indices { words[i].existingDocumentId = existing[keys[i]] }
            try Task.checkCancellation()
            entries = words
            selected = Set(words.filter { $0.fromLexicon && $0.existingDocumentId == nil }.map(\.id))
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            Diagnostics.error("Cartes p. \(page) : \(error.localizedDescription)", "cartes")
        }
    }

    /// « Autres mots » (DEC-CA-02, DEC-CA-06 A) : découpage MeCab, filtre, recherche groupée dans les dictionnaires
    /// actifs ; seuls les mots trouvés, dans l'ordre de la page. Fermer l'écran annule le travail en cours.
    private func otherWords(in text: String, excluding lexiconTerms: Set<String>) async throws -> [PageWord] {
        guard let mecab = MorphologyService.shared.mecab else {
            otherWordsNote = String(localized: "Pour voir aussi les autres mots de la page, installe l'analyseur japonais (Réglages → Modèles → MeCab + UniDic).")
            return []
        }
        let dictionary = reader.model.dictionary
        let ids = dictionary.activeTermDictionaryIds
        guard let database = dictionary.database, !ids.isEmpty else {
            otherWordsNote = String(localized: "Pour voir aussi les autres mots de la page, installe ou active un dictionnaire (Réglages → Dictionnaires).")
            return []
        }
        let start = Date()
        let work = Task.detached(priority: .userInitiated) { () throws -> [PageWord] in
            let candidates = PageWordCandidates.words(mecab.tokens(text), excluding: lexiconTerms)
            try Task.checkCancellation()
            // Forme de dictionnaire d'abord ; la forme écrite seulement si la première n'existe dans aucune source.
            var lookups = candidates.map { (expression: $0.expression, readingHint: $0.readingHint) }
            lookups += candidates.filter { $0.surface != $0.expression }.map { (expression: $0.surface, readingHint: "") }
            let found = try database.lexiconWords(dictionaryIds: ids, expressions: lookups)
            var seen = lexiconTerms
            return candidates.compactMap { candidate -> PageWord? in
                guard let word = found[candidate.expression] ?? found[candidate.surface],
                      seen.insert(word.expression).inserted else { return nil }
                // Revue Codex après 1.5.6 (P2 n°2) : la carte reçoit la définition entière (`full`), pas l'aperçu
                // coupé à 90 caractères ; seule la ligne de la liste est limitée à l'écran.
                let sense = word.senses.first { $0.language == .french && !$0.full.isEmpty }
                    ?? word.senses.first { $0.language == .english && !$0.full.isEmpty } ?? word.senses.first
                let meaning = sense?.full ?? ""
                return PageWord(term: word.expression, surface: candidate.surface, reading: word.reading ?? word.expression,
                                meaning: meaning, fromLexicon: false)
            }
        }
        let words = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        Diagnostics.log("Cartes p. \(page) : \(words.count) autres mots en \(String(format: "%.2f", Date().timeIntervalSince(start))) s", "cartes")
        if words.isEmpty { otherWordsNote = String(localized: "Aucun autre mot de cette page n'est dans tes dictionnaires.") }
        return words
    }

    nonisolated private static func suggestedReading(_ term: String) -> String {
        let result = NSMutableString(string: term)
        for ruby in Furigana.rubies(for: term).sorted(by: { $0.utf16.location > $1.utf16.location }) {
            result.replaceCharacters(in: ruby.utf16, with: ruby.reading)
        }
        let reading = (result as String).applyingTransform(.hiraganaToKatakana, reverse: true) ?? ""
        // Lecture incomplète : laisser le champ vide plutôt que garder des kanji.
        return reading.contains(where: Furigana.isKanji) ? "" : reading
    }

    private func add() async {
        saving = true
        error = nil
        defer { saving = false }
        let source = "\(document.title) · p. \(document.pageLabel(page))"
        let lines = text.components(separatedBy: .newlines)
        let fields = chosen.map { entry in
            // Mot conjugué sur la page (測っ…) : la phrase est cherchée par la forme écrite, seulement si elle a au
            // moins deux caractères (revue D-07 F12 : une forme d'un caractère attrape n'importe quelle ligne).
            let sentence = lines.first { $0.contains(entry.term) }
                ?? (entry.surface.count > 1 ? lines.first { $0.contains(entry.surface) } : nil) ?? entry.term
            return CardFields.lexicon(expression: entry.term,
                                      reading: entry.reading.trimmingCharacters(in: .whitespacesAndNewlines),
                                      meaning: entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines),
                                      sentence: sentence, source: source)
        }
        do {
            let added = try await review.addPageCards(fields, documentId: document.id, page: page)
            message = String(localized: "\(added) carte(s) ajoutée(s), \(fields.count - added) doublon(s) ignoré(s).")
            Diagnostics.log("Cartes p. \(page) : \(added) ajoutées", "cartes")
        } catch {
            self.error = String(localized: "Ajout impossible : \(error.localizedDescription)")
            Diagnostics.error("Cartes p. \(page) : \(error.localizedDescription)", "cartes")
        }
    }
}
