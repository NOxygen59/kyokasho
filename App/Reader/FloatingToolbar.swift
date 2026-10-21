// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Barre d'outils flottante du lecteur : déplacée par sa poignée, verticale, horizontale ou rétractée.
/// Vue à part : pendant un glissement, seule la barre se redessine (pas tout l'écran du lecteur).
struct FloatingToolbar<Items: View>: View {
    enum Style: String { case vertical, horizontal, collapsed }

    /// Zone où la barre peut aller.
    let area: CGSize
    @ViewBuilder let items: (_ vertical: Bool) -> Items

    @AppStorage("toolbar.style") private var styleRaw = Style.vertical.rawValue
    @AppStorage("toolbar.lastOpen") private var lastOpen = Style.vertical.rawValue
    @AppStorage("toolbar.x") private var fractionX = 0.0
    @AppStorage("toolbar.y") private var fractionY = 0.1
    /// Déplacement en cours (remis à zéro tout seul à la fin du geste).
    @GestureState private var drag: CGSize = .zero
    @State private var size: CGSize = .zero

    var body: some View {
        let style = Style(rawValue: styleRaw) ?? .vertical
        let maxX = max(0, area.width - size.width)
        let maxY = max(0, area.height - size.height)
        let x = min(max(0, fractionX * maxX + drag.width), maxX)
        let y = min(max(0, fractionY * maxY + drag.height), maxY)
        // Repère global : la poignée bouge avec la barre ; mesurer dans son propre repère faisait
        // osciller le geste à l'infini (gel puis plantage).
        let gesture = DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                let endX = min(max(0, fractionX * maxX + value.translation.width), maxX)
                let endY = min(max(0, fractionY * maxY + value.translation.height), maxY)
                fractionX = maxX > 0 ? endX / maxX : 0
                fractionY = maxY > 0 ? endY / maxY : 0
            }
        return Group {
            switch style {
            case .collapsed:
                HStack(spacing: 2) {
                    grip(vertical: false).gesture(gesture)
                    ToolButton(icon: "square.grid.2x2", label: "Ouvrir les outils", tint: Atelier.Tint.read) {
                        setStyle(Style(rawValue: lastOpen) ?? .vertical)
                    }
                }
            case .vertical:
                VStack(spacing: 6) {
                    grip(vertical: true).gesture(gesture)
                    items(true)
                    styleMenu
                }
            case .horizontal:
                HStack(spacing: 6) {
                    grip(vertical: false).gesture(gesture)
                    items(false)
                    styleMenu
                }
            }
        }
        .padding(6)
        .atelierPanel(radius: 16)
        .background(GeometryReader { g in Color.clear.preference(key: ToolbarSizeKey.self, value: g.size) })
        .onPreferenceChange(ToolbarSizeKey.self) { new in
            // Seulement si la taille change vraiment (pas de boucle de mise en page).
            if abs(new.width - size.width) > 0.5 || abs(new.height - size.height) > 0.5 { size = new }
        }
        .offset(x: x, y: y)
        .transaction { if drag != .zero { $0.animation = nil } }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func grip(vertical: Bool) -> some View {
        Image(systemName: "line.3.horizontal")
            .rotationEffect(.degrees(vertical ? 0 : 90))
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Atelier.textTertiary)
            .frame(width: vertical ? 46 : 22, height: vertical ? 22 : 46)
            .contentShape(Rectangle())
            .accessibilityLabel("Déplacer la barre d'outils")
    }

    private var styleMenu: some View {
        Menu {
            Button { setStyle(.vertical) } label: { Label("Verticale", systemImage: "rectangle.portrait") }
            Button { setStyle(.horizontal) } label: { Label("Horizontale", systemImage: "rectangle") }
            Button { setStyle(.collapsed) } label: { Label("Rétracter", systemImage: "arrow.down.right.and.arrow.up.left") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                .frame(width: 46, height: 30).foregroundStyle(Atelier.textSecondary)
        }
        .accessibilityLabel("Forme de la barre d'outils")
    }

    private func setStyle(_ style: Style) {
        if style != .collapsed { lastOpen = style.rawValue }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { styleRaw = style.rawValue }
    }
}

private struct ToolbarSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
