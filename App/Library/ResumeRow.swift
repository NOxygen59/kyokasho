// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Rangée « Reprendre » de la nouvelle présentation de l'accueil (PLAN-REFONTE-001, E3) : livres ouverts dans un onglet,
/// puis livres en cours de l'espace affiché, trois au plus. Remplace la petite puce « Ouverts » ; ✕ ferme l'onglet
/// comme avant (`closeTab`), Reprendre rouvre le livre à sa dernière page (`openDocumentId`).
struct ResumeRow: View {
    @EnvironmentObject private var model: AppModel
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1
    let space: LibrarySpace

    /// Documents à reprendre : **tous** les onglets ouverts (les deux espaces, pour pouvoir les fermer d'ici comme
    /// avec l'ancien bandeau), puis les livres en cours de l'espace affiché jusqu'à `limit` cartes.
    static func documents(tabs: [String], all: [LibraryDocument], manga: Bool, limit: Int = 3) -> [LibraryDocument] {
        let open = tabs.compactMap { id in all.first { $0.id == id } }
        let inProgress = all.filter { doc in
            doc.isInMangaSpace == manga && !tabs.contains(doc.id)
                && doc.lastPageIndex > 0 && doc.lastPageIndex < doc.pageCount - 1
        }
        return open + inProgress.prefix(max(0, limit - open.count))
    }

    private var items: [LibraryDocument] {
        Self.documents(tabs: model.tabs.ids, all: model.documents, manga: space == .manga)
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        title
                        subtitle
                    }
                    .fixedSize()
                    VStack(alignment: .leading, spacing: 2) {
                        title
                        subtitle
                    }
                }
                // Défile au-delà de trois cartes (beaucoup d'onglets ouverts).
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(items) { document in
                            ResumeCard(document: document, isOpen: model.tabs.ids.contains(document.id),
                                       resume: { model.openDocumentId = document.id },
                                       close: { model.closeTab(document.id) })
                                .frame(width: 330)
                        }
                    }
                    .padding(.vertical, 6).padding(.horizontal, 2)
                }
            }
        }
    }

    private var title: some View {
        Text("Reprendre").font(Atelier.font(17 * typeScale, weight: .bold)).foregroundStyle(Atelier.textPrimary)
    }

    private var subtitle: some View {
        Text("ouverts et en cours").font(Atelier.font(13 * typeScale)).foregroundStyle(Atelier.textSecondary)
    }
}

private struct ResumeCard: View {
    @EnvironmentObject private var model: AppModel
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1
    let document: LibraryDocument
    let isOpen: Bool
    let resume: () -> Void
    let close: () -> Void
    @State private var image: UIImage?

    private var progress: Double {
        Double(min(document.lastPageIndex + 1, document.pageCount)) / Double(max(document.pageCount, 1))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: Atelier.corner(10), style: .continuous).fill(Atelier.surfaceHigh)
                .frame(width: 84, height: 112)
                .overlay {
                    if let image { Image(uiImage: image).resizable().scaledToFit() }
                }
                .clipShape(RoundedRectangle(cornerRadius: Atelier.corner(10), style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                if isOpen {
                    Text("Ouvert").font(Atelier.font(11 * typeScale, weight: .bold)).textCase(.uppercase)
                        .foregroundStyle(NewLayoutInk.accent)
                }
                Text(document.title).font(Atelier.font(15 * typeScale, weight: .semibold)).lineLimit(typeScale > 1.2 ? nil : 2)
                    .foregroundStyle(Atelier.textPrimary)
                Text(verbatim: "p. \(document.pageLabel(document.lastPageIndex)) / \(document.pageLabel(document.pageCount - 1))")
                    .font(Atelier.font(12 * typeScale).monospacedDigit()).foregroundStyle(Atelier.textSecondary)
                ProgressView(value: progress).tint(NewLayoutInk.accent)
                NewLayoutPillButton(icon: nil, title: String(localized: "Reprendre"), active: true, selectable: false, action: resume)
                    .accessibilityLabel(Text("Reprendre « \(document.title) »"))
            }
            if isOpen {
                Button(action: close) {
                    Image(systemName: "xmark").font(Atelier.font(12, weight: .bold))
                        .frame(width: 32, height: 32).foregroundStyle(Atelier.textSecondary)
                        .background(Atelier.surfaceHigh, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Fermer l'onglet")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .newLayoutBar(radius: Atelier.corner(20))
        .onAppear(perform: load)
        .onChange(of: document.id) { _ in load() }
    }

    private func load() {
        if let cached = model.thumbnails.cached(documentId: document.id, page: 0, width: 400) {
            image = cached
            return
        }
        model.thumbnails.thumbnail(documentId: document.id, fileURL: model.storage.url(for: document.id),
                                   page: 0, width: 400) { image = $0 }
    }
}
