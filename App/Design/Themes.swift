// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Un thème = fonds (toujours sombres) + une couleur par fonction + un fond dessiné (`ThemeBackdrop`).
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let canvas: Color
    let surface: Color
    let surfaceHigh: Color
    /// Couleur de base du texte (dégradée en primaire / secondaire / tertiaire).
    let ink: Color
    let read: Color
    let annotate: Color
    let japanese: Color
    let ai: Color
    let cloud: Color
    /// Fond de la bibliothèque et du dictionnaire, dessiné ici (aucune image tierce).
    var backdrop: Backdrop = .grid

    enum Backdrop: Equatable { case grid, washi, blueprint, floorplan, dusk, ink, sakura }

    static let atelier = Theme(
        id: "atelier", name: "Atelier (graphite)",
        canvas: Color(hex: 0x0E1013), surface: Color(hex: 0x1B1D22), surfaceHigh: Color(hex: 0x262930),
        ink: .white,
        read: Color(hex: 0x4FD1C4), annotate: Color(hex: 0xF7BA3B), japanese: Color(hex: 0xFF6154),
        ai: Color(hex: 0x9E8FFF), cloud: Color(hex: 0x5CA8FF))

    /// 1 — rouge #c01909, vert #319269, fond #051a11.
    static let foret = Theme(
        id: "foret", name: "Forêt (rouge et vert)",
        canvas: Color(hex: 0x051A11), surface: Color(hex: 0x0B2619), surfaceHigh: Color(hex: 0x143524),
        ink: Color(hex: 0xEEF5EF),
        read: Color(hex: 0x3FB07F), annotate: Color(hex: 0xD9B45A), japanese: Color(hex: 0xE0331F),
        ai: Color(hex: 0x8FC7A8), cloud: Color(hex: 0x5FB0A0))

    /// 2 — rouille #d95733 (le code donné « #d9573 » a 5 chiffres : lu comme #d95733), prune #312730, rouge #e83023.
    static let braise = Theme(
        id: "braise", name: "Braise (prune et rouille)",
        canvas: Color(hex: 0x18121A), surface: Color(hex: 0x241B23), surfaceHigh: Color(hex: 0x312730),
        ink: Color(hex: 0xF6EEF2),
        read: Color(hex: 0xD95733), annotate: Color(hex: 0xF0A35E), japanese: Color(hex: 0xE83023),
        ai: Color(hex: 0xC792B8), cloud: Color(hex: 0x9AA7D6))

    /// 3 — orange #ed6d23, sable #d9ad80, blanc cassé #fcfdf7 (gardé pour le texte, fonds sombres).
    static let sable = Theme(
        id: "sable", name: "Sable (orange et crème)",
        canvas: Color(hex: 0x15110D), surface: Color(hex: 0x211A14), surfaceHigh: Color(hex: 0x2E241B),
        ink: Color(hex: 0xFCFDF7),
        read: Color(hex: 0xD9AD80), annotate: Color(hex: 0xF2C46B), japanese: Color(hex: 0xED6D23),
        ai: Color(hex: 0xC7A6D9), cloud: Color(hex: 0x9EC2D6))

    /// 4 — jaune #ffdc07, ardoise #678488, sable #e1c478.
    static let lagon = Theme(
        id: "lagon", name: "Lagon (jaune et ardoise)",
        canvas: Color(hex: 0x0E1617), surface: Color(hex: 0x172224), surfaceHigh: Color(hex: 0x223133),
        ink: Color(hex: 0xF1F4F2),
        read: Color(hex: 0x86A9AD), annotate: Color(hex: 0xE1C478), japanese: Color(hex: 0xFFDC07),
        ai: Color(hex: 0xB4A6E0), cloud: Color(hex: 0x7FB6D3))

    static let washi = Theme(
        id: "washi", name: "Washi (papier et encre)",
        canvas: Color(hex: 0x1A1714), surface: Color(hex: 0x24201C), surfaceHigh: Color(hex: 0x302A25),
        ink: Color(hex: 0xF4EEE4),
        read: Color(hex: 0x9DB8A0), annotate: Color(hex: 0xE0B862), japanese: Color(hex: 0xD9503F),
        ai: Color(hex: 0xA99BD6), cloud: Color(hex: 0x86A8C2), backdrop: .washi)

    /// Grille d'architecte : le thème du manuel.
    static let architecte = Theme(
        id: "architecte", name: "Architecte (plan bleu)",
        canvas: Color(hex: 0x0A1626), surface: Color(hex: 0x10203A), surfaceHigh: Color(hex: 0x182C4C),
        ink: Color(hex: 0xEAF2FF),
        read: Color(hex: 0x6CC4FF), annotate: Color(hex: 0xFFD166), japanese: Color(hex: 0xFF6B6B),
        ai: Color(hex: 0xB79CFF), cloud: Color(hex: 0x7FD1C8), backdrop: .blueprint)

    static let interieur = Theme(
        id: "interieur", name: "Intérieur (plan et chêne)",
        canvas: Color(hex: 0x121314), surface: Color(hex: 0x1C1D1F), surfaceHigh: Color(hex: 0x28292C),
        ink: Color(hex: 0xF2EFEA),
        read: Color(hex: 0xC9A47A), annotate: Color(hex: 0xE8C37A), japanese: Color(hex: 0xE0644B),
        ai: Color(hex: 0xA7A0D8), cloud: Color(hex: 0x8FB3C4), backdrop: .floorplan)

    static let soir = Theme(
        id: "soir", name: "Lumière du soir",
        canvas: Color(hex: 0x16121F), surface: Color(hex: 0x211A2C), surfaceHigh: Color(hex: 0x2D2439),
        ink: Color(hex: 0xFBF1EA),
        read: Color(hex: 0xF2A65A), annotate: Color(hex: 0xF7D06B), japanese: Color(hex: 0xFF6F61),
        ai: Color(hex: 0xB9A3F5), cloud: Color(hex: 0x8EB7E8), backdrop: .dusk)

    static let encre = Theme(
        id: "encre", name: "Encre et or",
        canvas: Color(hex: 0x0A0A0A), surface: Color(hex: 0x151515), surfaceHigh: Color(hex: 0x202020),
        ink: Color(hex: 0xF5F0E6),
        read: Color(hex: 0xD4AF37), annotate: Color(hex: 0xE9C46A), japanese: Color(hex: 0xE34234),
        ai: Color(hex: 0xB8A9E8), cloud: Color(hex: 0x9DB4C8), backdrop: .ink)

    static let sakura = Theme(
        id: "sakura", name: "Sakura (nuit de printemps)",
        canvas: Color(hex: 0x1A1218), surface: Color(hex: 0x251A22), surfaceHigh: Color(hex: 0x32232E),
        ink: Color(hex: 0xFFF3F6),
        read: Color(hex: 0x9FC9B3), annotate: Color(hex: 0xF3C98B), japanese: Color(hex: 0xF28AB3),
        ai: Color(hex: 0xB9A6F0), cloud: Color(hex: 0x93B8E0), backdrop: .sakura)

    static let all: [Theme] = [.atelier, .washi, .architecte, .interieur, .soir, .encre, .sakura,
                               .foret, .braise, .sable, .lagon]

    /// Thème en cours (lu par `Atelier`). Changé par `ThemeManager`.
    static var current: Theme = .atelier

    /// Couleurs du thème en cours pour le HTML du dictionnaire (`GlossaryRenderer.palette`).
    static var cssPalette: [String: String] {
        let t = current
        func hex(_ c: Color) -> String { UIColor(c).hexString }
        return ["fg": hex(t.ink), "bg": hex(t.surface), "bg2": hex(t.surfaceHigh), "jp": hex(t.japanese),
                "read": hex(t.read), "ann": hex(t.annotate), "ai": hex(t.ai)]
    }
}

/// Choix du thème, gardé entre deux lancements. La racine de l'app se reconstruit au changement.
@MainActor
final class ThemeManager: ObservableObject {
    @Published private(set) var theme: Theme

    init() {
        let id = UserDefaults.standard.string(forKey: "theme.id")
        theme = Theme.all.first { $0.id == id } ?? .atelier
        Theme.current = theme
    }

    func select(_ theme: Theme) {
        guard theme != self.theme else { return }
        UserDefaults.standard.set(theme.id, forKey: "theme.id")
        Theme.current = theme
        self.theme = theme
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Réglages → Apparence : aperçu de chaque thème (son vrai fond), un toucher l'applique.
struct ThemePickerView: View {
    @EnvironmentObject private var themes: ThemeManager

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                ForEach(Theme.all) { theme in
                    Button { themes.select(theme) } label: { card(theme) }.buttonStyle(PressScale())
                }
            }
            .padding()
        }
        .navigationTitle("Thèmes")
    }

    private func card(_ t: Theme) -> some View {
        let on = themes.theme == t
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t.name).font(.headline).foregroundStyle(t.ink)
                Spacer()
                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(t.read) }
            }
            HStack(spacing: 8) {
                ForEach(Array([t.read, t.annotate, t.japanese, t.ai, t.cloud].enumerated()), id: \.offset) { _, c in
                    Circle().fill(c).frame(width: 22, height: 22)
                }
            }
            HStack(spacing: 8) {
                Text("辞").font(.custom("HiraMinProN-W6", size: 18)).foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 38, height: 38).background(t.japanese, in: RoundedRectangle(cornerRadius: 9))
                RoundedRectangle(cornerRadius: 9).fill(t.surfaceHigh).frame(height: 38)
                    .overlay(Text("Texte de la page").font(.footnote).foregroundStyle(t.ink.opacity(0.6)))
            }
        }
        .padding(16)
        .background(t.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(14)
        .background(ThemeBackdrop(theme: t))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(on ? t.read : Color.white.opacity(0.08), lineWidth: on ? 2 : 1))
    }
}
