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
                // Barre en UIKit (recette 1.3.2 (63), 3 et 4) : dans une zone défilante SwiftUI, ni les boutons ni les
                // gestes des pastilles ne recevaient le toucher, alors que le + (bouton UIKit) marchait.
                TabStripView(tabs: openDocuments.map { .init(id: $0.id, title: $0.title) }, current: current,
                             onSelect: { id in if let d = openDocuments.first(where: { $0.id == id }) { select(d) } },
                             onClose: { id in if let d = openDocuments.first(where: { $0.id == id }) { close(d) } })
                    .frame(height: 32)
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

/// Pastilles des onglets en UIKit : `UIScrollView` horizontal et `UIButton` (titre et ×), mis à jour sans tout
/// recréer. Couleurs du thème (Atelier) ; l'onglet affiché est rempli de la teinte de lecture.
struct TabStripView: UIViewRepresentable {
    struct Tab: Equatable { let id: String; let title: String }
    let tabs: [Tab]
    let current: String
    var onSelect: (String) -> Void
    var onClose: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.stack = stack
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let c = context.coordinator
        c.onSelect = onSelect
        c.onClose = onClose
        guard c.shown != tabs || c.current != current, let stack = c.stack else { return }
        c.shown = tabs
        c.current = current
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tab in tabs { stack.addArrangedSubview(c.pill(tab, selected: tab.id == current)) }
        // Onglet affiché rendu visible (barre défilée jusqu'à lui).
        DispatchQueue.main.async {
            if let index = tabs.firstIndex(where: { $0.id == current }), stack.arrangedSubviews.indices.contains(index) {
                scroll.scrollRectToVisible(stack.arrangedSubviews[index].frame.insetBy(dx: -12, dy: 0), animated: true)
            }
        }
    }

    final class Coordinator: NSObject {
        weak var stack: UIStackView?
        var shown: [Tab] = []
        var current = ""
        var onSelect: (String) -> Void = { _ in }
        var onClose: (String) -> Void = { _ in }

        func pill(_ tab: Tab, selected: Bool) -> UIView {
            let ink = selected ? UIColor.black.withAlphaComponent(0.85) : UIColor(Atelier.textPrimary)
            var config = UIButton.Configuration.plain()
            config.title = tab.title
            config.titleLineBreakMode = .byTruncatingTail
            config.baseForegroundColor = ink
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 4)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
                var a = attrs
                a.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
                return a
            }
            let title = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.onSelect(tab.id) })
            title.widthAnchor.constraint(lessThanOrEqualToConstant: 190).isActive = true
            title.accessibilityLabel = tab.title
            title.accessibilityTraits = selected ? [.button, .selected] : .button

            var closeConfig = UIButton.Configuration.plain()
            closeConfig.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))
            closeConfig.baseForegroundColor = ink
            closeConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 10)
            let close = UIButton(configuration: closeConfig, primaryAction: UIAction { [weak self] _ in self?.onClose(tab.id) })
            close.accessibilityLabel = "Fermer l'onglet \(tab.title)"

            let row = UIStackView(arrangedSubviews: [title, close])
            row.axis = .horizontal
            row.spacing = 0
            row.backgroundColor = selected ? UIColor(Atelier.Tint.read) : UIColor(Atelier.surface).withAlphaComponent(0.85)
            row.layer.cornerRadius = 15
            row.layer.cornerCurve = .continuous
            row.clipsToBounds = true
            row.heightAnchor.constraint(equalToConstant: 30).isActive = true
            return row
        }
    }
}
