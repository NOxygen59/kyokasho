// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import SwiftUI

/// Lexique du domaine (design d'intérieur), modifiable : termes que les dictionnaires généraux ne connaissent pas
/// (野縁, 吊り木…), avec leur lecture et leur sens. Sert à la relecture de l'OCR (terme = mot connu), au choix des
/// lectures dans l'analyse, au glossaire des traductions et aux aides du chat. Prérempli par le glossaire de départ ;
/// gardé dans `Application Support/Kyokasho/lexique.json`.
@MainActor
final class DomainLexicon: ObservableObject {
    struct Entry: Codable, Identifiable, Equatable, Sendable {
        var id = UUID()
        var term: String
        var reading: String
        var meaning: String
    }

    static let shared = DomainLexicon()

    @Published private(set) var entries: [Entry] = []

    /// Copie lisible depuis n'importe quel fil (relecture OCR hors du fil principal).
    nonisolated static var terms: [String] { lock.withLock { snapshot.map(\.term) } }
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var snapshot: [Entry] = []

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kyokasho/lexique.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        } else {
            entries = Self.starter
        }
        Self.lock.withLock { Self.snapshot = entries }
    }

    /// Glossaire de départ (lectures ajoutées pour les termes qui en ont besoin le plus souvent).
    static var starter: [Entry] {
        Qwen3VLReader.defaultGlossary.map { Entry(term: $0.0, reading: "", meaning: $0.1) }
    }

    /// Terme → sens (traduction, chat).
    var glossary: [(String, String)] { entries.filter { !$0.meaning.isEmpty }.map { ($0.term, $0.meaning) } }
    /// Terme → lecture, quand elle est renseignée (chat).
    var readings: [String: String] {
        Dictionary(entries.filter { !$0.reading.isEmpty }.map { ($0.term, $0.reading) }, uniquingKeysWith: { a, _ in a })
    }

    func save(_ entry: Entry) {
        var e = entry
        e.term = e.term.trimmingCharacters(in: .whitespacesAndNewlines)
        e.reading = e.reading.trimmingCharacters(in: .whitespacesAndNewlines)
        e.meaning = e.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.term.isEmpty else { return }
        if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i] = e } else { entries.append(e) }
        persist()
    }

    func delete(_ ids: [UUID]) {
        entries.removeAll { ids.contains($0.id) }
        persist()
    }

    /// Termes de départ manquants remis (les termes modifiés ou ajoutés restent).
    func restoreStarter() {
        for e in Self.starter where !entries.contains(where: { $0.term == e.term }) { entries.append(e) }
        persist()
    }

    private func persist() {
        entries.sort { $0.term < $1.term }
        Self.lock.withLock { Self.snapshot = entries }
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: Self.file, options: .atomic)
    }
}

/// Réglages → Japonais → « Lexique du domaine ».
struct DomainLexiconView: View {
    @ObservedObject private var lexicon = DomainLexicon.shared
    @State private var search = ""
    @State private var editing: DomainLexicon.Entry?
    @State private var showHarvest = false

    private var shown: [DomainLexicon.Entry] {
        guard !search.isEmpty else { return lexicon.entries }
        return lexicon.entries.filter { $0.term.contains(search) || $0.reading.contains(search) || $0.meaning.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section {
                ForEach(shown) { e in
                    Button { editing = e } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(e.term).font(.custom("HiraginoSans-W3", size: 17)).foregroundStyle(.primary)
                                if !e.reading.isEmpty { Text(e.reading).font(.caption).foregroundStyle(.secondary) }
                            }
                            if !e.meaning.isEmpty { Text(e.meaning).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
                .onDelete { offsets in lexicon.delete(offsets.map { shown[$0].id }) }
            } footer: {
                Text("\(lexicon.entries.count) termes. Un terme du lexique compte comme un mot connu pour la relecture de l'OCR (moins de faux « caractères douteux ») et l'analyse ; son sens est imposé aux traductions de Qwen3-VL ; lecture et sens aident le chat.")
            }
            Section {
                // Lexique du design d'intérieur (#50, D4) : termes relevés dans les manuels ou importés, à valider.
                Button { showHarvest = true } label: { Label("Enrichir : relever dans mes manuels, importer un glossaire", systemImage: "sparkles") }
                Button("Remettre les termes de départ manquants") { lexicon.restoreStarter() }
            }
        }
        .searchable(text: $search, prompt: String(localized: "Chercher un terme"))
        .navigationTitle("Lexique du domaine")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = DomainLexicon.Entry(term: "", reading: "", meaning: "") } label: { Label("Ajouter", systemImage: "plus") }
            }
        }
        .stackedSheet(item: $editing) { entry in LexiconEntryEditor(entry: entry) }
        .stackedSheet(isPresented: $showHarvest) { LexiconHarvestView() }
    }
}

private struct LexiconEntryEditor: View {
    @State var entry: DomainLexicon.Entry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetStack {
            Form {
                TextField("Terme (ex. 野縁)", text: $entry.term)
                TextField("Lecture en kana (ex. のぶち)", text: $entry.reading)
                TextField("Sens en français (ex. tasseau de plafond)", text: $entry.meaning, axis: .vertical)
            }
            .navigationTitle(entry.term.isEmpty ? String(localized: "Nouveau terme") : entry.term)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { DomainLexicon.shared.save(entry); dismiss() }
                        .disabled(entry.term.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
