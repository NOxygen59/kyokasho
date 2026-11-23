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
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Atelier.surface)
                .shadow(color: Atelier.shadow.opacity(0.10), radius: 12, y: 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Atelier.hairline, lineWidth: 1)
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
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(Atelier.font(large ? 17 : 15, weight: .semibold)) }
                Text(verbatim: title).font(Atelier.font(large ? 16 : 15, weight: .bold)).lineLimit(1)
            }
            .padding(.horizontal, large ? 18 : 15)
            .frame(height: large ? 56 : 48)
            .foregroundStyle(active ? NewLayoutInk.onAccent : Atelier.textPrimary)
            .background(active ? NewLayoutInk.accent : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(accessibility ?? title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
