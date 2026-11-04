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
            // Confirmations dans une fenêtre centrée qui change d'étape sur place : les alertes enchaînées d'iOS
            // demandaient une pause entre les deux (recette 1.3.2 (66), point 10 : trop lent).
            .overlay { confirmation }
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: emptyStep)
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: forever)
        }
    }

    @ViewBuilder
    private var confirmation: some View {
        if let doc = forever {
            card(title: String(localized: "Supprimer définitivement « \(doc.title) » ?"),
                 message: String(localized: "Le PDF, ses notes, surlignages, dessins et le texte lu par l'OCR seront effacés de l'iPad. Impossible de revenir en arrière."),
                 confirm: String(localized: "Supprimer"), cancel: { forever = nil }) { model.deleteForever(doc); forever = nil }
        } else if emptyStep == 1 {
            card(title: String(localized: "Vider la corbeille ?"), message: String(localized: "\(model.trashedDocuments.count) document(s) seront effacés de l'iPad."),
                 confirm: String(localized: "Continuer"), cancel: { emptyStep = 0 }) { emptyStep = 2 }
        } else if emptyStep == 2 {
            card(title: String(localized: "Effacer définitivement ?"), message: String(localized: "Dernière confirmation : impossible de revenir en arrière."),
                 confirm: String(localized: "Effacer tout"), cancel: { emptyStep = 0 }) { model.emptyTrash(); emptyStep = 0 }
        }
    }

    private func card(title: String, message: String, confirm: String, cancel: @escaping () -> Void,
                      action: @escaping () -> Void) -> some View {
        ZStack {
            Atelier.scrim.opacity(0.35).ignoresSafeArea().onTapGesture(perform: cancel)
            VStack(spacing: 12) {
                Image(systemName: "trash").font(.title2).foregroundStyle(.red)
                Text(title).font(.headline).multilineTextAlignment(.center)
                Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Annuler", action: cancel).buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                    Button(confirm, role: .destructive, action: action)
                        .buttonStyle(.borderedProminent).tint(.red).keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(Atelier.material(.regularMaterial), in: RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous))
            .atelierShadow(opacity: 0.3, radius: 16, y: 6)
            .padding(16)
            .id(title)   // nouvelle étape : la carte change d'un fondu, sans fermer ni rouvrir
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
        .accessibilityAddTraits(.isModal)
    }

    private func remaining(_ document: LibraryDocument) -> String {
        guard let days = model.trash.daysLeft(document.id) else { return "" }
        return days == 0 ? String(localized: "Effacé au prochain lancement") : String(localized: "Effacé dans \(days) jour\(days > 1 ? "s" : "")")
    }
}
