// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Rangée « Reprendre » de la nouvelle présentation de l'accueil (PLAN-REFONTE-001, E3) : livres ouverts dans un onglet,
/// puis livres en cours de l'espace affiché, trois au plus. Remplace la petite puce « Ouverts » ; ✕ ferme l'onglet
/// comme avant (`closeTab`) ou, pour un livre seulement en cours, le retire de Reprendre ; Reprendre rouvre le livre à sa
/// dernière page (`openDocumentId`).
struct ResumeRow: View {
    @EnvironmentObject private var model: AppModel
    let space: LibrarySpace

    /// Livres en cours retirés de Reprendre par leur ✕ (recette 1.6.4) : `id:page` séparés par des virgules. Un livre
    /// revient dès que sa page change (on l'a relu) ; rien d'autre n'est modifié (ni le livre, ni sa progression).
    static let dismissedKey = "library.resumeDismissed"

    static func dismissed(_ raw: String = UserDefaults.standard.string(forKey: dismissedKey) ?? "") -> [String: Int] {
        Dictionary(raw.split(separator: ",").compactMap { item -> (String, Int)? in
            let parts = item.split(separator: ":")
            guard parts.count == 2, let page = Int(parts[1]) else { return nil }
            return (String(parts[0]), page)
        }, uniquingKeysWith: { _, last in last })
    }

    /// Documents à reprendre : **tous** les onglets ouverts (les deux espaces, pour pouvoir les fermer d'ici comme
    /// avec l'ancien bandeau), puis les livres en cours de l'espace affiché jusqu'à `limit` cartes, sauf ceux retirés
    /// par ✕ à leur page actuelle.
    static func documents(tabs: [String], all: [LibraryDocument], manga: Bool, limit: Int = 3,
                          dismissed: [String: Int] = dismissed()) -> [LibraryDocument] {
        let open = tabs.compactMap { id in all.first { $0.id == id } }
        let inProgress = all.filter { doc in
            doc.isInMangaSpace == manga && !tabs.contains(doc.id)
                && doc.lastPageIndex > 0 && doc.lastPageIndex < doc.pageCount - 1
                && dismissed[doc.id] != doc.lastPageIndex
        }
        return open + inProgress.prefix(max(0, limit - open.count))
    }

    @AppStorage(ResumeRow.dismissedKey) private var dismissedRaw = ""

    private var items: [LibraryDocument] {
        Self.documents(tabs: model.tabs.ids, all: model.documents, manga: space == .manga, dismissed: Self.dismissed(dismissedRaw))
    }

    /// ✕ d'une carte : ferme l'onglet d'un livre ouvert ; retire de Reprendre un livre seulement en cours.
    private func remove(_ document: LibraryDocument) {
        if model.tabs.ids.contains(document.id) { model.closeTab(document.id); return }
        var all = Self.dismissed(dismissedRaw).filter { id, _ in model.documents.contains { $0.id == id } }
        all[document.id] = document.lastPageIndex
        dismissedRaw = all.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ",")
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Reprendre").font(Atelier.font(17, weight: .bold)).foregroundStyle(Atelier.textPrimary)
                    Text("ouverts et en cours").font(Atelier.font(13)).foregroundStyle(Atelier.textSecondary)
                }
                // Défile au-delà de trois cartes (beaucoup d'onglets ouverts).
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(items) { document in
                            ResumeCard(document: document, isOpen: model.tabs.ids.contains(document.id),
                                       resume: { model.openDocumentId = document.id },
                                       close: { remove(document) })
                                .frame(width: 330)
                        }
                    }
                    .padding(.vertical, 6).padding(.horizontal, 2)
                }
            }
        }
    }
}

private struct ResumeCard: View {
    @EnvironmentObject private var model: AppModel
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
                    Text("Ouvert").font(Atelier.font(11, weight: .bold)).textCase(.uppercase)
                        .foregroundStyle(NewLayoutInk.accent)
                }
                Text(document.title).font(Atelier.font(15, weight: .semibold)).lineLimit(2)
                    .foregroundStyle(Atelier.textPrimary)
                Text(verbatim: "p. \(document.pageLabel(document.lastPageIndex)) / \(document.pageLabel(document.pageCount - 1))")
                    .font(Atelier.font(12).monospacedDigit()).foregroundStyle(Atelier.textSecondary)
                ProgressView(value: progress).tint(NewLayoutInk.accent)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    NewLayoutPillButton(icon: nil, title: String(localized: "Reprendre"), active: true, selectable: false, action: resume)
                        .accessibilityLabel(Text("Reprendre « \(document.title) »"))
                    Spacer(minLength: 0)
                    // ✕ sur chaque carte, à côté de Reprendre (recette 1.6.4, point 3).
                    Button(action: close) {
                        Image(systemName: "xmark").font(Atelier.font(12, weight: .bold))
                            .frame(width: 32, height: 32).foregroundStyle(Atelier.textSecondary)
                            .background(Atelier.surfaceHigh, in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel(isOpen ? Text("Fermer l'onglet") : Text("Retirer de Reprendre"))
                }
            }
        }
        .padding(12)
        // Hauteur naturelle : dans la rangée qui défile, la carte prenait toute la hauteur offerte (grand vide).
        .fixedSize(horizontal: false, vertical: true)
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
