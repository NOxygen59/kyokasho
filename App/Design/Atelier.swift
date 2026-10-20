// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Système visuel « Atelier » : un outil de studio (graphite, panneaux flottants, grille fine),
/// une couleur par fonction pour qu'on sache toujours dans quel mode on est.
enum Atelier {
    // MARK: Couleurs

    static let canvas = Color(red: 0.055, green: 0.063, blue: 0.075)       // fond graphite
    static let surface = Color(red: 0.105, green: 0.115, blue: 0.135)      // panneaux
    static let surfaceHigh = Color(red: 0.150, green: 0.162, blue: 0.188)  // éléments posés sur un panneau
    static let hairline = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.56)
    static let textTertiary = Color.white.opacity(0.34)

    /// Une couleur par fonction.
    enum Tint {
        static let read = Color(red: 0.31, green: 0.82, blue: 0.77)        // lecture, navigation
        static let annotate = Color(red: 0.97, green: 0.73, blue: 0.23)    // stylo, surligneur, notes
        static let japanese = Color(red: 1.00, green: 0.38, blue: 0.33)    // japonais : texte, vocabulaire
        static let ai = Color(red: 0.62, green: 0.56, blue: 1.00)          // IA, traduction
        static let cloud = Color(red: 0.36, green: 0.66, blue: 1.00)       // Drive, import
    }

    // MARK: Mesures

    static let radius: CGFloat = 18
    static let smallRadius: CGFloat = 11
    static let gap: CGFloat = 14
    static let panelWidth: CGFloat = 372

    // MARK: Typographie

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .default) }
    /// Petites étiquettes en capitales espacées, style plan d'architecte.
    static let label = Font.system(size: 11, weight: .semibold).width(.expanded)
    static let mono = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let jp = Font.custom("HiraginoSans-W3", size: 17)
}

// MARK: - Panneau

struct AtelierPanel: ViewModifier {
    var padding: CGFloat = 0
    var radius: CGFloat = Atelier.radius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Atelier.surface.opacity(0.92))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Atelier.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }
}

extension View {
    func atelierPanel(padding: CGFloat = 0, radius: CGFloat = Atelier.radius) -> some View {
        modifier(AtelierPanel(padding: padding, radius: radius))
    }
}

/// Étiquette de section : « LECTURE », « TEXTE »…
struct AtelierLabel: View {
    let text: String
    var tint: Color = Atelier.textTertiary

    init(_ text: String, tint: Color = Atelier.textTertiary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased()).font(Atelier.label).tracking(1.2).foregroundStyle(tint)
    }
}

/// Bouton d'outil carré (barre d'outils verticale).
struct ToolButton: View {
    let icon: String
    let label: String
    var tint: Color = Atelier.Tint.read
    var active = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 46, height: 46)
                .foregroundStyle(active ? Color.black.opacity(0.85) : Atelier.textPrimary)
                .background {
                    RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous)
                        .fill(active ? tint : Color.clear)
                }
                .overlay(alignment: .bottomTrailing) {
                    if !active {
                        Circle().fill(tint).frame(width: 5, height: 5).offset(x: -6, y: -6)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Bouton rond d'une capsule (barre du haut).
struct CapsuleButton: View {
    let icon: String
    let label: String
    var active = false
    var tint: Color = Atelier.Tint.read
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 40)
                .foregroundStyle(active ? tint : Atelier.textPrimary)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Bouton plein, couleur de fonction.
struct AtelierButtonStyle: ButtonStyle {
    var tint: Color = Atelier.Tint.read

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(Color.black.opacity(0.85))
            .background(tint, in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Fond quadrillé discret (papier millimétré d'atelier).
struct GridBackground: View {
    var spacing: CGFloat = 28

    var body: some View {
        Canvas { context, size in
            var minor = Path()
            var x: CGFloat = 0
            while x <= size.width { minor.move(to: CGPoint(x: x, y: 0)); minor.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
            var y: CGFloat = 0
            while y <= size.height { minor.move(to: CGPoint(x: 0, y: y)); minor.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
            context.stroke(minor, with: .color(.white.opacity(0.035)), lineWidth: 0.5)
            var major = Path()
            x = 0
            while x <= size.width { major.move(to: CGPoint(x: x, y: 0)); major.addLine(to: CGPoint(x: x, y: size.height)); x += spacing * 5 }
            y = 0
            while y <= size.height { major.move(to: CGPoint(x: 0, y: y)); major.addLine(to: CGPoint(x: size.width, y: y)); y += spacing * 5 }
            context.stroke(major, with: .color(.white.opacity(0.06)), lineWidth: 0.6)
        }
        .background(Atelier.canvas)
        .ignoresSafeArea()
        .drawingGroup()
    }
}

/// Onglets en pastilles (panneau d'étude, filtres).
struct PillTabs<T: Hashable>: View {
    let items: [(T, String, String)]   // valeur, icône, titre
    @Binding var selection: T
    var tint: Color = Atelier.Tint.read

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                let (value, icon, title) = items[i]
                let on = value == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = value }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                        // Nom seulement sur l'onglet actif : jamais coupé, même dans un panneau étroit.
                        if on { Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize() }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: on ? .infinity : nil)
                    .frame(minWidth: 40)
                    .foregroundStyle(on ? Color.black.opacity(0.85) : Atelier.textSecondary)
                    .background(on ? tint : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
            }
        }
        .padding(4)
        .background(Atelier.surfaceHigh, in: Capsule())
    }
}
