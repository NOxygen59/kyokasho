// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReviewKit
import SwiftUI

/// Liste des cartes : recherche, filtre par paquet, édition, suspension, suppression, statistiques.
struct CardBrowserView: View {
    @EnvironmentObject private var review: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var deckId: Int64?
    @State private var cards: [StudyCard] = []
    @State private var stats: ReviewStore.Stats?

    var body: some View {
        NavigationStack {
            List {
                if let stats {
                    Section {
                        HStack(spacing: 0) {
                            stat("\(stats.totalCards)", String(localized: "cartes"))
                            stat("\(stats.matureCards)", String(localized: "mûres (≥ 21 j)"))
                            stat("\(stats.reviewsPerDay.values.reduce(0, +))", String(localized: "réponses / 30 j"))
                            stat(stats.retention.map { "\(Int(($0 * 100).rounded())) %" } ?? "—", String(localized: "retenues"))
                        }
                    }
                }
                Section("\(cards.count) carte\(cards.count > 1 ? "s" : "")") {
                    ForEach(cards) { card in
                        NavigationLink {
                            CardEditor(card: card) { reload() }
                        } label: {
                            row(card)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: String(localized: "Chercher dans les cartes"))
            .navigationTitle("Cartes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("OK") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Picker("Paquet", selection: $deckId) {
                        Text("Tous les paquets").tag(Int64?.none)
                        ForEach(review.decks) { deck in Text(deck.name).tag(deck.id) }
                    }
                }
            }
            .onAppear(perform: reload)
            // Recherche tapée : on attend une courte pause avant d'interroger la base.
            .task(id: query) {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if !Task.isCancelled { reload() }
            }
            .onChange(of: deckId) { _ in reload() }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.monospacedDigit().bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ card: StudyCard) -> some View {
        let names = review.templates.first { $0.id == card.templateId }?.fieldNames ?? []
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title(fieldNames: names)).font(.custom("HiraginoSans-W6", size: 17))
                Text(card.suspended ? String(localized: "Suspendue") : card.state.label)
                    .font(.caption).foregroundStyle(card.suspended ? .orange : .secondary)
            }
            Spacer()
            if card.state != .new, !card.suspended {
                Text(card.due.formatted(date: .abbreviated, time: .omitted)).font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reload() {
        cards = (try? review.store.cards(deckId: deckId, query: query)) ?? []
        stats = try? review.store.stats(settings: review.settings)
        review.refresh()
    }
}

/// Édition d'une carte : un champ par zone de texte, suspendre, supprimer.
struct CardEditor: View {
    @EnvironmentObject private var review: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @State var card: StudyCard
    var onChange: () -> Void
    @State private var confirmDelete = false
    @State private var saveError: String?

    private var fieldNames: [String] {
        let names = review.templates.first { $0.id == card.templateId }?.fieldNames ?? []
        return names + card.fields.keys.filter { !names.contains($0) }.sorted()
    }

    var body: some View {
        Form {
            ForEach(fieldNames, id: \.self) { name in
                Section(name) {
                    TextEditor(text: Binding(get: { card.fields[name] ?? "" }, set: { card.fields[name] = $0 }))
                        .font(.system(size: 15, design: name == "Sens" || name == "Image" ? .monospaced : .default))
                        .frame(minHeight: 44)
                }
            }
            Section {
                Toggle("Suspendue (ne revient plus en révision)", isOn: $card.suspended)
                LabeledContent("État", value: card.state.label)
                LabeledContent("Révisions", value: String(localized: "\(card.reps) · oublis \(card.lapses)"))
            }
            Section {
                Button("Supprimer la carte", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(card.title(fieldNames: fieldNames))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    // PLAN-CARTES-001 (DEC-CA-07 = A) : mot et lecture modifiables ; la clé anti-doublon suit, l'historique
                    // de révision reste. Une autre carte pour le même mot : refus, rien n'est enregistré.
                    let oldKey = card.key
                    do {
                        let saved = try review.store.saveEdited(card)
                        if saved.key != oldKey {
                            review.forgetKey(oldKey)
                            review.loadKeys([saved.key])
                        }
                        onChange()
                        dismiss()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
            }
        }
        .alert("Carte non enregistrée", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(saveError ?? "") }
        .confirmationDialog("Supprimer cette carte et son historique ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let id = card.id { try? review.store.deleteCards([id]) }
                review.forgetKey(card.key)
                onChange()
                dismiss()
            }
        }
    }
}
