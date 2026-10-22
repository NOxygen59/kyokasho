// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Un thème = fonds (toujours sombres) + une couleur par fonction.
// FDR-V6 : nouveaux thèmes à fonds dessinés (washi, grille d'architecte, plan d'intérieur, encre et or…), aperçu en direct, couleurs aussi dans le HTML.
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

    static let all: [Theme] = [.atelier, .foret, .braise, .sable, .lagon]

    /// Thème en cours (lu par `Atelier`). Changé par `ThemeManager`.
    static var current: Theme = .atelier
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

/// Réglages → Apparence : aperçu de chaque thème, un toucher l'applique.
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
        .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(on ? t.read : Color.white.opacity(0.08), lineWidth: on ? 2 : 1))
        .background(t.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
