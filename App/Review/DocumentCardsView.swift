// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import ReviewKit
import SwiftUI

/// « Cartes de ce document » (PLAN-CARTES-001, étape E1, plan approuvé par NOxygen59 le 11/11/2026) : toutes les cartes
/// créées depuis un livre, rangées par page, avec recherche ; toucher une carte ouvre l'éditeur habituel (`CardEditor` :
/// modifier, suspendre, supprimer) ; « Exporter en Anki » reprend l'export par document existant (DEC-CA-05 = A).
/// Ouvert depuis l'accueil (appui long sur le livre) et depuis le lecteur (menu « … ») — DEC-CA-01.
///
/// Une carte n'existe qu'une fois par mot (DEC-CA-03) : un mot de ce livre déjà carté depuis un autre livre n'apparaît
/// pas ici ; la création depuis une page l'indique (« déjà en carte »).
struct DocumentCardsView: View {
    @EnvironmentObject private var review: ReviewModel
    @Environment(\.dismiss) private var dismiss
    let document: LibraryDocument
    /// Export Anki du document (feuille d'export existante), fourni par l'appelant ; `nil` : pas de bouton.
    var onExport: (() -> Void)?
    @State private var query = ""
    @State private var cards: [StudyCard] = []
    @State private var loaded = false

    /// Cartes groupées par page (ordre de la base : page puis date de création).
    private var pages: [(page: Int?, cards: [StudyCard])] {
        var result: [(page: Int?, cards: [StudyCard])] = []
        for card in cards {
            if let last = result.last, last.page == card.sourcePage {
                result[result.count - 1].cards.append(card)
            } else {
                result.append((card.sourcePage, [card]))
            }
        }
        return result
    }

    private var dueCount: Int {
        let now = Date()
        return cards.filter { !$0.suspended && ($0.state == .new || $0.due <= now) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(String(localized: "Cartes"), value: "\(cards.count)")
                    // Revue DeepSeek (n°5) : « maintenant », pas « aujourd'hui » (la pastille de révision compte autrement).
                    LabeledContent(String(localized: "À réviser maintenant (nouvelles comprises)"), value: "\(dueCount)")
                }
                if loaded && cards.isEmpty {
                    Text(query.isEmpty
                         ? String(localized: "Aucune carte pour ce document. Dans le lecteur : menu « … » → Cette page → « Créer des cartes de cette page », ou ＋ dans la fiche d'un mot.")
                         : String(localized: "Aucune carte ne correspond à la recherche."))
                        .foregroundStyle(.secondary)
                }
                ForEach(pages, id: \.page) { group in
                    Section(group.page.map { String(localized: "Page \(document.pageLabel($0))") } ?? String(localized: "Sans page")) {
                        ForEach(group.cards) { card in
                            NavigationLink {
                                CardEditor(card: card) { reload() }
                            } label: {
                                row(card)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: String(localized: "Chercher dans les cartes de ce document"))
            .navigationTitle(String(localized: "Cartes · \(document.title)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("OK") { dismiss() } }
                if let onExport, !cards.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button { onExport() } label: { Label("Exporter en Anki", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            // Un seul chargement (revue DeepSeek n°6) : tout de suite à l'ouverture, puis après une courte pause de frappe.
            .task(id: query) {
                if loaded { try? await Task.sleep(nanoseconds: 250_000_000) }
                if !Task.isCancelled { reload() }
            }
        }
    }

    private func row(_ card: StudyCard) -> some View {
        let names = review.templates.first { $0.id == card.templateId }?.fieldNames ?? []
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title(fieldNames: names)).font(.custom("HiraginoSans-W6", size: 17))
                let meaning = CardTemplate.oneLine(card.fields["Sens"] ?? "")
                if !meaning.isEmpty {
                    Text(meaning).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(card.suspended ? String(localized: "Suspendue") : card.state.label)
                .font(.caption).foregroundStyle(card.suspended ? .orange : .secondary)
        }
    }

    private func reload() {
        cards = (try? review.store.cards(sourceDocumentId: document.id, query: query)) ?? []
        loaded = true
        review.refresh()
    }
}
