// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

// Composants de la nouvelle présentation (PLAN-REFONTE-001, maquettes E0 et E3) : forme fixe (pilules, cibles de
// 48 à 56 pt, libellés visibles), couleurs lues dans le thème actif (AV-REFONTE-01). Le style choisi (AppStyle)
// n'en change pas la forme : c'est la refonte qui la fixe ; seules les couleurs suivent la palette.

/// Couleur principale de la nouvelle présentation : bleu encre du thème Papier, ou la couleur « cloud » du thème
/// actif (même rôle dans toutes les palettes, testée à 4,5:1 sous `onAccent` dans les variantes claires).
enum NewLayoutInk {
    static var accent: Color { Atelier.Tint.cloud }
    static var onAccent: Color { Atelier.onAccentInk }
}

extension View {
    /// Fond d'une barre de la nouvelle présentation : surface pleine, filet et ombre douce. Un filet visible détache
    /// la barre d'un fond clair (sans lui, le blanc sur papier ne se voit pas ; relecture D-07 du plan).
    func newLayoutBar(radius: CGFloat) -> some View {
        atelierShapeShadow(RoundedRectangle(cornerRadius: radius, style: .continuous), opacity: 0.10, radius: 12, y: 5)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Atelier.hairline, lineWidth: Atelier.border(1))
            }
    }
}

/// Bouton rond posé seul (retour à la bibliothèque).
struct NewLayoutRoundButton: View {
    let icon: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(Atelier.font(18, weight: .semibold))
                .frame(width: 52, height: 52)
                .foregroundStyle(Atelier.textPrimary)
                .newLayoutBar(radius: 26)
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }
}

/// Bouton icône de 48 ou 56 pt ; actif : voile de la couleur principale.
struct NewLayoutIconButton: View {
    let icon: String
    let label: String
    var active = false
    var tint: Color = NewLayoutInk.accent
    /// Fond léger permanent (flèches de page).
    var filled = false
    var size: CGFloat = 48
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(Atelier.font(size >= 56 ? 20 : 18, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(active ? tint : Atelier.textPrimary)
                .background(active ? tint.opacity(0.16) : filled ? Atelier.surfaceHigh : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Bouton libellé en pilule ; actif : plein de la couleur principale (forme et couleur, pas la couleur seule).
struct NewLayoutPillButton: View {
    let icon: String?
    let title: String
    var active = false
    /// 56 pt (grande barre du bas) au lieu de 48.
    var large = false
    /// Libellé lu par VoiceOver quand il diffère du titre affiché.
    var accessibility: String? = nil
    /// Icône seule quand la place manque (le titre reste lu par VoiceOver).
    var compact = false
    /// Faux pour une simple action mise en avant (Reprendre, Terminé) : pas de trait « sélectionné » pour VoiceOver.
    var selectable = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(Atelier.font(large ? 17 : 15, weight: .semibold)) }
                if !(compact && icon != nil) {
                    Text(verbatim: title).font(Atelier.font(large ? 16 : 15, weight: .bold)).lineLimit(1)
                }
            }
            .padding(.horizontal, compact ? 14 : large ? 18 : 15)
            .frame(minWidth: large ? 56 : 48)
            .frame(height: large ? 56 : 48)
            .foregroundStyle(active ? NewLayoutInk.onAccent : Atelier.textPrimary)
            .background(active ? NewLayoutInk.accent : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(accessibility ?? title)
        .accessibilityAddTraits(active && selectable ? .isSelected : [])
    }
}

/// Onglets du panneau d'étude dans la nouvelle présentation (maquette E0) : piste grise, onglet choisi en carte
/// claire, **titres toujours visibles** (l'ancienne version ne montrait que celui de l'onglet actif).
struct NewLayoutTabs<T: Hashable>: View {
    let items: [(T, String)]   // valeur, titre
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                let (value, title) = items[i]
                let on = value == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = value }
                } label: {
                    Text(verbatim: title).font(Atelier.font(14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .foregroundStyle(on ? NewLayoutInk.accent : Atelier.textSecondary)
                        .background {
                            if on { Color.clear.atelierShapeShadow(Capsule(), opacity: 0.12, radius: 3, y: 1) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Atelier.surfaceHigh, in: Capsule())
    }
}

/// Enveloppe d'un panneau : carte claire de la nouvelle présentation, ou panneau Atelier d'origine.
struct NewLayoutPanel: ViewModifier {
    let on: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if on { content.newLayoutBar(radius: Atelier.corner(22)) } else { content.atelierPanel() }
    }
}

/// Bandeau discret (corrections IA) dans la nouvelle présentation ; inchangé sinon.
struct NewLayoutBanner: ViewModifier {
    let on: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            content.padding(10)
                .background(NewLayoutInk.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: Atelier.corner(14), style: .continuous))
        } else {
            content
        }
    }
}
