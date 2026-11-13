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
    private var style: Style { Style(rawValue: styleRaw) ?? .vertical }
    @AppStorage("toolbar.lastOpen") private var lastOpen = Style.vertical.rawValue
    /// Coin haut-gauche de la barre, en fraction de la **zone** (pas de « zone − taille de la barre ») : la barre ne bouge
    /// plus quand sa taille change, par exemple en passant au Pencil (recette 1.5.7, 1.2). Bornée à l'affichage.
    @AppStorage("toolbar.x") private var fractionX = 0.0
    @AppStorage("toolbar.y") private var fractionY = 0.1
    /// Marge invisible autour de la barre, qui sert aussi de prise (recette 1.5.7, 1.2 : demande de NOxygen59).
    private static var grabMargin: CGFloat { 12 }
    /// Déplacement en cours (remis à zéro tout seul à la fin du geste).
    @GestureState private var drag: CGSize = .zero
    @State private var size: CGSize = .zero

    var body: some View {
        let maxX = max(0, area.width - size.width)
        let maxY = max(0, area.height - size.height)
        let x = min(max(0, fractionX * area.width + drag.width), maxX)
        let y = min(max(0, fractionY * area.height + drag.height), maxY)
        // Repère global : la poignée bouge avec la barre ; mesurer dans son propre repère faisait
        // osciller le geste à l'infini (gel puis plantage).
        let gesture = DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                let endX = min(max(0, fractionX * area.width + value.translation.width), maxX)
                let endY = min(max(0, fractionY * area.height + value.translation.height), maxY)
                fractionX = area.width > 0 ? endX / area.width : 0
                fractionY = area.height > 0 ? endY / area.height : 0
            }
        return Group {
            switch style {
            case .collapsed:
                HStack(spacing: 2) {
                    grip(vertical: false)
                    ToolButton(icon: "square.grid.2x2", label: String(localized: "Ouvrir les outils"), tint: Atelier.Tint.read) {
                        setStyle(Style(rawValue: lastOpen) ?? .vertical)
                    }
                }
            case .vertical:
                VStack(spacing: 6) {
                    grip(vertical: true)
                    items(true)
                    styleButtons(vertical: true)
                }
            case .horizontal:
                HStack(spacing: 6) {
                    grip(vertical: false)
                    items(false)
                    styleButtons(vertical: false)
                }
            }
        }
        .padding(6)
        .atelierPanel(radius: 16)
        // Toute la barre et sa marge se déplacent au glisser ; un toucher sur un bouton reste un toucher.
        .padding(Self.grabMargin)
        .contentShape(Rectangle())
        .gesture(gesture)
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
            .font(Atelier.font(13, weight: .bold))
            .foregroundStyle(Atelier.textTertiary)
            .frame(width: vertical ? 46 : 30, height: vertical ? 30 : 46)
            .contentShape(Rectangle())
            .accessibilityLabel("Déplacer la barre d'outils")
    }

    /// Forme de la barre : trois petits boutons directs (plus de menu à dérouler).
    private func styleButtons(vertical: Bool) -> some View {
        let buttons = Group {
            styleButton(.vertical, icon: "rectangle.portrait", label: String(localized: "Barre verticale"), vertical: vertical)
            styleButton(.horizontal, icon: "rectangle", label: String(localized: "Barre horizontale"), vertical: vertical)
            styleButton(.collapsed, icon: "arrow.down.right.and.arrow.up.left", label: String(localized: "Rétracter la barre"), vertical: vertical)
        }
        return Group {
            if vertical { VStack(spacing: 2) { buttons } } else { HStack(spacing: 2) { buttons } }
        }
    }

    private func styleButton(_ target: Style, icon: String, label: String, vertical: Bool) -> some View {
        let current = style == target
        return Button { setStyle(target) } label: {
            Image(systemName: icon).font(Atelier.font(12, weight: .semibold))
                .frame(width: vertical ? 46 : 26, height: vertical ? 26 : 46)
                .foregroundStyle(current ? Atelier.Tint.read : Atelier.textTertiary)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .disabled(current)
        .accessibilityLabel(label)
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
