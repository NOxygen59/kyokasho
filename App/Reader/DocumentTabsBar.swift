// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Lecteur de l'onglet affiché (#16). `.id` : changer d'onglet crée un nouveau lecteur (l'ancien se ferme et rend sa
/// mémoire, sa page est gardée) ; un seul document est chargé à la fois.
struct ReaderTabsHost: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let id = model.openDocumentId, let document = model.documents.first(where: { $0.id == id }) {
            ReaderScreen(document: document, model: model).id(document.id)
        }
    }
}

/// Onglets des documents ouverts, en haut du lecteur (RET-013, #16) : barre défilable, × pour fermer, + pour ouvrir
/// un autre document. À partir de ``DocumentTabs/warningCount`` onglets, une bulle conseille de surveiller la mémoire.
struct DocumentTabsBar: View {
    let current: String
    @EnvironmentObject private var model: AppModel
    @AppStorage(ResourceMonitor.enabledKey) private var monitorEnabled = false
    @AppStorage(ResourceMonitor.shownKey) private var monitorShown = false

    private var openDocuments: [LibraryDocument] {
        model.tabs.ids.compactMap { id in model.documents.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(openDocuments) { document in tab(document).id(document.id) }
                        }
                    }
                    // Hauteur du contenu seulement : sans elle, la zone défilante pouvait s'étirer en hauteur.
                    .fixedSize(horizontal: false, vertical: true)
                    .onAppear { proxy.scrollTo(current) }
                    .onChange(of: current) { id in withAnimation { proxy.scrollTo(id) } }
                }
                Menu {
                    ForEach(model.documents.filter { !model.tabs.ids.contains($0.id) }) { document in
                        Button(document.title) { model.openDocumentId = document.id }
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .atelierPanel(radius: 15)
                }
                .accessibilityLabel("Ouvrir un autre document dans un onglet")
            }
            if model.tabs.showsMemoryWarning { memoryBubble }
        }
    }

    /// Toute la pastille est la zone de toucher (recette 1.3.2 (62), L6 : toucher le titre seul ne faisait rien) ;
    /// le × a sa propre zone, prioritaire.
    private func tab(_ document: LibraryDocument) -> some View {
        let selected = document.id == current
        return HStack(spacing: 6) {
            Text(document.title).lineLimit(1).frame(maxWidth: 180)
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { close(document) })
                .accessibilityLabel("Fermer l'onglet \(document.title)")
                .accessibilityAddTraits(.isButton)
        }
        .font(.system(size: 13, weight: selected ? .semibold : .regular))
        .foregroundStyle(selected ? Color.black.opacity(0.85) : Atelier.textPrimary)
        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 3)
        .background(selected ? AnyShapeStyle(Atelier.Tint.read) : AnyShapeStyle(Atelier.surface.opacity(0.85)), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { select(document) }
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private func select(_ document: LibraryDocument) {
        guard document.id != current else { return }
        Diagnostics.log("onglets : passage à « \(document.title) »", "lecteur")
        model.openDocumentId = document.id
    }

    private func close(_ document: LibraryDocument) {
        Diagnostics.log("onglets : fermeture de « \(document.title) »", "lecteur")
        model.closeTab(document.id)
    }

    /// Bulle discrète, façon notification ; « Moniteur » l'affiche directement.
    private var memoryBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "memorychip").foregroundStyle(.orange)
            Text("\(model.tabs.ids.count) documents ouverts : la mémoire peut se remplir, garde un œil sur le moniteur.")
                .font(.system(size: 12)).foregroundStyle(Atelier.textPrimary)
            if !(monitorEnabled && monitorShown) {
                Button("Moniteur") { monitorEnabled = true; monitorShown = true }
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .atelierPanel(radius: 14)
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity)
    }
}
