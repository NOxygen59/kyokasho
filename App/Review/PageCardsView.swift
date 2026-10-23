// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import OCRKit
import ReaderCore
import SwiftUI

/// La page est figée à l'ouverture, même en double page : celle choisie dans le panneau d'étude.
struct PageCardsView: View {
    private let reader: ReaderController
    private let document: LibraryDocument
    @State private var page: Int
    @EnvironmentObject private var review: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DomainLexicon.Entry] = []
    @State private var selected: Set<UUID> = []
    @State private var text = ""
    @State private var loading = true
    @State private var saving = false
    @State private var message: String?
    @State private var error: String?

    init(reader: ReaderController) {
        self.reader = reader
        document = reader.document
        _page = State(initialValue: reader.focusSource)
    }

    private var chosen: [DomainLexicon.Entry] {
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
                    ProgressView("Recherche des termes de la page…")
                } else if entries.isEmpty, error == nil {
                    Text("Aucun terme du lexique trouvé sur cette page. Tu peux enrichir le lexique dans Réglages → Japonais.")
                }
                ForEach($entries) { $entry in
                    Section {
                        Toggle(entry.term, isOn: Binding(get: { selected.contains(entry.id) }, set: { on in
                            if on { selected.insert(entry.id) } else { selected.remove(entry.id) }
                        }))
                        TextField("Lecture en kana (à renseigner)", text: $entry.reading)
                        TextField("Sens en français", text: $entry.meaning, axis: .vertical)
                    }
                }
                if !entries.isEmpty {
                    Text("Une lecture et un sens sont nécessaires. Les corrections ici s'appliquent seulement aux cartes créées.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
                if let message { Text(message) }
            }
            .disabled(saving || message != nil)
            .navigationTitle("Cartes de la page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Ajout…" : "Ajouter (\(chosen.count))") { Task { await add() } }
                        .disabled(loading || saving || chosen.isEmpty || message != nil)
                }
            }
            .interactiveDismissDisabled(saving)
            .task { await load() }
        }
    }

    private func load() async {
        defer { loading = false }
        let lexicon = DomainLexicon.shared.entries
        let file = DocumentAnalysisService.rawURL(document.id, ModelSpec.ovisocr2.id, page)
        let cachedText = await Task.detached(priority: .utility) {
            try? String(contentsOf: file, encoding: .utf8)
        }.value
        do {
            if let cachedText, !cachedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                error = "La page n'a pas de texte exploitable. Relance sa lecture OCR puis réessaie."
                return
            }
            var seen: Set<String> = []
            entries = lexicon.filter { !$0.term.isEmpty && text.contains($0.term) && seen.insert($0.term).inserted }
            // Lectures du lexique prioritaires ; suggestion locale à vérifier pour les entrées sans lecture.
            let candidates = entries
            entries = await Task.detached(priority: .utility) {
                candidates.map { entry in
                    var entry = entry
                    if entry.reading.isEmpty { entry.reading = Self.suggestedReading(entry.term) }
                    return entry
                }
            }.value
            try Task.checkCancellation()
            selected = Set(entries.map(\.id))
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            Diagnostics.error("Cartes p. \(page) : \(error.localizedDescription)", "cartes")
        }
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
        let fields = chosen.map { entry in
            let sentence = text.components(separatedBy: .newlines).first { $0.contains(entry.term) } ?? entry.term
            return CardFields.lexicon(expression: entry.term,
                                      reading: entry.reading.trimmingCharacters(in: .whitespacesAndNewlines),
                                      meaning: entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines),
                                      sentence: sentence, source: source)
        }
        do {
            let added = try await review.addPageCards(fields, documentId: document.id, page: page)
            message = "\(added) carte(s) ajoutée(s), \(fields.count - added) doublon(s) ignoré(s)."
            Diagnostics.log("Cartes p. \(page) : \(added) ajoutées", "cartes")
        } catch {
            self.error = "Ajout impossible : \(error.localizedDescription)"
            Diagnostics.error("Cartes p. \(page) : \(error.localizedDescription)", "cartes")
        }
    }
}
