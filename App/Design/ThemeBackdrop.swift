// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Fond dessiné d'un thème (bibliothèque, dictionnaire, aperçu des thèmes). Tout est tracé ici, en traits fins et
/// très peu opaques, sans image ni animation (batterie) ; le hasard est fixé (même dessin à chaque affichage).
struct ThemeBackdrop: View {
    let theme: Theme
    /// La palette reste indépendante du style ; les aperçus de palettes passent explicitement nil.
    var style: AppStyle? = .current
    @AppStorage("appearance.themePatterns") private var patternsEnabled = true

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.canvas))
            guard patternsEnabled else { return }
            // Lueur périphérique légère : le centre reste calme sous les documents.
            let rect = Path(CGRect(origin: .zero, size: size))
            let light = CGPoint(x: size.width * 0.95, y: 0)
            context.fill(rect, with: .radialGradient(Gradient(colors: [theme.read.opacity(0.065), .clear]),
                         center: light, startRadius: 0, endRadius: max(size.width, size.height) * 0.9))
            switch effectiveBackdrop {
            case .plain: break
            case .grid: Self.grid(&context, size, color: theme.read, minor: 0.035, major: 0.075, spacing: 32)
            case .paper: Self.paper(&context, size, theme)
            case .engraving: Self.engraving(&context, size, theme)
            case .blocks: Self.blocks(&context, size, theme)
            case .swiss: Self.swiss(&context, size, theme)
            case .neon: Self.neon(&context, size, theme)
            case .earth: Self.earth(&context, size, theme)
            case .forest: Self.forest(&context, size, theme)
            case .embers: Self.embers(&context, size, theme)
            case .dunes: Self.contours(&context, size, theme, water: false)
            case .waves: Self.contours(&context, size, theme, water: true)
            case .washi: Self.washi(&context, size, theme)
            case .blueprint: Self.blueprint(&context, size, theme)
            case .floorplan: Self.floorplan(&context, size, theme)
            case .dusk: Self.dusk(&context, size, theme)
            case .ink: Self.ink(&context, size, theme)
            case .sakura: Self.sakura(&context, size, theme)
            }
            if let style { Self.signature(&context, size, theme, style) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// La palette garde son motif (Sakura reste Sakura) et le style ajoute sa signature. Seuls les styles dont l'identité
    /// tient au fond l'imposent : le verre reste nu, et les styles numériques ne récupèrent ni feuilles ni vagues.
    /// Aucune préférence enregistrée n'est réécrite.
    private var effectiveBackdrop: Theme.Backdrop {
        switch style?.id {
        case "cybercore", "cyberpunk", "pixel": return .grid
        case "glass": return .plain
        case "minimalism", "editorial", "clay", "neumorphism": return .plain
        case "scrapbook": return .paper
        default: return theme.backdrop
        }
    }

    // MARK: Motifs

    /// Papier millimétré d'atelier (le fond d'origine).
    static func grid(_ c: inout GraphicsContext, _ size: CGSize, color: Color, minor: Double, major: Double,
                     spacing: CGFloat = 28) {
        func lines(every step: CGFloat) -> Path {
            var p = Path()
            var x: CGFloat = 0
            while x <= size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            return p
        }
        c.stroke(lines(every: spacing), with: .color(color.opacity(minor)), lineWidth: 0.5)
        c.stroke(lines(every: spacing * 5), with: .color(color.opacity(major)), lineWidth: 0.6)
    }

    /// Papier washi : fibres courtes et longues dans tous les sens, quelques nuages plus clairs.
    static func washi(_ c: inout GraphicsContext, _ size: CGSize, _ t: Theme) {
        var rng = Seeded(7)
        for _ in 0..<6 {
            let r = CGFloat(rng.next(120, 340))
            let center = CGPoint(x: CGFloat(rng.next(0, 1)) * size.width, y: CGFloat(rng.next(0, 1)) * size.height)
            c.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r * 0.7, width: 2 * r, height: 1.4 * r)),
                   with: .radialGradient(Gradient(colors: [t.ink.opacity(0.035), .clear]), center: center,
                                         startRadius: 0, endRadius: r))
        }
        let count = min(600, Int(size.width * size.height / 1100))
        var fibers = Path(), long = Path()
        for i in 0..<count {
            let start = CGPoint(x: CGFloat(rng.next(0, 1)) * size.width, y: CGFloat(rng.next(0, 1)) * size.height)
            let isLong = i % 9 == 0
            let length = CGFloat(isLong ? rng.next(40, 110) : rng.next(6, 22))
            let angle = rng.next(0, .pi * 2)
            let end = CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
            let bend = CGPoint(x: (start.x + end.x) / 2 + CGFloat(rng.next(-8, 8)),
                               y: (start.y + end.y) / 2 + CGFloat(rng.next(-8, 8)))
            var p = Path()
            p.move(to: start)
            p.addQuadCurve(to: end, control: bend)
            if isLong { long.addPath(p) } else { fibers.addPath(p) }
        }
        c.stroke(fibers, with: .color(t.ink.opacity(0.055)), lineWidth: 0.6)
        c.stroke(long, with: .color(t.ink.opacity(0.075)), lineWidth: 0.8)
    }

    /// Plan bleu d'architecte : grille dans la couleur de lecture, cotes le long des bords, repères de trame.
    static func blueprint(_ c: inout GraphicsContext, _ size: CGSize, _ t: Theme) {
        grid(&c, size, color: t.read, minor: 0.035, major: 0.085, spacing: 24)
        let ink = t.read.opacity(0.24)
        var cotes = Path()
        // Cotes horizontales en haut, verticales à gauche : trait, petites barres obliques aux extrémités.
        let y = 36.0, x = 36.0
        for (a, b) in [(0.08, 0.34), (0.34, 0.62), (0.62, 0.9)] {
            let x0 = size.width * a, x1 = size.width * b
            cotes.move(to: CGPoint(x: x0, y: y)); cotes.addLine(to: CGPoint(x: x1, y: y))
            for xe in [x0, x1] { cotes.move(to: CGPoint(x: xe - 4, y: y + 4)); cotes.addLine(to: CGPoint(x: xe + 4, y: y - 4)) }
            c.draw(Text(verbatim: "\(Int((b - a) * 10000))").font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(ink), at: CGPoint(x: (x0 + x1) / 2, y: y - 9))
        }
        for (a, b) in [(0.12, 0.48), (0.48, 0.86)] {
            let y0 = size.height * a, y1 = size.height * b
            cotes.move(to: CGPoint(x: x, y: y0)); cotes.addLine(to: CGPoint(x: x, y: y1))
            for ye in [y0, y1] { cotes.move(to: CGPoint(x: x - 4, y: ye + 4)); cotes.addLine(to: CGPoint(x: x + 4, y: ye - 4)) }
        }
        c.stroke(cotes, with: .color(ink), lineWidth: 0.8)
        // Repères de trame (cercles numérotés) en bas.
        for (i, a) in [0.2, 0.5, 0.8].enumerated() {
            let center = CGPoint(x: size.width * a, y: size.height - 30)
            c.stroke(Path(ellipseIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)),
                     with: .color(ink), lineWidth: 0.8)
            c.draw(Text(String(UnicodeScalar(65 + i)!)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(ink),
                   at: center)
        }
    }

    /// Plan d'intérieur discret : murs, cloisons, portes (arc d'ouverture), fenêtres, en bas à droite.
    static func floorplan(_ c: inout GraphicsContext, _ size: CGSize, _ t: Theme) {
        grid(&c, size, color: t.read, minor: 0.018, major: 0.04, spacing: 32)
        let w = min(size.width * 0.62, 900), h = w * 0.62
        let o = CGPoint(x: size.width - w - size.width * 0.04, y: size.height - h - size.height * 0.05)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * w, y: o.y + y * h) }
        // Matières vues en plan : aplat de chêne, lames espacées, pièces ouvertes.
        c.fill(Path(CGRect(origin: pt(0, 0), size: CGSize(width: w * 0.42, height: h * 0.55))),
               with: .color(t.read.opacity(0.045)))
        var boards = Path()
        for i in 1..<10 {
            let x = CGFloat(i) * 0.042
            boards.move(to: pt(x, 0)); boards.addLine(to: pt(x, 0.55))
        }
        c.stroke(boards, with: .color(t.read.opacity(0.07)), lineWidth: 0.5)
        let wall = t.ink.opacity(0.11), detail = t.read.opacity(0.20)
        var walls = Path()
        walls.addRect(CGRect(origin: o, size: CGSize(width: w, height: h)))
        // Cloisons (avec les vides des portes).
        walls.move(to: pt(0.42, 0)); walls.addLine(to: pt(0.42, 0.38))
        walls.move(to: pt(0.42, 0.52)); walls.addLine(to: pt(0.42, 1))
        walls.move(to: pt(0.42, 0.6)); walls.addLine(to: pt(0.7, 0.6))
        walls.move(to: pt(0.82, 0.6)); walls.addLine(to: pt(1, 0.6))
        walls.move(to: pt(0, 0.55)); walls.addLine(to: pt(0.24, 0.55))
        walls.move(to: pt(0.34, 0.55)); walls.addLine(to: pt(0.42, 0.55))
        c.stroke(walls, with: .color(wall), lineWidth: 3)
        var doors = Path()
        for (hinge, leaf, start) in [(pt(0.42, 0.38), 0.14 * h, 90.0), (pt(0.7, 0.6), 0.12 * w, 0.0),
                                     (pt(0.24, 0.55), 0.1 * w, 0.0)] {
            doors.move(to: hinge)
            doors.addLine(to: CGPoint(x: hinge.x + leaf * cos(start * .pi / 180), y: hinge.y - leaf * sin(start * .pi / 180)))
            doors.addArc(center: hinge, radius: leaf, startAngle: .degrees(-start), endAngle: .degrees(-start + 90),
                         clockwise: false)
        }
        // Fenêtres : double trait dans le mur du haut.
        for (a, b) in [(0.1, 0.3), (0.55, 0.85)] {
            for dy in [-3.0, 3.0] {
                doors.move(to: CGPoint(x: pt(a, 0).x, y: o.y + dy)); doors.addLine(to: CGPoint(x: pt(b, 0).x, y: o.y + dy))
            }
        }
        // Mobilier : table ronde et canapé.
        doors.addEllipse(in: CGRect(x: pt(0.68, 0.2).x, y: pt(0.68, 0.2).y, width: 0.12 * w, height: 0.12 * w))
        doors.addRoundedRect(in: CGRect(x: pt(0.06, 0.7).x, y: pt(0.06, 0.7).y, width: 0.26 * w, height: 0.12 * h),
                             cornerSize: CGSize(width: 6, height: 6))
        c.stroke(doors, with: .color(detail), lineWidth: 0.9)
    }

    /// Lumière du soir : dégradé du fond vers une lueur chaude en bas, soleil voilé.
    static func dusk(_ c: inout GraphicsContext, _ size: CGSize, _ t: Theme) {
        let rect = CGRect(origin: .zero, size: size)
        c.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [.init(color: .clear, location: 0), .init(color: t.ai.opacity(0.05), location: 0.55),
                             .init(color: t.read.opacity(0.12), location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let sun = CGPoint(x: size.width * 0.72, y: size.height * 0.92)
        c.fill(Path(rect), with: .radialGradient(Gradient(colors: [t.annotate.opacity(0.12), .clear]), center: sun,
                                                 startRadius: 0, endRadius: max(size.width, size.height) * 0.45))
        // Horizon lointain : deux lignes de collines très douces.
        for (k, alpha) in [(0.8, 0.05), (0.88, 0.07)] {
            var hill = Path()
            hill.move(to: CGPoint(x: 0, y: size.height))
            hill.addLine(to: CGPoint(x: 0, y: size.height * k))
            hill.addCurve(to: CGPoint(x: size.width, y: size.height * (k - 0.03)),
                          control1: CGPoint(x: size.width * 0.3, y: size.height * (k - 0.08)),
                          control2: CGPoint(x: size.width * 0.6, y: size.height * (k + 0.05)))
            hill.addLine(to: CGPoint(x: size.width, y: size.height))
            c.fill(hill, with: .color(Color.black.opacity(alpha * 3)))
        }
    }

    /// Encre et or : grands traits de pinceau dorés à peine visibles, filet doré le long des bords.
    static func ink(_ c: inout GraphicsContext, _ size: CGSize, _ t: Theme) {
        var rng = Seeded(3)
        for k in 0..<3 {
            var stroke = Path()
            let y = size.height * (0.25 + 0.28 * CGFloat(k))
            stroke.move(to: CGPoint(x: -20, y: y + CGFloat(rng.next(-40, 40))))
            stroke.addCurve(to: CGPoint(x: size.width + 20, y: y + CGFloat(rng.next(-60, 60))),
                            control1: CGPoint(x: size.width * 0.3, y: y + CGFloat(rng.next(-120, 120))),
                            control2: CGPoint(x: size.width * 0.7, y: y + CGFloat(rng.next(-120, 120))))
            c.stroke(stroke, with: .color(t.read.opacity(0.035)), style: StrokeStyle(lineWidth: CGFloat(rng.next(10, 26)), lineCap: .round))
            c.stroke(stroke, with: .color(t.read.opacity(0.085)), lineWidth: 0.6)
        }
        c.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: 24, dy: 24)), with: .color(t.read.opacity(0.16)), lineWidth: 0.6)
        c.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: 29, dy: 29)), with: .color(t.read.opacity(0.1)), lineWidth: 0.4)
    }

    /// Sakura : quelques pétales posés, plus nombreux vers le coin haut droit.
    static func sakura(_ c: inout GraphicsContext, _ size: CGSize, _ t: Theme) {
        var branch = Path()
        branch.move(to: CGPoint(x: size.width * 1.02, y: size.height * 0.02))
        branch.addCurve(to: CGPoint(x: size.width * 0.65, y: size.height * 0.34),
                        control1: CGPoint(x: size.width * 0.86, y: size.height * 0.11),
                        control2: CGPoint(x: size.width * 0.89, y: size.height * 0.25))
        c.stroke(branch, with: .color(t.japanese.opacity(0.11)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        var rng = Seeded(11)
        let count = min(72, max(12, Int(size.width * size.height / 14000)))
        for _ in 0..<count {
            // Tirage biaisé vers le coin haut droit.
            let u = rng.next(0, 1), v = rng.next(0, 1)
            let p = CGPoint(x: size.width * CGFloat(1 - u * u), y: size.height * CGFloat(v * v))
            let s = CGFloat(rng.next(5, 12))
            var petal = Path()
            petal.move(to: CGPoint(x: 0, y: -s * 0.65))
            petal.addLine(to: CGPoint(x: s * 0.28, y: -s))
            petal.addCurve(to: CGPoint(x: 0, y: s), control1: CGPoint(x: s * 1.1, y: -s * 0.4),
                          control2: CGPoint(x: s * 0.8, y: s * 0.5))
            petal.addCurve(to: CGPoint(x: -s * 0.28, y: -s), control1: CGPoint(x: -s * 0.8, y: s * 0.5),
                          control2: CGPoint(x: -s * 1.1, y: -s * 0.4))
            petal.closeSubpath()
            let placed = petal.applying(CGAffineTransform(rotationAngle: CGFloat(rng.next(0, .pi * 2)))
                .concatenating(CGAffineTransform(translationX: p.x, y: p.y)))
            c.fill(placed, with: .color(t.japanese.opacity(rng.next(0.07, 0.18))))
        }
    }
}

/// Hasard reproductible (même dessin à chaque affichage).
struct Seeded {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }

    mutating func next(_ low: Double, _ high: Double) -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return low + Double(state % 1_000_000) / 1_000_000 * (high - low)
    }
}
