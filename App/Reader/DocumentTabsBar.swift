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
                // Le calque gère le fondu d'entrée ; le changement d'onglet ne doit pas le rejouer.
                ReaderScreen(document: document, model: model).id(document.id)
                    .transition(.identity)
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
        // Le diagnostic a un ancrage commun avec la bibliothèque, au-dessus de ce rappel.
        .safeAreaInset(edge: .top, spacing: 0) {
            // Rappel de luminosité (11/11/2026) : dans le lecteur seulement, c'est là que l'écran coûte.
            BrightnessReminderBanner()
        }
        // Lecteur ouvert depuis la bibliothèque avec déjà assez d'onglets : prévenir une fois à l'ouverture.
        .onAppear {
            Diagnostics.log("lecteur affiché", "lecteur")
            if model.tabs.showsMemoryWarning { showNotice() }
        }
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

extension Notification.Name {
    /// Le lecteur a posé son PDF (ou échoué) : son calque peut apparaître (`ReaderReveal`).
    static let readerContentReady = Notification.Name("kyokasho.readerContentReady")
}

/// Apparition du calque du lecteur (recette 1.6.1, 1.2 et 1.3). Le calque naît invisible, puis fond en 0,2 s une fois
/// le PDF installé (au plus 0,5 s d'attente). Lancé plus tôt, le fondu tombait pendant la construction et l'installation
/// du PDF sur le fil principal : SwiftUI n'en montrait rien et le lecteur apparaissait d'un coup. « Réduire les
/// animations » : visible tout de suite, sans fondu. Un changement d'onglet ne le rejoue pas (calque déjà visible).
struct ReaderReveal: ViewModifier {
    let reduceMotion: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            // Réunion AV-16-02 (D1) : invisible, il ne prend ni toucher ni VoiceOver (la bibliothèque est déjà inerte).
            .allowsHitTesting(shown || reduceMotion)
            .accessibilityHidden(!(shown || reduceMotion))
            .onReceive(NotificationCenter.default.publisher(for: .readerContentReady)) { _ in reveal() }
            .task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                reveal()
            }
    }

    private func reveal() {
        guard !shown else { return }
        if reduceMotion {
            shown = true
        } else {
            withAnimation(.easeOut(duration: 0.2)) { shown = true }
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
                .font(Atelier.font(13)).foregroundStyle(Atelier.textPrimary)
            if !(monitorEnabled && monitorShown) {
                Button("Moniteur") { monitorEnabled = true; monitorShown = true }
                    .font(Atelier.font(13, weight: .semibold))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Atelier.material(.regularMaterial), in: Capsule())
        .atelierShapeShadow(Capsule(), opacity: 0.3, radius: 12, y: 4)
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
                        Button(document.title) { ReaderTabHandoff.shared.prepare(); model.openDocumentId = document.id }
                    }
                } label: {
                    Image(systemName: "plus").font(Atelier.font(13, weight: .bold))
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
        ReaderTabHandoff.shared.prepare()
        model.openDocumentId = document.id
    }

    private func close(_ document: LibraryDocument) {
        Diagnostics.log("onglets : fermeture de « \(document.title) »", "lecteur")
        ReaderTabHandoff.shared.prepare()
        model.closeTab(document.id)
        // Dernier onglet fermé : retour à la bibliothèque, rien à reprendre.
        if model.openDocumentId == nil { _ = ReaderTabHandoff.shared.take() }
    }
}

/// Onglets en tuiles de la nouvelle présentation (PLAN-REFONTE-001, maquette E0) : une tuile par livre ouvert avec son
/// premier caractère (souvent un kanji), le livre affiché déplié avec titre, page et ✕, puis « + ». Pas de zone
/// défilante (les boutons SwiftUI dans un défilement ne recevaient pas le toucher, recette 1.3.2 (63)) : au-delà de
/// `visible` onglets, les autres passent dans un menu « … ». Mêmes actions que `DocumentTabsBar`.
struct DocumentTileBar: View {
    let current: String
    /// Page affichée par le lecteur (la position enregistrée n'est publiée qu'à la fermeture du livre).
    let currentPageLabel: String
    var visible = 6
    @EnvironmentObject private var model: AppModel
    private var openDocuments: [LibraryDocument] {
        model.tabs.ids.compactMap { id in model.documents.first { $0.id == id } }
    }

    /// Pastels propres aux livres (jamais les couleurs à sens du thème), choisis d'après l'identifiant.
    private static let pastels: [UInt32] = [0xF6D9D2, 0xD3EBDF, 0xE2DCF7, 0xF8E7C2, 0xD5E4F5, 0xF2D6E6]
    static func tileColor(_ id: String) -> Color {
        Color(hex: pastels[Int(id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }) % pastels.count])
    }
    /// Premier caractère du titre ; kanji ou kana de préférence, sinon la première lettre.
    static func glyph(_ title: String) -> String {
        let japanese = title.first { ch in ch.unicodeScalars.contains { (0x3040...0x9FFF).contains($0.value) } }
        return String(japanese ?? title.first(where: { $0.isLetter || $0.isNumber }) ?? "?")
    }

    var body: some View {
        let (shown, hidden) = split(openDocuments)
        HStack(spacing: 8) {
            ForEach(shown) { document in tile(document) }
            if !hidden.isEmpty {
                Menu {
                    ForEach(hidden) { d in
                        Menu(d.title) {
                            Button { select(d) } label: { Label("Afficher", systemImage: "book") }
                            Button(role: .destructive) { close(d) } label: { Label("Fermer l'onglet", systemImage: "xmark") }
                        }
                    }
                } label: {
                    Text(verbatim: "+\(hidden.count)").font(Atelier.font(14, weight: .bold))
                        .frame(width: 44, height: 44).foregroundStyle(Atelier.textSecondary)
                        .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.corner(14), style: .continuous))
                }
                .accessibilityLabel("Autres onglets ouverts")
            }
            Menu {
                ForEach(model.documents.filter { !model.tabs.ids.contains($0.id) }) { document in
                    Button(document.title) { ReaderTabHandoff.shared.prepare(); model.openDocumentId = document.id }
                }
            } label: {
                Image(systemName: "plus").font(Atelier.font(15, weight: .bold))
                    .frame(width: 44, height: 44).foregroundStyle(Atelier.textSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Atelier.corner(14), style: .continuous)
                        .strokeBorder(Atelier.hairline, style: StrokeStyle(lineWidth: Atelier.border(1.5), dash: [4, 3])))
            }
            .accessibilityLabel("Ouvrir un autre document dans un onglet")
        }
    }

    /// Onglets montrés et rangés dans « +N » ; l'onglet affiché reste toujours visible, même ouvert après les autres.
    private func split(_ docs: [LibraryDocument]) -> (shown: [LibraryDocument], hidden: [LibraryDocument]) {
        var shown = Array(docs.prefix(visible))
        if let active = docs.first(where: { $0.id == current }), !shown.contains(where: { $0.id == current }), !shown.isEmpty {
            shown[shown.count - 1] = active
        }
        let hidden = docs.filter { d in !shown.contains { $0.id == d.id } }
        return (shown, hidden)
    }

    /// À partir de ce nombre de livres ouverts, le livre affiché reste lui aussi en pastille (recette 1.6.4 : son titre et
    /// sa page se tassaient sur plusieurs lignes quand beaucoup de livres étaient ouverts).
    static let pillsOnlyFrom = 4

    @ViewBuilder
    private func tile(_ document: LibraryDocument) -> some View {
        let on = document.id == current
        let expanded = on && openDocuments.count < Self.pillsOnlyFrom
        let square = Text(verbatim: Self.glyph(document.title)).font(.custom("HiraginoSans-W6", size: 20))
            .foregroundStyle(Color(hex: 0x1E272C))
            .frame(width: 44, height: 44)
            // Arrondi suivant le style, comme la barre qui l'entoure : rond avec les pastilles arrondies (recette 1.6.4,
            // point 8 : la pastille restait trop carrée), plus anguleux avec un style à petits coins.
            .background(Self.tileColor(document.id), in: RoundedRectangle(cornerRadius: Atelier.corner(22, height: 44), style: .continuous))
        if expanded {
            HStack(spacing: 10) {
                square
                VStack(alignment: .leading, spacing: 1) {
                    Text(document.title).font(Atelier.font(15, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(Atelier.textPrimary)
                    Text(verbatim: "p. \(currentPageLabel) / \(document.pageLabel(document.pageCount - 1))")
                        .font(Atelier.font(12).monospacedDigit()).foregroundStyle(Atelier.textSecondary)
                }
                .frame(maxWidth: 260, alignment: .leading)
                Button { close(document) } label: {
                    Image(systemName: "xmark").font(Atelier.font(12, weight: .bold))
                        .foregroundStyle(Atelier.textSecondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Fermer l'onglet")
            }
            .padding(.leading, 4)
            .newLayoutBar(radius: Atelier.corner(18))
            .accessibilityElement(children: .contain)
        } else {
            // Fermer un autre onglet sans l'afficher : appui long, ou action VoiceOver (revue R2 Codex).
            Button { select(document) } label: {
                // Livre affiché en pastille : anneau de la teinte d'accent pour le distinguer.
                square.overlay {
                    if on {
                        RoundedRectangle(cornerRadius: Atelier.corner(22, height: 44), style: .continuous)
                            .strokeBorder(NewLayoutInk.accent, lineWidth: Atelier.border(2.5))
                    }
                }
            }
                .buttonStyle(PressScale())
                .contextMenu {
                    Button(role: .destructive) { close(document) } label: { Label("Fermer l'onglet", systemImage: "xmark") }
                }
                .accessibilityLabel(document.title)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityAction(named: Text("Fermer l'onglet")) { close(document) }
        }
    }

    private func select(_ document: LibraryDocument) {
        guard document.id != current else { return }
        Diagnostics.log("onglets : passage à « \(document.title) »", "lecteur")
        ReaderTabHandoff.shared.prepare()
        model.openDocumentId = document.id
    }

    private func close(_ document: LibraryDocument) {
        Diagnostics.log("onglets : fermeture de « \(document.title) »", "lecteur")
        ReaderTabHandoff.shared.prepare()
        model.closeTab(document.id)
        // Dernier onglet fermé : retour à la bibliothèque, rien à reprendre.
        if model.openDocumentId == nil { _ = ReaderTabHandoff.shared.take() }
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
            let ink = selected ? UIColor(Atelier.onAccentInk).withAlphaComponent(0.85) : UIColor(Atelier.textPrimary)
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
            close.accessibilityLabel = String(localized: "Fermer l'onglet \(tab.title)")

            let row = UIStackView(arrangedSubviews: [title, close])
            row.axis = .horizontal
            row.spacing = 0
            row.backgroundColor = selected ? UIColor(Atelier.Tint.read) : UIColor(Atelier.surface).withAlphaComponent(0.85)
            let height: CGFloat = 30
            row.layer.cornerRadius = Atelier.corner(15, height: height)
            row.layer.cornerCurve = .continuous
            row.clipsToBounds = true
            row.heightAnchor.constraint(equalToConstant: height).isActive = true
            return row
        }
    }
}
