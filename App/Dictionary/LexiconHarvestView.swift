// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import GLMOCRKit
import OCRKit
import ReaderCore
import SwiftUI
import UniformTypeIdentifiers

/// Lexique du design d'intérieur (#50, lot D4) : propositions de termes à valider.
/// - Piste A : Qwen3-VL relève les termes techniques des pages d'un livre déjà lues par OvisOCR2 (une tâche IA,
///   visible dans « Activité des IA », arrêtable) ; rien ne part en ligne.
/// - Piste C : import d'un glossaire en tableau (CSV, TSV ou texte « terme | lecture | sens »).
/// Rien n'entre dans le lexique sans être coché puis « Ajouter ».
struct LexiconHarvestView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var lexicon = DomainLexicon.shared
    @ObservedObject private var center = AITaskCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var documentId: String?
    @State private var candidates: [LexiconCandidate] = []
    @State private var picked: Set<String> = []
    @State private var showImporter = false
    @State private var error: String?
    @State private var pagesDone = 0
    @State private var pagesTotal = 0
    /// Choix de NOxygen59 (recette 1.3.2 (67), D8) : l'IA du relevé et la langue des sens, gardés.
    @AppStorage("lexique.releve.modele") private var modelID = ModelSpec.qwen3vl4b.id
    @AppStorage("lexique.releve.langue") private var languageRaw = TermExtractor.Language.french.rawValue

    private var chosenModel: ModelSpec { TermExtractor.models.first { $0.id == modelID } ?? .qwen3vl4b }
    private var language: TermExtractor.Language { TermExtractor.Language(rawValue: languageRaw) ?? .french }

    private static let key = "lexique|releve"
    private var running: Bool { center.isRunning(Self.key) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Livre", selection: $documentId) {
                        Text("Choisir…").tag(String?.none)
                        ForEach(model.documents) { d in Text(d.title).tag(Optional(d.id)) }
                    }
                    Picker("IA", selection: $modelID) {
                        ForEach(TermExtractor.models, id: \.id) { spec in
                            Text(spec.id == ModelSpec.qwen35chat.id ? ModelSpec.qwen35chatName : String(localized: "Qwen3-VL 4B"))
                                + Text(TermExtractor.isAvailable(spec) ? "" : String(localized: " (à télécharger)"))
                        }
                    }
                    Picker("Sens en", selection: $languageRaw) {
                        Text("Français").tag(TermExtractor.Language.french.rawValue)
                        Text("Anglais").tag(TermExtractor.Language.english.rawValue)
                    }
                    .pickerStyle(.segmented)
                    Button {
                        harvest()
                    } label: {
                        Label(running ? String(localized: "Relevé en cours… (\(pagesDone)/\(pagesTotal))") : String(localized: "Relever les termes avec l'IA"),
                              systemImage: "sparkles")
                    }
                    .disabled(documentId == nil || running || !TermExtractor.isAvailable(chosenModel))
                    if running { Button("Arrêter", role: .destructive) { center.cancel(key: Self.key) } }
                } header: {
                    Text("Depuis tes manuels")
                } footer: {
                    Text(TermExtractor.isAvailable(chosenModel)
                         ? String(localized: "L'IA choisie lit les pages déjà lues par OvisOCR2 et propose les termes du métier, avec lecture et sens dans la langue choisie. Environ 20 à 40 s par page ; branche l'iPad pour un livre entier.")
                         : String(localized: "Télécharge ce modèle dans Réglages → Modèles d'IA, ou choisis-en un autre."))
                }
                Section {
                    Button { showImporter = true } label: { Label("Importer un glossaire (CSV, texte)", systemImage: "tablecells") }
                } footer: {
                    Text("Une ligne par terme : terme ; lecture ; sens (séparateur ; , | ou tabulation). Un tableur exporté en CSV convient.")
                }
                if !candidates.isEmpty {
                    Section {
                        ForEach(candidates) { c in
                            Button { toggle(c.term) } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: picked.contains(c.term) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(picked.contains(c.term) ? Atelier.Tint.japanese : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(c.term).font(.custom("HiraginoSans-W3", size: 17))
                                            if !c.reading.isEmpty { Text(c.reading).font(.caption).foregroundStyle(.secondary) }
                                            if let page = c.page { Text("p. \(page + 1)").font(.caption2).foregroundStyle(.tertiary) }
                                        }
                                        if !c.meaning.isEmpty { Text(c.meaning).font(.footnote).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text("\(candidates.count) proposition(s)")
                            Spacer()
                            Button(picked.count == candidates.count ? String(localized: "Aucun") : String(localized: "Tout")) {
                                picked = picked.count == candidates.count ? [] : Set(candidates.map(\.term))
                            }
                        }
                    } footer: {
                        Text("Vérifie la lecture et le sens : l'IA peut se tromper. Un terme ajouté se modifie ensuite dans le lexique.")
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("Enrichir le lexique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter (\(picked.count))") { addPicked() }.disabled(picked.isEmpty)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { result in
                importGlossary(result)
            }
        }
    }

    private func toggle(_ term: String) {
        if picked.contains(term) { picked.remove(term) } else { picked.insert(term) }
    }

    private func merge(_ found: [LexiconCandidate]) {
        let known = Set(lexicon.entries.map(\.term)).union(candidates.map(\.term))
        let fresh = LexiconCandidates.new(found, known: known)
        candidates += fresh
        picked.formUnion(fresh.map(\.term))
    }

    private func importGlossary(_ result: Result<URL, Error>) {
        error = nil
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
            error = String(localized: "Fichier illisible (UTF-8 ou Shift-JIS attendu).")
            return
        }
        let found = LexiconCandidates.parse(text)
        if found.isEmpty { error = String(localized: "Aucun terme reconnu : une ligne par terme, « terme ; lecture ; sens ».") }
        merge(found)
    }

    /// Une tâche IA de l'app : continue si l'on ferme la fenêtre ; les propositions reviennent à la réouverture
    /// seulement si elle est encore ouverte (sinon, relancer : les pages déjà vues sont refaites, rien n'est écrit).
    private func harvest() {
        guard let id = documentId, let document = model.documents.first(where: { $0.id == id }) else { return }
        error = nil
        let pages = (0..<document.pageCount).filter { DocumentAITextStore.read(documentId: id, reader: ModelSpec.ovisocr2.id, page: $0) != nil }
        guard !pages.isEmpty else {
            error = String(localized: "Aucune page de ce livre n'a encore été lue par OvisOCR2.")
            return
        }
        pagesDone = 0
        pagesTotal = pages.count
        let known = lexicon.entries.map(\.term)
        let spec = chosenModel, language = language
        center.run(Self.key, title: String(localized: "Relevé des termes : \(document.title)"), modelId: spec.id, activity: "lecture") { job in
            for page in pages {
                try Task.checkCancellation()
                guard let markdown = DocumentAITextStore.read(documentId: id, reader: ModelSpec.ovisocr2.id, page: page) else { continue }
                center.log(job, "p. \(page + 1) : recherche des termes du métier…")
                let text = try await TermExtractor.extract(markdown: markdown, known: known + candidates.map(\.term),
                                                           language: language, model: spec)
                let found = LexiconCandidates.parse(text, page: page)
                center.log(job, "p. \(page + 1) : \(found.count) terme(s) proposé(s)")
                merge(found)
                pagesDone += 1
            }
        }
    }

    private func addPicked() {
        for c in candidates where picked.contains(c.term) {
            lexicon.save(DomainLexicon.Entry(term: c.term, reading: c.reading, meaning: c.meaning))
        }
        candidates.removeAll { picked.contains($0.term) }
        picked = []
    }
}
