// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Documents gardés en onglets, sur l'accueil. Un seul est chargé en mémoire à la fois (`ReaderTabsHost`) : les autres
/// ne sont qu'une entrée de liste, dont la croix retire l'onglet sans rien effacer. La position de lecture reste enregistrée.
struct OpenDocumentsStrip: View {
    @EnvironmentObject private var model: AppModel

    private var documents: [LibraryDocument] {
        model.tabs.ids.compactMap { id in model.documents.first { $0.id == id } }
    }

    var body: some View {
        if !documents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                AtelierLabel(String(localized: "Onglets ouverts"), tint: Atelier.Tint.read)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(documents) { document in chip(document) }
                    }
                }
            }
        }
    }

    private func chip(_ document: LibraryDocument) -> some View {
        HStack(spacing: 2) {
            Button { model.openDocumentId = document.id } label: {
                Text(document.title).font(Atelier.font(13, weight: .medium)).lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
                    .padding(.leading, 12).padding(.vertical, 8)
                    .foregroundStyle(Atelier.textPrimary)
            }
            .buttonStyle(.plain)
            Button { model.closeTab(document.id) } label: {
                Image(systemName: "xmark").font(Atelier.font(11, weight: .bold))
                    .foregroundStyle(Atelier.textSecondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Fermer « \(document.title) »"))
        }
        .background(Atelier.surfaceHigh, in: Capsule())
        .overlay(Capsule().strokeBorder(Atelier.hairline, lineWidth: Atelier.border(1)))
    }
}
