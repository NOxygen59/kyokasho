// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI
import UIKit

/// Documents gardés en onglets, sur l'accueil. Un seul est chargé en mémoire à la fois (`ReaderTabsHost`) : les autres
/// ne sont qu'une entrée de liste, dont la croix retire l'onglet sans rien effacer. La position de lecture reste enregistrée.
struct OpenDocumentsStrip: View {
    var compact = false
    @EnvironmentObject private var model: AppModel

    private var documents: [LibraryDocument] {
        model.tabs.ids.compactMap { id in model.documents.first { $0.id == id } }
    }

    var body: some View {
        if !documents.isEmpty {
            if compact {
                HStack(spacing: 8) {
                    Label("Ouverts", systemImage: "rectangle.on.rectangle")
                        .font(Atelier.font(11, weight: .semibold))
                        .foregroundStyle(Atelier.textSecondary)
                        .fixedSize()
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 6) {
                            ForEach(documents) { CompactOpenDocument(document: $0) }
                        }
                    }
                    .frame(height: 44)
                }
            } else {
                legacyStrip
            }
        }
    }

    private var legacyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            AtelierLabel(String(localized: "Onglets ouverts"), tint: Atelier.Tint.read)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(documents) { document in chip(document) }
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

/// Une entrée d'accueil, indépendante de l'espace affiché. La miniature utilise le cache existant à petite taille.
private struct CompactOpenDocument: View {
    let document: LibraryDocument
    @EnvironmentObject private var model: AppModel
    @State private var cover: UIImage?

    private var kind: String {
        if document.isComicArchive { return "CBZ" }
        if document.isInMangaSpace { return String(localized: "Manga") }
        return document.category?.title ?? "PDF"
    }

    private var page: Int { min(max(0, document.lastPageIndex) + 1, max(1, document.pageCount)) }

    var body: some View {
        HStack(spacing: 0) {
            Button { model.openDocumentId = document.id } label: {
                HStack(spacing: 6) {
                    Group {
                        if let cover {
                            Image(uiImage: cover).resizable().scaledToFit()
                        } else {
                            Image(systemName: "doc").font(Atelier.font(12))
                        }
                    }
                    .frame(width: 20, height: 26)
                    .foregroundStyle(Atelier.textSecondary)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ui: document.title)
                            .font(Atelier.font(12, weight: .semibold))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .foregroundStyle(Atelier.textPrimary)
                        Text(verbatim: "\(kind) · \(page)/\(document.pageCount)")
                            .font(Atelier.font(10))
                            .lineLimit(1)
                            .foregroundStyle(Atelier.textSecondary)
                    }
                    .frame(width: 110, alignment: .leading)
                }
                .padding(.leading, 6)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: document.title))
            .accessibilityValue(Text("\(kind), page \(page) sur \(document.pageCount)"))
            Button { model.closeTab(document.id) } label: {
                Image(systemName: "xmark")
                    .font(Atelier.font(9, weight: .semibold))
                    .foregroundStyle(Atelier.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Fermer « \(document.title) »"))
        }
        .background(alignment: .center) {
            RoundedRectangle(cornerRadius: Atelier.corner(8))
                .fill(Atelier.surfaceHigh)
                .padding(.vertical, 4)
        }
        .onAppear {
            guard cover == nil else { return }
            model.thumbnails.thumbnail(documentId: document.id, fileURL: model.storage.url(for: document.id),
                                       page: 0, width: 64) { cover = $0 }
        }
    }
}
