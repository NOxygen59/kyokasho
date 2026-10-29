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

    /// Niveaux communs : une légende reste lisible sur le panneau le plus clair.
    var secondaryInk: Color { ink.opacity(0.74) }
    var tertiaryInk: Color { ink.opacity(0.60) }
    var separator: Color { ink.opacity(0.13) }

    var atmosphere: String {
        switch id {
        case "atelier": return "Graphite profond · menthe patinée"
        case "foret": return "Sous-bois · sauge et rouge argile"
        case "braise": return "Prune veloutée · cuivre doux"
        case "sable": return "Sable chaud · crème et terre cuite"
        case "lagon": return "Ardoise marine · jaune solaire"
        case "washi": return "Papier fibreux · encre et céladon"
        case "architecte": return "Bleu de Prusse · traits de craie"
        case "interieur": return "Chêne fumé · lignes d'intérieur"
        case "soir": return "Prune nocturne · lumière ambrée"
        case "encre": return "Encre de charbon · laiton brossé"
        case "sakura": return "Rose poudré · nuit de printemps"
        default: return ""
        }
    }

    enum Backdrop: Equatable { case grid, washi, blueprint, floorplan, dusk, ink, sakura }

    static let atelier = Theme(
        id: "atelier", name: "Atelier (graphite)",
        canvas: Color(hex: 0x101619), surface: Color(hex: 0x1C252A), surfaceHigh: Color(hex: 0x2A353C),
        ink: Color(hex: 0xEFF4F2),
        read: Color(hex: 0x81D8CB), annotate: Color(hex: 0xF0C775), japanese: Color(hex: 0xFA9A8D),
        ai: Color(hex: 0xBFB0EF), cloud: Color(hex: 0x91BDEC))

    static let foret = Theme(
        id: "foret", name: "Forêt (rouge et vert)",
        canvas: Color(hex: 0x101B17), surface: Color(hex: 0x1B2B24), surfaceHigh: Color(hex: 0x2A3B32),
        ink: Color(hex: 0xEFF4E9),
        read: Color(hex: 0x97CCA3), annotate: Color(hex: 0xE6C883), japanese: Color(hex: 0xF29587),
        ai: Color(hex: 0xC0BDD9), cloud: Color(hex: 0x94CBCD))

    static let braise = Theme(
        id: "braise", name: "Braise (prune et rouille)",
        canvas: Color(hex: 0x1C151C), surface: Color(hex: 0x2C212B), surfaceHigh: Color(hex: 0x3D2E3B),
        ink: Color(hex: 0xF8EFEE),
        read: Color(hex: 0xF0A18C), annotate: Color(hex: 0xEEC481), japanese: Color(hex: 0xFFAAA1),
        ai: Color(hex: 0xCFADD6), cloud: Color(hex: 0xA6BCD9))

    static let sable = Theme(
        id: "sable", name: "Sable (orange et crème)",
        canvas: Color(hex: 0x1C1914), surface: Color(hex: 0x2C261F), surfaceHigh: Color(hex: 0x3D342A),
        ink: Color(hex: 0xF8F1E5),
        read: Color(hex: 0xDEC39B), annotate: Color(hex: 0xE9C06C), japanese: Color(hex: 0xF2AE80),
        ai: Color(hex: 0xCDB9DE), cloud: Color(hex: 0xA8C8D4))

    static let lagon = Theme(
        id: "lagon", name: "Lagon (jaune et ardoise)",
        canvas: Color(hex: 0x111D21), surface: Color(hex: 0x1D2D33), surfaceHigh: Color(hex: 0x2C3F46),
        ink: Color(hex: 0xEBF4F2),
        read: Color(hex: 0x99C7CB), annotate: Color(hex: 0xE3C990), japanese: Color(hex: 0xEAD66F),
        ai: Color(hex: 0xBEB9E4), cloud: Color(hex: 0x9ACAE6))

    static let washi = Theme(
        id: "washi", name: "Washi (papier et encre)",
        canvas: Color(hex: 0x1D1C18), surface: Color(hex: 0x2C2A24), surfaceHigh: Color(hex: 0x3C3930),
        ink: Color(hex: 0xF5EFE1),
        read: Color(hex: 0xB8CCAA), annotate: Color(hex: 0xE1C38B), japanese: Color(hex: 0xEBA493),
        ai: Color(hex: 0xC9B9D9), cloud: Color(hex: 0xA6C2CD), backdrop: .washi)

    /// Grille d'architecte : le thème du manuel.
    static let architecte = Theme(
        id: "architecte", name: "Architecte (plan bleu)",
        canvas: Color(hex: 0x101E30), surface: Color(hex: 0x1D3046), surfaceHigh: Color(hex: 0x2B435D),
        ink: Color(hex: 0xEFF6FC),
        read: Color(hex: 0xA0D6F1), annotate: Color(hex: 0xEED39A), japanese: Color(hex: 0xF5A294),
        ai: Color(hex: 0xC6BDF1), cloud: Color(hex: 0xA3D8D0), backdrop: .blueprint)

    static let interieur = Theme(
        id: "interieur", name: "Intérieur (plan et chêne)",
        canvas: Color(hex: 0x1C1D1B), surface: Color(hex: 0x2B2C27), surfaceHigh: Color(hex: 0x3B3C34),
        ink: Color(hex: 0xF4F0E5),
        read: Color(hex: 0xD9BC93), annotate: Color(hex: 0xE7CF9D), japanese: Color(hex: 0xE9A58D),
        ai: Color(hex: 0xC4BDDC), cloud: Color(hex: 0xABC8CB), backdrop: .floorplan)

    static let soir = Theme(
        id: "soir", name: "Lumière du soir",
        canvas: Color(hex: 0x201A29), surface: Color(hex: 0x302639), surfaceHigh: Color(hex: 0x41344C),
        ink: Color(hex: 0xFCF0E7),
        read: Color(hex: 0xF2BF94), annotate: Color(hex: 0xEBD299), japanese: Color(hex: 0xF7A7A3),
        ai: Color(hex: 0xD0B9ED), cloud: Color(hex: 0xAFC9E8), backdrop: .dusk)

    static let encre = Theme(
        id: "encre", name: "Encre et or",
        canvas: Color(hex: 0x101211), surface: Color(hex: 0x20221F), surfaceHigh: Color(hex: 0x30332D),
        ink: Color(hex: 0xF4F0E4),
        read: Color(hex: 0xD9C28C), annotate: Color(hex: 0xEDDAAB), japanese: Color(hex: 0xEBA496),
        ai: Color(hex: 0xCBBFE2), cloud: Color(hex: 0xB2C7D0), backdrop: .ink)

    static let sakura = Theme(
        id: "sakura", name: "Sakura (nuit de printemps)",
        canvas: Color(hex: 0x211921), surface: Color(hex: 0x302530), surfaceHigh: Color(hex: 0x423440),
        ink: Color(hex: 0xFBEFF3),
        read: Color(hex: 0xB9D1BF), annotate: Color(hex: 0xE9D0A8), japanese: Color(hex: 0xF1B1CB),
        ai: Color(hex: 0xD1C1EB), cloud: Color(hex: 0xB4CCE6), backdrop: .sakura)

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

/// Choix de la palette (`Theme`) et du style (`AppStyle`), gardés entre deux lancements. La racine de l'app se
/// reconstruit au changement (`identity`).
@MainActor
final class ThemeManager: ObservableObject {
    @Published private(set) var theme: Theme
    @Published private(set) var style: AppStyle

    /// Identité de la racine : change avec la palette ou le style.
    var identity: String { theme.id + "|" + style.id }

    init() {
        let id = UserDefaults.standard.string(forKey: "theme.id")
        let styleId = UserDefaults.standard.string(forKey: "style.id")
        let theme = Theme.all.first { $0.id == id } ?? .atelier
        let style = AppStyle.all.first { $0.id == styleId } ?? .atelier
        self.theme = theme
        self.style = style
        Theme.current = theme
        AppStyle.current = style
    }

    func select(style: AppStyle) {
        guard style != self.style else { return }
        UserDefaults.standard.set(style.id, forKey: "style.id")
        AppStyle.current = style
        self.style = style
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

/// Réglages → Apparence : le vrai motif reste visible au-dessus d'un échantillon d'interface.
struct ThemePickerView: View {
    @EnvironmentObject private var themes: ThemeManager
    @AppStorage("appearance.themePatterns") private var patternsEnabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choisis ton atmosphère.").font(.title2.weight(.semibold))
                        .foregroundStyle(Atelier.textPrimary)
                    Text("Onze ambiances pour le même atelier de lecture.")
                        .font(.subheadline).foregroundStyle(Atelier.textSecondary)
                    Toggle("Motifs de fond", isOn: $patternsEnabled)
                        .font(.subheadline).tint(Atelier.Tint.read).padding(.top, 8)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18)], spacing: 18) {
                    ForEach(Theme.all) { theme in
                        Button { themes.select(theme) } label: { card(theme) }
                            .buttonStyle(PressScale())
                            .accessibilityLabel(theme.name)
                            .accessibilityValue(themes.theme == theme ? "Sélectionné" : theme.atmosphere)
                            .accessibilityAddTraits(themes.theme == theme ? .isSelected : [])
                    }
                }
            }
            .padding(22)
        }
        .background(Atelier.canvas)
        .navigationTitle("Thèmes")
    }

    private func card(_ t: Theme) -> some View {
        let on = themes.theme == t
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ThemeBackdrop(theme: t)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text("教科書").font(.custom("HiraMinProN-W3", size: 32)).foregroundStyle(t.ink)
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(Atelier.font(22, weight: .medium))
                            .foregroundStyle(on ? t.read : t.tertiaryInk)
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(Array([t.read, t.annotate, t.japanese, t.ai, t.cloud].enumerated()), id: \.offset) { _, color in
                            Capsule().fill(color).frame(width: 25, height: 4)
                        }
                    }
                }
                .padding(20)
            }
            .frame(height: 142)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(t.name).font(Atelier.font(16, weight: .semibold)).foregroundStyle(t.ink)
                    Text(t.atmosphere).font(Atelier.font(12)).foregroundStyle(t.secondaryInk)
                }
                HStack(spacing: 10) {
                    Text("辞").font(.custom("HiraginoSans-W3", size: 18))
                        .foregroundStyle(t.japanese).frame(width: 38, height: 38)
                        .background(t.japanese.opacity(0.12), in: RoundedRectangle(cornerRadius: Atelier.corner(10)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Texte de la page").font(Atelier.font(12, weight: .medium)).foregroundStyle(t.ink)
                        Text("Lecture · vocabulaire · notes").font(Atelier.font(10)).foregroundStyle(t.secondaryInk)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right").font(Atelier.font(12, weight: .semibold)).foregroundStyle(t.read)
                }
                .padding(10)
                .background(t.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.corner(13)))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: Atelier.corner(20), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Atelier.corner(20), style: .continuous)
            .strokeBorder(on ? t.read : t.separator, lineWidth: on ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: Atelier.corner(20), style: .continuous))
    }
}
