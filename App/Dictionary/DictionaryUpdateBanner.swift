// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Notification en haut de la bibliothèque, comme celle de la mise à jour de l'app : elle reste, y compris d'un
/// lancement à l'autre, jusqu'à la réponse de l'utilisateur. Une fenêtre d'alerte se perdait si les nouveautés
/// s'ouvraient au même moment (recette 1.4.0, essai 3.4).
struct DictionaryUpdateBanner: View {
    @ObservedObject private var service = DictionaryCatalogService.shared
    @EnvironmentObject private var dictionaries: DictionaryModel

    var body: some View {
        if service.working != nil {
            // Après « Mettre à jour » : la notification ne disparaît pas sans rien dire pendant l'import.
            HStack(spacing: 12) {
                ProgressView()
                Text("Mise à jour des dictionnaires…").font(.footnote).foregroundStyle(Atelier.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .atelierPanel(radius: 16)
            .padding(.horizontal, Atelier.gap).padding(.top, 8)
        } else if !service.offeredUpdates.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "character.book.closed.fill").font(Atelier.font(22)).foregroundStyle(Atelier.Tint.japanese)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dictionnaires à mettre à jour").font(Atelier.font(15, weight: .semibold))
                        .foregroundStyle(Atelier.textPrimary)
                    Text("Une nouvelle version est disponible : \(service.offeredNames(in: dictionaries).joined(separator: ", ")).")
                        .font(.footnote).foregroundStyle(Atelier.textSecondary).lineLimit(2)
                }
                Spacer()
                Button("Ignorer") { service.dismissOfferedUpdates() }.foregroundStyle(Atelier.textSecondary)
                Button("Mettre à jour") { service.installOfferedUpdates(model: dictionaries) }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .atelierPanel(radius: 16)
            .padding(.horizontal, Atelier.gap).padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
