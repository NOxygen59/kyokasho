// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI
import UIKit

/// Documents gardés en onglets, sur l'accueil. Un seul est chargé en mémoire à la fois (`ReaderTabsHost`) : les autres
/// ne sont qu'une entrée de liste, dont la croix retire l'onglet sans rien effacer. La position de lecture reste enregistrée.
struct OpenDocumentsStrip: View {
    var compact = false
    let palette: Theme
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
                        .foregroundStyle(palette.secondaryInk)
                        .fixedSize()
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(documents) { CompactOpenDocument(document: $0, palette: palette) }
                        }
                    }
                    .frame(height: CompactOpenDocument.height)
                }
            } else {
                legacyStrip
            }
        }
    }

    private var legacyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            AtelierLabel(String(localized: "Onglets ouverts"), tint: palette.read)
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
                    .foregroundStyle(palette.ink.opacity(0.96))
            }
            .buttonStyle(.plain)
            Button { model.closeTab(document.id) } label: {
                Image(systemName: "xmark").font(Atelier.font(11, weight: .bold))
                    .foregroundStyle(palette.secondaryInk)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Fermer « \(document.title) »"))
        }
        .background(palette.surfaceHigh, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.separator, lineWidth: Atelier.border(1)))
    }
}

/// Une entrée d'accueil, indépendante de l'espace affiché. La miniature utilise le cache existant à petite taille.
private struct CompactOpenDocument: View {
    let document: LibraryDocument
    let palette: Theme
    @EnvironmentObject private var model: AppModel
    @State private var cover: UIImage?

    private var kind: String {
        if document.isComicArchive { return "CBZ" }
        if document.isInMangaSpace { return String(localized: "Manga") }
        return document.category?.title ?? "PDF"
    }

    private var page: String { document.pageLabel(min(max(0, document.lastPageIndex), max(0, document.pageCount - 1))) }
    private var finalPage: String { document.pageLabel(max(0, document.pageCount - 1)) }

    /// Hauteur de l'entrée : deux lignes de titre et la ligne d'infos tiennent dans le rectangle, avec sa marge
    /// (recette de la 1.5.0 : le titre et les infos débordaient de l'ancienne entrée de 44 pt, à largeur fixe).
    static let height: CGFloat = 58

    var body: some View {
        HStack(spacing: 8) {
            Button { model.openDocumentId = document.id } label: {
                HStack(spacing: 8) {
                    Group {
                        if let cover {
                            Image(uiImage: cover).resizable().scaledToFill()
                        } else {
                            Image(systemName: "doc").font(Atelier.font(13))
                        }
                    }
                    .frame(width: 30, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: Atelier.corner(3)))
                    .foregroundStyle(palette.secondaryInk)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ui: document.title)
                            .font(Atelier.font(12, weight: .semibold))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(palette.ink.opacity(0.96))
                        Text(verbatim: "\(kind) · p. \(page)/\(finalPage)")
                            .font(Atelier.font(10))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(palette.secondaryInk)
                    }
                    .frame(minWidth: 130, maxWidth: 210, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: document.title))
            .accessibilityValue(Text("\(kind), page \(page) sur \(finalPage)"))
            Button { model.closeTab(document.id) } label: {
                Image(systemName: "xmark")
                    .font(Atelier.font(10, weight: .semibold))
                    .foregroundStyle(palette.secondaryInk)
                    .frame(width: 30, height: 30)
                    .background(palette.surface.opacity(0.6), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Fermer « \(document.title) »"))
        }
        .padding(.leading, 7)
        .padding(.vertical, 5)
        .frame(height: Self.height)
        .background(palette.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.corner(10)))
        .overlay(RoundedRectangle(cornerRadius: Atelier.corner(10)).strokeBorder(palette.separator, lineWidth: Atelier.border(1)))
        .clipShape(RoundedRectangle(cornerRadius: Atelier.corner(10)))
        .onAppear {
            guard cover == nil else { return }
            model.thumbnails.thumbnail(documentId: document.id, fileURL: model.storage.url(for: document.id),
                                       page: 0, width: 64) { cover = $0 }
        }
    }
}
