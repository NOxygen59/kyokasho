// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Où est le panneau d'étude : collé à droite (d'origine), fenêtre libre, plein écran ou réduit en pastille.
/// Gardé entre les ouvertures (`@AppStorage(StudyPanelMode.storageKey)`).
enum StudyPanelMode: String {
    case docked, floating, full, minimized

    static let storageKey = "study.panelMode"
    /// Mode à retrouver en touchant la pastille du panneau réduit.
    static let restoreKey = "study.panelRestore"
}

/// Transitions visuelles des panneaux ; la géométrie du PDF est recalée séparément.
enum StudyPanelMotion {
    static let storageKey = "study.animateTransitions"

    static func animation(enabled: Bool, reduceMotion: Bool) -> Animation? {
        guard enabled else { return nil }
        return reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.32, dampingFraction: 0.92)
    }
}

/// Boutons de fenêtre de l'en-tête du panneau (le mode actuel n'a pas de bouton).
struct StudyWindowButtons: View {
    @AppStorage(StudyPanelMode.storageKey) private var mode = StudyPanelMode.docked
    @AppStorage(StudyPanelMode.restoreKey) private var restore = StudyPanelMode.docked
    @AppStorage(StudyPanelMotion.storageKey) private var animateTransitions = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            button("minus", "Réduire le panneau") { restore = mode; mode = .minimized }
            if mode != .floating { button("macwindow", "Détacher le panneau en fenêtre") { mode = .floating } }
            if mode != .docked { button("sidebar.trailing", "Ancrer le panneau à droite") { mode = .docked } }
            if mode != .full {
                button("arrow.up.left.and.arrow.down.right", "Panneau en plein écran") { mode = .full }
            } else {
                button("arrow.down.right.and.arrow.up.left", "Quitter le plein écran") { mode = .floating }
            }
        }
    }

    private func button(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(StudyPanelMotion.animation(enabled: animateTransitions, reduceMotion: reduceMotion)) { action() }
        } label: {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Atelier.textSecondary)
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Panneau d'étude hors de la colonne de droite : fenêtre déplaçable (barre du haut) et redimensionnable (coin),
/// plein écran, ou pastille. Même principe que `NoteWindow` (position et taille en `@AppStorage`).
struct DetachedPanel<Content: View>: View {
    /// Zone où la fenêtre peut aller.
    let area: CGSize
    @ViewBuilder var content: () -> Content

    @AppStorage(StudyPanelMode.storageKey) private var mode = StudyPanelMode.docked
    @AppStorage(StudyPanelMode.restoreKey) private var restore = StudyPanelMode.docked
    @AppStorage(StudyPanelMotion.storageKey) private var animateTransitions = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("studyPanel.width") private var width = 520.0
    @AppStorage("studyPanel.height") private var height = 640.0
    @AppStorage("studyPanel.x") private var x = 120.0
    @AppStorage("studyPanel.y") private var y = 80.0
    @GestureState private var move: CGSize = .zero
    @GestureState private var resize: CGSize = .zero

    private static var minSize: CGSize { CGSize(width: Atelier.panelWidth, height: 320) }

    /// Un seul `content()` pour tous les modes : changer de mode ne reconstruit pas le panneau (onglet, recherche,
    /// défilement gardés) ; réduit, il est seulement caché.
    var body: some View {
        let full = mode == .full, floating = mode != .full && mode != .minimized
        let gap = Atelier.gap
        // Taille et position affichées (toujours dans la zone, même si elle a rétréci depuis : rotation, Split View).
        let w = full ? max(0, area.width - 2 * gap) : min(max(Self.minSize.width, width + resize.width), area.width)
        let h = full ? max(0, area.height - 2 * gap) : min(max(Self.minSize.height, height + resize.height), area.height)
        let left = full ? gap : min(max(0, x + move.width), max(0, area.width - w))
        let top = full ? gap : min(max(0, y + move.height), max(0, area.height - h))
        return content()
            .frame(width: w, height: h)
            .overlay(alignment: .top) { if floating { grip(left: left, top: top, w: w, h: h) } }
            .overlay(alignment: .bottomTrailing) { if floating { resizeHandle(w: w, h: h) } }
            .shadow(color: .black.opacity(floating ? 0.5 : 0), radius: 20, y: 8)
            .offset(x: left, y: top)
            .opacity(mode == .minimized ? 0 : 1)
            .allowsHitTesting(mode != .minimized)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay { if mode == .minimized { pill.transition(.opacity) } }
            .animation(StudyPanelMotion.animation(enabled: animateTransitions, reduceMotion: reduceMotion), value: mode)
            .transaction { if move != .zero || resize != .zero { $0.animation = nil } }
    }

    /// Poignée du haut : glisser déplace la fenêtre (à partir de la position affichée).
    private func grip(left: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        Capsule().fill(Atelier.textTertiary.opacity(0.6))
            .frame(width: 44, height: 5)
            .frame(width: 120, height: 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .updating($move) { v, s, _ in s = v.translation }
                .onEnded { v in
                    x = min(max(0, left + v.translation.width), max(0, area.width - w))
                    y = min(max(0, top + v.translation.height), max(0, area.height - h))
                })
            .accessibilityLabel("Déplacer le panneau")
    }

    /// Coin de redimensionnement, à moitié hors du panneau (ne cache pas son contenu).
    private func resizeHandle(w: CGFloat, h: CGFloat) -> some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .rotationEffect(.degrees(90))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Atelier.textTertiary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Atelier.surfaceHigh))
            .contentShape(Circle())
            .offset(x: 10, y: 10)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .updating($resize) { v, s, _ in s = v.translation }
                .onEnded { v in
                    width = min(max(Self.minSize.width, w + v.translation.width), area.width)
                    height = min(max(Self.minSize.height, h + v.translation.height), area.height)
                })
            .accessibilityLabel("Redimensionner le panneau")
    }

    /// Panneau réduit : pastille en bas à droite, toucher le rouvre comme avant.
    private var pill: some View {
        Button {
            withAnimation(StudyPanelMotion.animation(enabled: animateTransitions, reduceMotion: reduceMotion)) {
                mode = restore == .minimized ? .docked : restore
            }
        } label: {
            Label("Étude", systemImage: "sidebar.trailing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Atelier.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .atelierPanel(radius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rouvrir le panneau d'étude")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(Atelier.gap)
    }
}
