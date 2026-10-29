// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Corbeille des documents : restaurer, supprimer définitivement (une confirmation), vider (deux confirmations).
/// Chaque ligne dit combien de jours il reste avant l'effacement automatique.
struct TrashView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var forever: LibraryDocument?
    @State private var emptyStep = 0

    var body: some View {
        NavigationStack {
            List {
                if model.trashedDocuments.isEmpty {
                    Text("La corbeille est vide.").foregroundStyle(.secondary)
                }
                ForEach(model.trashedDocuments) { document in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.richtext").foregroundStyle(Atelier.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.title).lineLimit(1)
                            Text(remaining(document)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restaurer") { model.restoreFromTrash(document) }
                            .buttonStyle(.bordered)
                    }
                    .swipeActions {
                        Button(role: .destructive) { forever = document } label: { Label("Supprimer", systemImage: "trash.slash") }
                        Button { model.restoreFromTrash(document) } label: { Label("Restaurer", systemImage: "arrow.uturn.backward") }
                            .tint(.green)
                    }
                    .contextMenu {
                        Button { model.restoreFromTrash(document) } label: { Label("Restaurer", systemImage: "arrow.uturn.backward") }
                        Button(role: .destructive) { forever = document } label: { Label("Supprimer définitivement", systemImage: "trash.slash") }
                    }
                }
            }
            .navigationTitle("Corbeille")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vider", role: .destructive) { emptyStep = 1 }
                        .disabled(model.trashedDocuments.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Un document reste 30 jours dans la corbeille, puis il est effacé de l'iPad.")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            }
            .alert("Supprimer définitivement « \(forever?.title ?? "") » ?",
                   isPresented: Binding(get: { forever != nil }, set: { if !$0 { forever = nil } })) {
                Button("Annuler", role: .cancel) {}
                Button("Supprimer", role: .destructive) { if let forever { model.deleteForever(forever) } }
            } message: {
                Text("Le PDF, ses notes, surlignages, dessins et le texte lu par l'OCR seront effacés de l'iPad. Impossible de revenir en arrière.")
            }
            .alert("Vider la corbeille ?", isPresented: Binding(get: { emptyStep == 1 }, set: { if !$0 && emptyStep == 1 { emptyStep = 0 } })) {
                Button("Annuler", role: .cancel) { emptyStep = 0 }
                Button("Continuer", role: .destructive) {
                    // La première alerte doit finir de se fermer, sinon iOS ignore la seconde.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { emptyStep = 2 }
                }
            } message: {
                Text("\(model.trashedDocuments.count) document(s) seront effacés de l'iPad.")
            }
            .alert("Effacer définitivement ?", isPresented: Binding(get: { emptyStep == 2 }, set: { if !$0 { emptyStep = 0 } })) {
                Button("Annuler", role: .cancel) { emptyStep = 0 }
                Button("Effacer tout", role: .destructive) { model.emptyTrash(); emptyStep = 0 }
            } message: {
                Text("Impossible de revenir en arrière.")
            }
        }
    }

    private func remaining(_ document: LibraryDocument) -> String {
        guard let days = model.trash.daysLeft(document.id) else { return "" }
        return days == 0 ? "Effacé au prochain lancement" : "Effacé dans \(days) jour\(days > 1 ? "s" : "")"
    }
}
