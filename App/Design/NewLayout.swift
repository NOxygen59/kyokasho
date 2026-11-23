// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
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

/// Onglet de chemise : arrondi en bas seulement (`UnevenRoundedRectangle` n'existe qu'à partir d'iOS 17).
struct UnevenRoundedRectangleShim: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Toutes les pages du document en grille, dans le lecteur (maquette E0) : toucher une page y va ; « Supprimer des
/// pages… » garde le chemin d'origine (le livre se ferme, puis « Pages du document », #49). Vignettes du cache commun.
struct PageGridSheet: View {
    @EnvironmentObject private var model: AppModel
    let document: LibraryDocument
    let current: Int
    let canDelete: Bool
    let close: () -> Void
    let go: (Int) -> Void
    let deletePages: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16)], spacing: 18) {
                        ForEach(0..<document.pageCount, id: \.self) { source in
                            Button { go(source); close() } label: {
                                VStack(spacing: 6) {
                                    PageGridThumbnail(document: document, source: source)
                                        .overlay(RoundedRectangle(cornerRadius: Atelier.corner(6), style: .continuous)
                                            .strokeBorder(source == current ? NewLayoutInk.accent : Atelier.hairline,
                                                          lineWidth: Atelier.border(source == current ? 3 : 1)))
                                    Text(verbatim: document.pageLabel(source)).font(Atelier.font(12, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(source == current ? NewLayoutInk.accent : Atelier.textSecondary)
                                }
                            }
                            .buttonStyle(PressScale())
                            .id(source)
                            .accessibilityLabel(Text("Page \(document.pageLabel(source))"))
                            .accessibilityAddTraits(source == current ? .isSelected : [])
                        }
                    }
                    .padding(20)
                }
                .onAppear { proxy.scrollTo(current, anchor: .center) }
            }
            .background(Atelier.canvas)
            .navigationTitle("Pages du document")
            // Revue R2 Codex : on peut renoncer avant que le livre se ferme (#49 : supprimer exige le livre fermé).
            .alert("Supprimer des pages ?", isPresented: $confirmingDelete) {
                Button("Annuler", role: .cancel) {}
                Button("Continuer", role: .destructive) { close(); deletePages() }
            } message: {
                Text("Le livre se ferme, puis « Pages du document » s'ouvre pour choisir les pages à supprimer.")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer", action: close) }
                if canDelete {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label("Supprimer des pages…", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

private struct PageGridThumbnail: View {
    @EnvironmentObject private var model: AppModel
    let document: LibraryDocument
    let source: Int
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: Atelier.corner(6), style: .continuous).fill(Atelier.surface)
            .aspectRatio(0.72, contentMode: .fit)
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFit() } }
            .clipShape(RoundedRectangle(cornerRadius: Atelier.corner(6), style: .continuous))
            .onAppear {
                if let cached = model.thumbnails.cached(documentId: document.id, page: source, width: 240) {
                    image = cached
                } else {
                    model.thumbnails.thumbnail(documentId: document.id, fileURL: model.storage.url(for: document.id),
                                               page: source, width: 240) { image = $0 }
                }
            }
    }
}

/// Croix du panneau : rond de 36 pt dans une zone de 44 pt en nouvelle présentation ; **rien** de changé sinon.
struct NewLayoutCloseTarget: ViewModifier {
    let on: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            content.frame(width: 36, height: 36)
                .background(Atelier.surfaceHigh, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        } else {
            content
        }
    }
}
