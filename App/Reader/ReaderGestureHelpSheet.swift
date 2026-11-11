// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Feuille « Gestes de lecture » (FEAT-AIDE) : ouverte par « Aide : gestes de lecture » du menu « … » du lecteur.
///
/// Affichage seul. Le contenu vient de `ReaderGestureHelp.items` (testé sur Mac) : cette vue ne connaît aucun geste et
/// n'en change aucun. Aucun état gardé, aucune animation ; les couleurs sont celles du thème en cours (`Atelier`), la
/// feuille prend le mode clair ou sombre du lecteur par le conteneur commun des feuilles de `ReaderScreen`.
struct ReaderGestureHelpSheet: View {
    let context: ReaderGestureHelp.Context
    var close: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ce que tu peux faire avec le doigt sur la page de ce document.")
                        .font(.subheadline).foregroundStyle(Atelier.textSecondary)
                        .padding(.bottom, 4)
                    ForEach(ReaderGestureHelp.items(context)) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.icon)
                                .font(Atelier.font(20, weight: .medium))
                                .foregroundStyle(Atelier.Tint.read)
                                .frame(width: 34, height: 34)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: item.title).font(.headline).foregroundStyle(Atelier.textPrimary)
                                Text(verbatim: item.detail).font(.subheadline).foregroundStyle(Atelier.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Atelier.surfaceHigh.opacity(0.65),
                                    in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
                        // VoiceOver lit un geste d'un trait : son nom, puis comment le faire.
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(Atelier.gap)
            }
            .background(Atelier.canvas)
            .navigationTitle("Gestes de lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { close() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
