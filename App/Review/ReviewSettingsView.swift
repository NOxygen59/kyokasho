// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReviewKit
import SwiftUI

/// Réglages → Révisions : rythme, paquets, modèle, contenu, AnkiMobile, export, médias.
struct ReviewSettingsView: View {
    @EnvironmentObject private var review: ReviewModel
    @State private var newDeckName = ""
    @State private var askingDeck = false
    @State private var exportURL: URL?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Stepper("Nouvelles cartes par jour : \(review.settings.newCardsPerDay)",
                        value: $review.settings.newCardsPerDay, in: 0...200, step: 5)
                Stepper("Révisions max par jour : \(review.settings.maximumReviewsPerDay)",
                        value: $review.settings.maximumReviewsPerDay, in: 10...2000, step: 10)
                VStack(alignment: .leading) {
                    Text("Rétention visée : \(Int((review.settings.retention * 100).rounded())) %")
                    Slider(value: $review.settings.retention, in: 0.80...0.97, step: 0.01)
                }
                Picker("La journée commence à", selection: $review.settings.dayStartHour) {
                    ForEach(0..<13) { h in Text("\(h) h").tag(h) }
                }
            } header: {
                Text("Rythme")
            } footer: {
                Text("Rétention : chance de te souvenir d'une carte le jour où elle revient. Plus haut = plus de révisions. 90 % est un bon choix.")
            }

            Section("Paquets") {
                Picker("Paquet des nouvelles cartes", selection: Binding(
                    get: { review.defaultDeckId }, set: { review.settings.defaultDeckId = $0 })) {
                    ForEach(review.decks) { deck in Text(deck.name).tag(deck.id) }
                }
                Button { newDeckName = ""; askingDeck = true } label: { Label("Nouveau paquet", systemImage: "plus") }
            }

            Section {
                if let template = review.defaultTemplate {
                    NavigationLink("Modèle « \(template.name) »") { TemplateEditorView(template: template) }
                }
                Toggle("Image de la ligne du manuel", isOn: $review.settings.includeImage)
                Toggle("Prononciation (audio)", isOn: $review.settings.includeAudio)
            } header: {
                Text("Cartes créées")
            } footer: {
                Text("Le modèle décide de ce qui est au recto et au verso. L'audio vient des sources réglées dans Dictionnaires.")
            }

            Section {
                Toggle("Envoyer aussi vers AnkiMobile", isOn: $review.settings.sendToAnkiMobile)
                if review.settings.sendToAnkiMobile {
                    TextField("Paquet dans Anki", text: $review.settings.ankiMobileDeck)
                    TextField("Type de note dans Anki", text: $review.settings.ankiMobileNoteType)
                }
            } header: {
                Text("AnkiMobile")
            } footer: {
                Text("Le type de note doit exister dans Anki avec les mêmes noms de champs (Mot, Lecture, Sens…). Texte seulement : AnkiMobile ne reçoit pas les images ni les sons par ce chemin.")
            }

            Section {
                Button { export(apkg: true) } label: { Label("Créer un paquet Anki (.apkg)", systemImage: "shippingbox") }
                Button { export(apkg: false) } label: { Label("Créer un fichier CSV", systemImage: "tablecells") }
                if let exportURL {
                    Label("Fichier prêt : \(exportURL.lastPathComponent)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    ShareLink(item: exportURL) {
                        Label("Enregistrer ou envoyer le fichier", systemImage: "square.and.arrow.up").font(.headline)
                    }
                }
            } header: {
                Text("Exporter vers Anki")
            } footer: {
                Text("Les cartes arrivent comme neuves dans Anki : l'historique de révision ne suit pas.")
            }

            Section {
                Button("Nettoyer les médias inutilisés") {
                    let n = (try? review.store.removeUnusedMedia()) ?? 0
                    message = n == 0 ? String(localized: "Aucun fichier inutile.") : String(localized: "\(n) fichier\(n > 1 ? "s" : "") supprimé\(n > 1 ? "s" : "").")
                }
            } footer: {
                Text("Supprime les images et sons que plus aucune carte n'utilise.")
            }
        }
        .navigationTitle("Révisions")
        .alert("Nouveau paquet", isPresented: $askingDeck) {
            TextField("Nom", text: $newDeckName)
            Button("Annuler", role: .cancel) {}
            Button("Créer") {
                let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                if let deck = try? review.store.addDeck(named: name) {
                    review.settings.defaultDeckId = deck.id
                    review.refresh()
                } else {
                    message = String(localized: "Un paquet porte déjà ce nom.")
                }
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func export(apkg: Bool) {
        guard let template = review.defaultTemplate, let templateId = template.id else { return }
        let deckName = review.decks.first { $0.id == review.defaultDeckId }?.name ?? "Kyōkasho"
        let cards = ((try? review.store.cards(limit: 1_000_000)) ?? []).filter { $0.templateId == templateId }
        guard !cards.isEmpty else { message = String(localized: "Aucune carte à exporter."); return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Kyokasho.\(apkg ? "apkg" : "csv")")
        do {
            if apkg {
                try AnkiExport.apkg(cards: cards, template: template, deckName: deckName,
                                    mediaRoot: review.store.mediaRoot, to: url)
            } else {
                try? FileManager.default.removeItem(at: url)
                try AnkiExport.csv(cards: cards, template: template, deckName: deckName)
                    .write(to: url, atomically: true, encoding: .utf8)
            }
            exportURL = url
        } catch {
            message = String(localized: "Export impossible : \(error.localizedDescription)")
        }
    }
}

/// Éditeur du modèle : recto, verso, CSS, aperçu en direct sur une vraie carte (ou un exemple).
struct TemplateEditorView: View {
    @EnvironmentObject private var review: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @State var template: NoteTemplate
    @State private var side = 0
    @State private var showBack = false

    private var sample: [String: String] {
        if let id = template.id, let card = (try? review.store.cards(limit: 50))?.first(where: { $0.templateId == id }) {
            return card.fields
        }
        return ["Mot": "食べる", "Lecture": "たべる", "Furigana": "食[た]べる", "Sens": "<ol><li>manger</li></ol>",
                "Phrase": "パンを<b>食べた</b>。", "Accent": "[2]", "Source": String(localized: "Exemple · p. 1")]
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker("", selection: $side) {
                    Text("Recto").tag(0); Text("Verso").tag(1); Text("CSS").tag(2)
                }
                .pickerStyle(.segmented)
                TextEditor(text: side == 0 ? $template.front : side == 1 ? $template.back : $template.css)
                    .font(.system(size: 14, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: Atelier.corner(10)))
                if let error = template.validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(String(localized: "Champs : ") + template.fieldNames.map { "{{\($0)}}" }.joined(separator: " "))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            VStack(spacing: 8) {
                Toggle("Aperçu du verso", isOn: $showBack)
                let sides = template.render(sample)
                CardWebView(html: CardHTML.page(css: template.css, body: showBack ? sides.back : sides.front),
                            mediaRoot: review.store.mediaRoot)
                    .clipShape(RoundedRectangle(cornerRadius: Atelier.corner(10)))
            }
            .padding()
        }
        .navigationTitle(template.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    _ = try? review.store.save(template)
                    review.refresh()
                    dismiss()
                }
                .disabled(template.validationError != nil)
            }
        }
    }
}
