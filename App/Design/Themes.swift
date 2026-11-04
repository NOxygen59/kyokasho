// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Un thème = une palette : fonds, une couleur par fonction, un fond dessiné (`ThemeBackdrop`), et sa variante
/// (lot 3 des styles, planche choisie par NOxygen59 le 29/10/2026) : **nuit** (fonds sombres, tous les thèmes
/// d'origine), **clair** ou **sépia** (fonds clairs : interface iOS en mode clair, encres foncées).
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
    /// Variante claire (clair, sépia) : mode clair d'iOS et encres ci-dessous inversées.
    var isLight = false
    /// Texte ou icône posé sur une couleur de fonction pleine (noir sur les teintes claires des thèmes nuit).
    var onAccent: Color = .black
    /// Contraste maximal sur le fond de l'interface.
    var contrast: Color = .white
    /// Teinte des ombres portées.
    var shadowTint: Color = .black
    /// Opacités de l'encre pour la légende et l'indication : relevées en clair pour garder 4,5:1 sur les panneaux.
    var secondaryLevel: Double = 0.74
    var tertiaryLevel: Double = 0.60

    /// Niveaux communs : une légende reste lisible sur le panneau le plus clair.
    var secondaryInk: Color { ink.opacity(secondaryLevel) }
    var tertiaryInk: Color { ink.opacity(tertiaryLevel) }
    var colorScheme: ColorScheme { isLight ? .light : .dark }
    var separator: Color { ink.opacity(0.13) }

    var atmosphere: String {
        switch id {
        case "atelier": return String(localized: "Graphite profond · menthe patinée")
        case "clair": return String(localized: "Papier blanc · encre graphite")
        case "sepia": return String(localized: "Papier ancien · encre brune")
        case "brutal": return String(localized: "Crème et encre · couleurs franches")
        case "swiss": return String(localized: "Blanc, noir · rouge suisse")
        case "synthwave": return String(localized: "Nuit violette · cyan et rose néon")
        case "terre": return String(localized: "Argile et lin · mousse et rouille")
        case "foret": return String(localized: "Sous-bois · sauge et rouge argile")
        case "braise": return String(localized: "Prune veloutée · cuivre doux")
        case "sable": return String(localized: "Sable chaud · crème et terre cuite")
        case "lagon": return String(localized: "Ardoise marine · jaune solaire")
        case "washi": return String(localized: "Papier fibreux · encre et céladon")
        case "architecte": return String(localized: "Bleu de Prusse · traits de craie")
        case "interieur": return String(localized: "Chêne fumé · lignes d'intérieur")
        case "soir": return String(localized: "Prune nocturne · lumière ambrée")
        case "encre": return String(localized: "Encre de charbon · laiton brossé")
        case "sakura": return String(localized: "Rose poudré · nuit de printemps")
        default: return ""
        }
    }

    enum Backdrop: Equatable { case grid, washi, blueprint, floorplan, dusk, ink, sakura }

    static let atelier = Theme(
        id: "atelier", name: String(localized: "Atelier (graphite)"),
        canvas: Color(hex: 0x101619), surface: Color(hex: 0x1C252A), surfaceHigh: Color(hex: 0x2A353C),
        ink: Color(hex: 0xEFF4F2),
        read: Color(hex: 0x81D8CB), annotate: Color(hex: 0xF0C775), japanese: Color(hex: 0xFA9A8D),
        ai: Color(hex: 0xBFB0EF), cloud: Color(hex: 0x91BDEC))

    static let foret = Theme(
        id: "foret", name: String(localized: "Forêt (rouge et vert)"),
        canvas: Color(hex: 0x101B17), surface: Color(hex: 0x1B2B24), surfaceHigh: Color(hex: 0x2A3B32),
        ink: Color(hex: 0xEFF4E9),
        read: Color(hex: 0x97CCA3), annotate: Color(hex: 0xE6C883), japanese: Color(hex: 0xF29587),
        ai: Color(hex: 0xC0BDD9), cloud: Color(hex: 0x94CBCD))

    static let braise = Theme(
        id: "braise", name: String(localized: "Braise (prune et rouille)"),
        canvas: Color(hex: 0x1C151C), surface: Color(hex: 0x2C212B), surfaceHigh: Color(hex: 0x3D2E3B),
        ink: Color(hex: 0xF8EFEE),
        read: Color(hex: 0xF0A18C), annotate: Color(hex: 0xEEC481), japanese: Color(hex: 0xFFAAA1),
        ai: Color(hex: 0xCFADD6), cloud: Color(hex: 0xA6BCD9))

    static let sable = Theme(
        id: "sable", name: String(localized: "Sable (orange et crème)"),
        canvas: Color(hex: 0x1C1914), surface: Color(hex: 0x2C261F), surfaceHigh: Color(hex: 0x3D342A),
        ink: Color(hex: 0xF8F1E5),
        read: Color(hex: 0xDEC39B), annotate: Color(hex: 0xE9C06C), japanese: Color(hex: 0xF2AE80),
        ai: Color(hex: 0xCDB9DE), cloud: Color(hex: 0xA8C8D4))

    static let lagon = Theme(
        id: "lagon", name: String(localized: "Lagon (jaune et ardoise)"),
        canvas: Color(hex: 0x111D21), surface: Color(hex: 0x1D2D33), surfaceHigh: Color(hex: 0x2C3F46),
        ink: Color(hex: 0xEBF4F2),
        read: Color(hex: 0x99C7CB), annotate: Color(hex: 0xE3C990), japanese: Color(hex: 0xEAD66F),
        ai: Color(hex: 0xBEB9E4), cloud: Color(hex: 0x9ACAE6))

    static let washi = Theme(
        id: "washi", name: String(localized: "Washi (papier et encre)"),
        canvas: Color(hex: 0x1D1C18), surface: Color(hex: 0x2C2A24), surfaceHigh: Color(hex: 0x3C3930),
        ink: Color(hex: 0xF5EFE1),
        read: Color(hex: 0xB8CCAA), annotate: Color(hex: 0xE1C38B), japanese: Color(hex: 0xEBA493),
        ai: Color(hex: 0xC9B9D9), cloud: Color(hex: 0xA6C2CD), backdrop: .washi)

    /// Grille d'architecte : le thème du manuel.
    static let architecte = Theme(
        id: "architecte", name: String(localized: "Architecte (plan bleu)"),
        canvas: Color(hex: 0x101E30), surface: Color(hex: 0x1D3046), surfaceHigh: Color(hex: 0x2B435D),
        ink: Color(hex: 0xEFF6FC),
        read: Color(hex: 0xA0D6F1), annotate: Color(hex: 0xEED39A), japanese: Color(hex: 0xF5A294),
        ai: Color(hex: 0xC6BDF1), cloud: Color(hex: 0xA3D8D0), backdrop: .blueprint)

    static let interieur = Theme(
        id: "interieur", name: String(localized: "Intérieur (plan et chêne)"),
        canvas: Color(hex: 0x1C1D1B), surface: Color(hex: 0x2B2C27), surfaceHigh: Color(hex: 0x3B3C34),
        ink: Color(hex: 0xF4F0E5),
        read: Color(hex: 0xD9BC93), annotate: Color(hex: 0xE7CF9D), japanese: Color(hex: 0xE9A58D),
        ai: Color(hex: 0xC4BDDC), cloud: Color(hex: 0xABC8CB), backdrop: .floorplan)

    static let soir = Theme(
        id: "soir", name: String(localized: "Lumière du soir"),
        canvas: Color(hex: 0x201A29), surface: Color(hex: 0x302639), surfaceHigh: Color(hex: 0x41344C),
        ink: Color(hex: 0xFCF0E7),
        read: Color(hex: 0xF2BF94), annotate: Color(hex: 0xEBD299), japanese: Color(hex: 0xF7A7A3),
        ai: Color(hex: 0xD0B9ED), cloud: Color(hex: 0xAFC9E8), backdrop: .dusk)

    static let encre = Theme(
        id: "encre", name: String(localized: "Encre et or"),
        canvas: Color(hex: 0x101211), surface: Color(hex: 0x20221F), surfaceHigh: Color(hex: 0x30332D),
        ink: Color(hex: 0xF4F0E4),
        read: Color(hex: 0xD9C28C), annotate: Color(hex: 0xEDDAAB), japanese: Color(hex: 0xEBA496),
        ai: Color(hex: 0xCBBFE2), cloud: Color(hex: 0xB2C7D0), backdrop: .ink)

    static let sakura = Theme(
        id: "sakura", name: String(localized: "Sakura (nuit de printemps)"),
        canvas: Color(hex: 0x211921), surface: Color(hex: 0x302530), surfaceHigh: Color(hex: 0x423440),
        ink: Color(hex: 0xFBEFF3),
        read: Color(hex: 0xB9D1BF), annotate: Color(hex: 0xE9D0A8), japanese: Color(hex: 0xF1B1CB),
        ai: Color(hex: 0xD1C1EB), cloud: Color(hex: 0xB4CCE6), backdrop: .sakura)

    /// Variante claire de la planche du 29/10/2026 : teintes de fonction foncées (texte blanc dessus, 4,5:1).
    static let clair = Theme(
        id: "clair", name: String(localized: "Clair (papier blanc)"),
        canvas: Color(hex: 0xF4F2EE), surface: Color(hex: 0xFFFFFF), surfaceHigh: Color(hex: 0xECE8E1),
        ink: Color(hex: 0x1B2226),
        read: Color(hex: 0x0F7466), annotate: Color(hex: 0x8A5A00), japanese: Color(hex: 0xB3372A),
        ai: Color(hex: 0x6347B8), cloud: Color(hex: 0x2563A8),
        isLight: true, onAccent: Color(hex: 0xFFFFFF), contrast: Color(hex: 0x1B2226), shadowTint: Color(hex: 0x1B2226),
        secondaryLevel: 0.82, tertiaryLevel: 0.72)

    /// Variante sépia de la planche du 29/10/2026.
    static let sepia = Theme(
        id: "sepia", name: String(localized: "Sépia (papier ancien)"),
        canvas: Color(hex: 0xEFE4D0), surface: Color(hex: 0xF8F0E1), surfaceHigh: Color(hex: 0xE6D8BE),
        ink: Color(hex: 0x3B2A1A),
        read: Color(hex: 0x1C6457), annotate: Color(hex: 0x845000), japanese: Color(hex: 0xA53A24),
        ai: Color(hex: 0x5E4A9E), cloud: Color(hex: 0x2F5F8A), backdrop: .washi,
        isLight: true, onAccent: Color(hex: 0xFFF8EC), contrast: Color(hex: 0x3B2A1A), shadowTint: Color(hex: 0x3B2A1A),
        secondaryLevel: 0.82, tertiaryLevel: 0.75)

    // Palettes proposées par les styles du premier lot (S2, 29/10/2026).
    static let brutal = Theme(
        id: "brutal", name: String(localized: "Brutal (crème et encre)"),
        canvas: Color(hex: 0xFFF4D6), surface: Color(hex: 0xFFFFFF), surfaceHigh: Color(hex: 0xFFEFB0),
        ink: Color(hex: 0x111111),
        read: Color(hex: 0x0050C8), annotate: Color(hex: 0x8A4B00), japanese: Color(hex: 0xB0154F),
        ai: Color(hex: 0x5B2DB8), cloud: Color(hex: 0x006D5B),
        isLight: true, onAccent: Color(hex: 0xFFFFFF), contrast: Color(hex: 0x111111), shadowTint: Color(hex: 0x111111),
        secondaryLevel: 0.82, tertiaryLevel: 0.72)

    static let swiss = Theme(
        id: "swiss", name: String(localized: "Suisse (blanc et rouge)"),
        canvas: Color(hex: 0xF2F2F2), surface: Color(hex: 0xFFFFFF), surfaceHigh: Color(hex: 0xE6E6E6),
        ink: Color(hex: 0x111111),
        read: Color(hex: 0xC01F14), annotate: Color(hex: 0x8A5A00), japanese: Color(hex: 0x9E1B32),
        ai: Color(hex: 0x3F3FBF), cloud: Color(hex: 0x1F5FA8),
        isLight: true, onAccent: Color(hex: 0xFFFFFF), contrast: Color(hex: 0x111111), shadowTint: Color(hex: 0x111111),
        secondaryLevel: 0.82, tertiaryLevel: 0.72)

    static let synthwave = Theme(
        id: "synthwave", name: String(localized: "Synthwave (néon)"),
        canvas: Color(hex: 0x140A26), surface: Color(hex: 0x221238), surfaceHigh: Color(hex: 0x321C4E),
        ink: Color(hex: 0xF6EEFF),
        read: Color(hex: 0x5CF2E6), annotate: Color(hex: 0xFFD166), japanese: Color(hex: 0xFF6EC7),
        ai: Color(hex: 0xB69CFF), cloud: Color(hex: 0x7FB7FF), backdrop: .dusk)

    static let terre = Theme(
        id: "terre", name: String(localized: "Terre (wabi-sabi)"),
        canvas: Color(hex: 0xE9E2D6), surface: Color(hex: 0xF3EEE5), surfaceHigh: Color(hex: 0xDDD3C3),
        ink: Color(hex: 0x2E2A24),
        read: Color(hex: 0x3F5A2E), annotate: Color(hex: 0x7A4A12), japanese: Color(hex: 0x8E3B2A),
        ai: Color(hex: 0x5A4A78), cloud: Color(hex: 0x3D5A6B), backdrop: .washi,
        isLight: true, onAccent: Color(hex: 0xFBF7EF), contrast: Color(hex: 0x2E2A24), shadowTint: Color(hex: 0x2E2A24),
        secondaryLevel: 0.82, tertiaryLevel: 0.75)

    static let all: [Theme] = [.atelier, .clair, .sepia, .brutal, .swiss, .synthwave, .terre, .washi, .architecte, .interieur, .soir, .encre, .sakura,
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

/// Choix de la palette (`Theme`) et du style (`AppStyle`), gardés entre deux lancements. Les valeurs publiées
/// rafraîchissent l'interface sans remplacer sa racine, afin de conserver les fenêtres et la navigation en cours.
@MainActor
final class ThemeManager: ObservableObject {
    @Published private(set) var theme: Theme
    @Published private(set) var style: AppStyle

    /// Apparence choisie (palette et style), visible tout de suite dans Réglages → Thèmes qui observe ce gestionnaire.
    var appearanceRevision: String { theme.id + "|" + style.id }
    /// Apparence appliquée à toute l'app : identité de la racine, mise à jour seulement à la fermeture des Réglages
    /// (`applyAppearance`). Les couleurs sont lues dans des valeurs globales que SwiftUI ne surveille pas : seule une
    /// reconstruction garantit que toutes les vues, UIKit et pages web comprises, prennent la nouvelle apparence ;
    /// la faire pendant le choix fermerait la feuille Réglages (revue Claude de 41e2ba5, constat 1).
    @Published private(set) var appliedAppearance: String = ""

    func applyAppearance() {
        if appliedAppearance != appearanceRevision { appliedAppearance = appearanceRevision }
    }

    init() {
        let id = UserDefaults.standard.string(forKey: "theme.id")
        let styleId = UserDefaults.standard.string(forKey: "style.id")
        let theme = Theme.all.first { $0.id == id } ?? .atelier
        let style = AppStyle.all.first { $0.id == styleId } ?? .atelier
        self.theme = theme
        self.style = style
        Theme.current = theme
        AppStyle.current = style
        appliedAppearance = theme.id + "|" + style.id
    }

    /// Choisir un style applique aussi sa palette proposée (décision du 29/10/2026) ; une autre palette peut être
    /// choisie ensuite, elle est gardée jusqu'au prochain changement de style.
    func select(style: AppStyle) {
        guard style != self.style else { return }
        UserDefaults.standard.set(style.id, forKey: "style.id")
        AppStyle.current = style
        if let palette = Theme.all.first(where: { $0.id == style.defaultTheme }), palette != theme {
            UserDefaults.standard.set(palette.id, forKey: "theme.id")
            Theme.current = palette
            theme = palette
        }
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
    /// Langue de l'interface (demande de NOxygen59 du 30/10/2026) : « AppleLanguages » propre à l'app, appliquée au
    /// relancement comme le prévoit iOS. Vide = langue du système.
    @State private var appLanguage = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])
        .flatMap { UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] != nil ? $0.first : nil }
        .map { $0.hasPrefix("en") ? "en" : "fr" } ?? ""
    @State private var languageChanged = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choisis ton style.").font(.title2.weight(.semibold))
                        .foregroundStyle(Atelier.textPrimary)
                    Text("Le style donne les formes, les bordures, les ombres et les polices. Il propose sa palette ; tu peux en choisir une autre juste en dessous. Les pages du manuel ne changent jamais.")
                        .font(.subheadline).foregroundStyle(Atelier.textSecondary)
                    Toggle("Motifs de fond", isOn: $patternsEnabled)
                        .font(.subheadline).tint(Atelier.Tint.read).padding(.top, 8)
                    AppLanguagePicker()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(AppStyle.all) { style in
                        Button { themes.select(style: style) } label: { styleCard(style) }
                            .buttonStyle(PressScale())
                            .accessibilityLabel(style.name)
                            .accessibilityValue(themes.style == style ? String(localized: "Sélectionné") : style.summary)
                            .accessibilityAddTraits(themes.style == style ? .isSelected : [])
                    }
                }
                Text("Palette").font(.title3.weight(.semibold)).foregroundStyle(Atelier.textPrimary).padding(.top, 6)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18)], spacing: 18) {
                    ForEach(Theme.all) { theme in
                        Button { themes.select(theme) } label: { card(theme) }
                            .buttonStyle(PressScale())
                            .accessibilityLabel(theme.name)
                            .accessibilityValue(themes.theme == theme ? String(localized: "Sélectionné") : theme.atmosphere)
                            .accessibilityAddTraits(themes.theme == theme ? .isSelected : [])
                    }
                }
            }
            .padding(22)
        }
        .background(Atelier.canvas)
        .navigationTitle("Thèmes")
    }

    /// Carte d'un style : son nom, sa ligne, et un échantillon dessiné avec ses propres formes et bordures.
    private func styleCard(_ s: AppStyle) -> some View {
        let on = themes.style == s
        let palette = Theme.all.first { $0.id == s.defaultTheme } ?? .atelier
        let corner = 14 * s.cornerScale
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(palette.surface)
                .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(s.panelEdge == .ink ? palette.ink : palette.read.opacity(s.panelEdge == .glow ? 0.9 : 0.4),
                                  lineWidth: s.borderScale))
                .overlay(Text("教").font(.custom("HiraMinProN-W6", size: 22)).foregroundStyle(palette.japanese))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(ui: s.name).font(.system(size: 15, weight: .semibold, design: s.fontDesign)).foregroundStyle(Atelier.textPrimary)
                Text(ui: s.summary).font(.system(size: 12, design: s.fontDesign)).foregroundStyle(Atelier.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(Atelier.font(20, weight: .medium))
                .foregroundStyle(on ? Atelier.Tint.read : Atelier.textTertiary)
        }
        .padding(12)
        .frame(minHeight: 76)
        .background(Atelier.surface, in: RoundedRectangle(cornerRadius: Atelier.corner(16), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Atelier.corner(16), style: .continuous)
            .strokeBorder(on ? Atelier.Tint.read : Atelier.hairline, lineWidth: on ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: Atelier.corner(16), style: .continuous))
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
                    Text(ui: t.name).font(Atelier.font(16, weight: .semibold)).foregroundStyle(t.ink)
                    Text(ui: t.atmosphere).font(Atelier.font(12)).foregroundStyle(t.secondaryInk)
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
