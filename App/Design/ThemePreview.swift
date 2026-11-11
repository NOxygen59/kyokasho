// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Échantillon natif réutilisé par le sélecteur et les planches de contrôle visuel. Il n'écrit aucun réglage.
/// Toutes ses valeurs viennent de la palette et du style fournis, jamais du choix global en cours.
struct ThemePreview: View {
    let theme: Theme
    var style: AppStyle?
    var selected = false

    private var corner: CGFloat { 18 * (style?.cornerScale ?? 1) }
    private var japaneseFace: String {
        style?.fontDesign == .serif || style == nil ? "HiraMinProN-W3" : "HiraginoSans-W6"
    }
    private var design: Font.Design { style?.fontDesign ?? .default }

    var body: some View {
        ZStack {
            ThemeBackdrop(theme: theme, style: style)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("教科書").font(.custom(japaneseFace, size: 31)).foregroundStyle(theme.ink)
                        HStack(spacing: 4) {
                            ForEach(Array([theme.read, theme.annotate, theme.japanese, theme.ai].enumerated()), id: \.offset) { _, tint in
                                Capsule().fill(tint).frame(width: 18, height: 3)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : (style?.symbol ?? theme.symbol))
                        .font(.system(size: 23, weight: .light, design: design)).foregroundStyle(theme.read)
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Text("辞").font(.custom("HiraginoSans-W3", size: 20)).foregroundStyle(theme.japanese)
                        .frame(width: 38, height: 42)
                        .background(theme.japanese.opacity(0.1), in: RoundedRectangle(cornerRadius: corner * 0.5))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Texte de la page").font(.system(size: 12, weight: .semibold, design: design)).foregroundStyle(theme.ink)
                        Text("Lecture · vocabulaire · notes").font(.system(size: 10, design: design)).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold, design: design)).foregroundStyle(theme.read)
                }
                .padding(12)
                .background {
                    let shape = StyledPanelShape(radius: corner * 0.65, kind: style?.panelShape ?? .rounded)
                    if style?.panelFill == .glass {
                        shape.fill(.ultraThinMaterial).overlay(shape.fill(theme.surface.opacity(0.55)))
                    } else {
                        shape.fill(theme.surfaceHigh)
                            .atelierShadow(opacity: 0.20, radius: 8, y: 4, style: style ?? .atelier, tint: theme.shadowTint)
                    }
                }
                .overlay {
                    let shape = StyledPanelShape(radius: corner * 0.65, kind: style?.panelShape ?? .rounded)
                    shape.strokeBorder(edge, lineWidth: style?.borderScale ?? 1)
                    if style?.panelEdge == .doubleLine {
                        shape.inset(by: 4).strokeBorder(theme.read.opacity(0.4), lineWidth: (style?.borderScale ?? 1) * 0.5)
                    }
                }
            }
            .padding(20)
        }
        .frame(height: 210)
        .clipped()
        .environment(\.colorScheme, theme.colorScheme)
        .accessibilityHidden(true) // Le bouton parent expose le nom, l'état et la description du choix.
    }

    private var edge: Color {
        switch style?.panelEdge {
        case .ink: return theme.ink
        case .glow, .doubleLine: return theme.read.opacity(0.85)
        default: return theme.separator
        }
    }
}

