// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Système visuel « Atelier » : un outil de studio (graphite, panneaux flottants, grille fine),
/// une couleur par fonction pour qu'on sache toujours dans quel mode on est.
enum Atelier {
    // MARK: Couleurs

    // Lues dans le thème en cours (`Theme.current`, voir Themes.swift).
    static var canvas: Color { Theme.current.canvas }               // fond
    static var surface: Color { Theme.current.surface }             // panneaux
    static var surfaceHigh: Color { Theme.current.surfaceHigh }     // éléments posés sur un panneau
    static var hairline: Color { Theme.current.separator }
    static var textPrimary: Color { Theme.current.ink.opacity(0.96) }
    static var textSecondary: Color { Theme.current.secondaryInk }
    static var textTertiary: Color { Theme.current.tertiaryInk }
    /// Encres liées à la variante de la palette (nuit, clair, sépia) : sur une couleur de fonction, contraste, ombre.
    static var onAccentInk: Color { Theme.current.onAccent }
    static var contrastInk: Color { Theme.current.contrast }
    static var shadow: Color { Theme.current.shadowTint }
    /// Voile derrière une fenêtre, lu dans le style.
    static var scrim: Color { AppStyle.current.scrim }

    /// Une couleur par fonction.
    enum Tint {
        static var read: Color { Theme.current.read }           // lecture, navigation
        static var annotate: Color { Theme.current.annotate }   // stylo, surligneur, notes
        static var japanese: Color { Theme.current.japanese }   // japonais : texte, vocabulaire
        static var ai: Color { Theme.current.ai }               // IA, traduction
        static var cloud: Color { Theme.current.cloud }         // Drive, import
    }

    // MARK: Mesures

    // Forme : lue dans le style en cours (`AppStyle.current`, voir Styles.swift).
    /// Arrondi d'un élément d'interface : valeur d'origine (style Atelier) × `cornerScale` du style. Les dessins
    /// posés sur la page (sélection OCR, repères) n'en dépendent pas.
    static func corner(_ base: CGFloat) -> CGFloat { base * AppStyle.current.cornerScale }
    static var radius: CGFloat { corner(18) }
    static var smallRadius: CGFloat { corner(11) }
    /// Épaisseur d'une bordure d'interface : valeur d'origine × `borderScale` du style.
    static func border(_ base: CGFloat) -> CGFloat { base * AppStyle.current.borderScale }
    /// Matière d'iOS demandée, ou fond plein du panneau si le style n'utilise pas de flou.
    static func material(_ base: Material) -> AnyShapeStyle {
        AppStyle.current.usesMaterials ? AnyShapeStyle(base) : AnyShapeStyle(surface)
    }
    static let gap: CGFloat = 14
    static let panelWidth: CGFloat = 372

    // MARK: Typographie

    /// Police de l'interface : taille d'origine, famille du style (`AppStyle.fontDesign`). Le japonais (Hiragino), le
    /// texte à chasse fixe et le texte de la page (panneau OCR, taille choisie dans les réglages) n'en dépendent pas.
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: AppStyle.current.fontDesign)
    }
    static func display(_ size: CGFloat) -> Font { font(size, weight: .semibold) }
    /// Petites étiquettes en capitales espacées, style plan d'architecte.
    static var label: Font { font(11, weight: .semibold).width(.expanded) }
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
            // Batterie / fluidité : pas de flou (invisible sous un fond presque opaque, mais recalculé
            // à chaque image quand la page défile derrière) et ombre portée par la forme seule
            // (sinon tout le contenu, textes et icônes, est redessiné à part pour la calculer).
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Atelier.surface.opacity(0.97))
                    .atelierShadow(opacity: 0.28, radius: 16, y: 7)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Atelier.hairline, lineWidth: Atelier.border(1))
            }
    }
}

extension View {
    /// Famille du style appliquée aux styles de texte iOS (`.caption`, `.headline`…). `fontDesign` n'existe qu'à
    /// partir d'iOS 16.1 : en 16.0, ces textes gardent la famille d'iOS (les textes `Atelier.font` suivent quand même).
    @ViewBuilder
    func atelierFontDesign() -> some View {
        if #available(iOS 16.1, *) { fontDesign(AppStyle.current.fontDesign) } else { self }
    }

    /// Ombre portée selon le style (`AppStyle.shadowKind`). Valeurs = celles d'origine pour une ombre douce ; appliquée
    /// là où l'était `.shadow`, donc au même calque (sur la forme seule pour les panneaux, voir `AtelierPanel`).
    @ViewBuilder
    func atelierShadow(opacity: Double, radius: CGFloat, y: CGFloat) -> some View {
        switch AppStyle.current.shadowKind {
        case .soft: shadow(color: Atelier.shadow.opacity(opacity), radius: radius, y: y)
        case .hard(let offset): shadow(color: Atelier.shadow.opacity(min(1, opacity * 2)), radius: 0, x: offset, y: offset)
        case .none: self
        }
    }

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
                .font(Atelier.font(19, weight: .medium))
                .frame(width: 46, height: 46)
                .foregroundStyle(active ? Atelier.onAccentInk.opacity(0.85) : Atelier.textPrimary)
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
                .font(Atelier.font(17, weight: .medium))
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
            .font(Atelier.font(15, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(Atelier.onAccentInk.opacity(0.85))
            .background(tint, in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Fond de la bibliothèque et du dictionnaire : celui du thème en cours (`ThemeBackdrop`, quadrillé d'origine).
struct GridBackground: View {
    var body: some View {
        ThemeBackdrop(theme: Theme.current).ignoresSafeArea()
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
                        Image(systemName: icon).font(Atelier.font(13, weight: .semibold))
                        // Nom seulement sur l'onglet actif : jamais coupé, même dans un panneau étroit.
                        if on { Text(title).font(Atelier.font(13, weight: .semibold)).lineLimit(1).fixedSize() }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: on ? .infinity : nil)
                    .frame(minWidth: 40)
                    .foregroundStyle(on ? Atelier.onAccentInk.opacity(0.85) : Atelier.textSecondary)
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
