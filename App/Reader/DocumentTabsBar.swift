// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Lecteur de l'onglet affiché (#16). `.id` : changer d'onglet crée un nouveau lecteur (l'ancien se ferme et rend sa
/// mémoire, sa page est gardée) ; un seul document est chargé à la fois.
struct ReaderTabsHost: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bulle mémoire façon notification (recette 1.3.2 (62), L8) : glisse du haut, repart après 3 s.
    @State private var notice = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            if let id = model.openDocumentId, let document = model.documents.first(where: { $0.id == id }) {
                ReaderScreen(document: document, model: model).id(document.id)
            }
            if notice {
                MemoryNotice(count: model.tabs.ids.count)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .onChange(of: model.tabs.ids.count) { [old = model.tabs.ids.count] count in
            // Seulement quand un onglet s'ajoute au-delà du seuil, pas à la fermeture d'un onglet.
            if count >= DocumentTabs.warningCount, count > old { showNotice() }
        }
        // Lecteur ouvert depuis la bibliothèque avec déjà assez d'onglets : prévenir une fois à l'ouverture.
        .onAppear { if model.tabs.showsMemoryWarning { showNotice() } }
        .onDisappear { hideTask?.cancel() }
    }

    private func showNotice() {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { notice = true }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { notice = false }
        }
    }
}

/// Notification de mémoire : « N documents ouverts… », avec un bouton qui affiche le moniteur.
private struct MemoryNotice: View {
    let count: Int
    @AppStorage(ResourceMonitor.enabledKey) private var monitorEnabled = false
    @AppStorage(ResourceMonitor.shownKey) private var monitorShown = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "memorychip").foregroundStyle(.orange)
            Text("\(count) documents ouverts : la mémoire peut se remplir, garde un œil sur le moniteur.")
                .font(.system(size: 13)).foregroundStyle(Atelier.textPrimary)
            if !(monitorEnabled && monitorShown) {
                Button("Moniteur") { monitorEnabled = true; monitorShown = true }
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .frame(maxWidth: 560)
    }
}

/// Onglets des documents ouverts, en haut du lecteur (RET-013, #16) : barre défilable, × pour fermer, + pour ouvrir
/// un autre document. À partir de ``DocumentTabs/warningCount`` onglets, `ReaderTabsHost` montre une notification
/// qui conseille de surveiller la mémoire.
struct DocumentTabsBar: View {
    let current: String
    @EnvironmentObject private var model: AppModel
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
}
