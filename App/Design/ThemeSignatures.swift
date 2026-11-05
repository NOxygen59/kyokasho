// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Dessins originaux des palettes et signatures des styles. Réservés au fond de l'interface, jamais au PDF.
/// Nombre de tracés borné, aucune animation, image, police externe ou couche de flou supplémentaire.
extension ThemeBackdrop {
    private static var fine: CGFloat { 0.8 }

    static func paper(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme) {
        // Feuille blanche : grande marge de cahier et lignes espacées, sans quadrillage technique.
        var p = Path()
        let margin = min(64, s.width * 0.12)
        p.move(to: CGPoint(x: margin, y: 0)); p.addLine(to: CGPoint(x: margin, y: s.height))
        for i in 1...min(60, max(1, Int(s.height / 34))) {
            let y = CGFloat(i) * 34
            p.move(to: CGPoint(x: margin + 18, y: y)); p.addLine(to: CGPoint(x: s.width, y: y))
        }
        c.stroke(p, with: .color(t.read.opacity(0.10)), lineWidth: fine)
    }

    static func engraving(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme) {
        // Sépia : filet de livre ancien et rosaces gravées dans les coins.
        let rect = CGRect(origin: .zero, size: s).insetBy(dx: 18, dy: 18)
        c.stroke(Path(rect), with: .color(t.annotate.opacity(0.20)), lineWidth: fine)
        for point in [CGPoint(x: 18, y: 18), CGPoint(x: s.width - 18, y: s.height - 18)] {
            for k in 0..<5 {
                let radius = CGFloat(12 + k * 9)
                c.stroke(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                               width: radius * 2, height: radius * 2)),
                         with: .color(t.annotate.opacity(0.10)), lineWidth: fine)
            }
        }
    }

    static func blocks(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme) {
        // Brutal : aplats francs, sans transparence vitrée ni détail pseudo artisanal.
        let w = min(110, s.width * 0.27)
        let rect = CGRect(x: s.width - w - 18, y: 20, width: w, height: w * 0.62)
        c.fill(Path(rect.offsetBy(dx: 7, dy: 7)), with: .color(t.ink.opacity(0.15)))
        c.fill(Path(rect), with: .color(t.read.opacity(0.40)))
        c.stroke(Path(rect), with: .color(t.ink.opacity(0.55)), lineWidth: fine * 2)
        c.fill(Path(ellipseIn: CGRect(x: 18, y: s.height - w * 0.6, width: w, height: w)),
               with: .color(t.japanese.opacity(0.14)))
    }

    static func swiss(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme) {
        // Composition suisse asymétrique : bande rouge, colonne, grand cercle recadré.
        c.fill(Path(CGRect(x: 0, y: 0, width: max(5, s.width * 0.018), height: s.height)),
               with: .color(t.read.opacity(0.7)))
        var p = Path()
        p.move(to: CGPoint(x: s.width * 0.68, y: 0)); p.addLine(to: CGPoint(x: s.width * 0.68, y: s.height))
        p.move(to: CGPoint(x: 0, y: s.height * 0.68)); p.addLine(to: CGPoint(x: s.width, y: s.height * 0.68))
        c.stroke(p, with: .color(t.ink.opacity(0.13)), lineWidth: fine)
        let d = min(s.width, s.height) * 0.65
        c.stroke(Path(ellipseIn: CGRect(x: s.width - d * 0.65, y: -d * 0.4, width: d, height: d)),
                 with: .color(t.read.opacity(0.17)), lineWidth: fine * 6)
    }

    static func neon(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme) {
        // Horizon rétrospectif : soleil rayé et perspective. Le dessin ne bouge jamais.
        let horizon = s.height * 0.65
        let radius = min(s.width * 0.17, s.height * 0.28)
        let sun = CGRect(x: s.width * 0.76 - radius, y: horizon - radius * 2.1,
                         width: radius * 2, height: radius * 2)
        var clipped = c
        clipped.clip(to: Path(ellipseIn: sun))
        for k in 0..<10 {
            let y = sun.minY + CGFloat(k) * sun.height / 10
            clipped.fill(Path(CGRect(x: sun.minX, y: y, width: sun.width, height: sun.height / 15)),
                         with: .color(t.japanese.opacity(0.28)))
        }
        var grid = Path()
        for k in -8...8 {
            grid.move(to: CGPoint(x: s.width * 0.5, y: horizon))
            grid.addLine(to: CGPoint(x: s.width * 0.5 + CGFloat(k) * s.width * 0.22, y: s.height))
        }
        for k in 0..<8 {
            let fraction = pow(CGFloat(k) / 7, 1.7)
            let y = horizon + fraction * (s.height - horizon)
            grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: s.width, y: y))
        }
        c.stroke(grid, with: .color(t.read.opacity(0.17)), lineWidth: fine)
    }

    static func earth(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme) {
        // Argile : galets et strates, une matière organique distincte des fibres washi.
        for k in 0..<4 {
            let w = s.width * (0.36 + Double(k) * 0.035)
            let rect = CGRect(x: s.width * 0.80 - w / 2, y: s.height * 0.08 + CGFloat(k) * 12,
                              width: w, height: w * 0.72)
            c.stroke(Path(ellipseIn: rect), with: .color(t.annotate.opacity(0.11)), lineWidth: fine * 1.5)
        }
        contours(&c, s, t, water: false)
    }

    static func forest(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme) {
        // Frondes diagonales : feuilles au bord, centre de lecture dégagé.
        var stems = Path(), leaves = Path()
        for side in 0..<2 {
            let origin = CGPoint(x: side == 0 ? -12 : s.width + 12, y: side == 0 ? s.height * 0.8 : 0)
            let sign: CGFloat = side == 0 ? 1 : -1
            for k in 0..<9 {
                let y = origin.y + CGFloat(k) * (side == 0 ? -22 : 22)
                let point = CGPoint(x: origin.x + sign * CGFloat(k * 9), y: y)
                stems.move(to: CGPoint(x: origin.x, y: origin.y)); stems.addLine(to: point)
                leaves.move(to: point)
                leaves.addQuadCurve(to: CGPoint(x: point.x + sign * 48, y: y - 16),
                                    control: CGPoint(x: point.x + sign * 18, y: y - 34))
                leaves.addQuadCurve(to: point, control: CGPoint(x: point.x + sign * 30, y: y + 12))
            }
        }
        c.stroke(stems, with: .color(t.read.opacity(0.15)), lineWidth: fine)
        c.fill(leaves, with: .color(t.read.opacity(0.10)))
    }

    static func embers(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme) {
        let origin = CGPoint(x: s.width * 0.84, y: s.height)
        c.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(
            Gradient(colors: [t.japanese.opacity(0.24), .clear]), center: origin,
            startRadius: 0, endRadius: max(s.width, s.height) * 0.7))
        var rng = Seeded(43)
        var sparks = Path()
        for _ in 0..<32 {
            let x = s.width * CGFloat(rng.next(0.25, 1)), y = s.height * CGFloat(rng.next(0.2, 1))
            let length = CGFloat(rng.next(2, 8))
            sparks.move(to: CGPoint(x: x, y: y)); sparks.addLine(to: CGPoint(x: x + 2, y: y - length))
        }
        c.stroke(sparks, with: .color(t.annotate.opacity(0.28)), style: StrokeStyle(lineWidth: fine, lineCap: .round))
    }

    static func contours(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme, water: Bool) {
        var p = Path()
        for k in 0..<8 {
            let y = s.height * (0.57 + CGFloat(k) * 0.065)
            p.move(to: CGPoint(x: -20, y: y))
            p.addCurve(to: CGPoint(x: s.width + 20, y: y - s.height * 0.10),
                       control1: CGPoint(x: s.width * 0.28, y: y - s.height * (water ? 0.24 : 0.13)),
                       control2: CGPoint(x: s.width * 0.65, y: y + s.height * (water ? 0.21 : 0.10)))
        }
        c.stroke(p, with: .color((water ? t.cloud : t.read).opacity(water ? 0.22 : 0.17)), lineWidth: fine)
        if water {
            let center = CGPoint(x: s.width * 0.85, y: s.height * 0.18)
            c.stroke(Path(ellipseIn: CGRect(x: center.x - 24, y: center.y - 24, width: 48, height: 48)),
                     with: .color(t.annotate.opacity(0.32)), lineWidth: fine * 2)
        }
    }

    /// Signatures des styles : la couleur reste celle de la palette choisie indépendamment.
    /// Ces motifs complètent les vrais arrondis, polices, cadres et reliefs portés par AppStyle.
    static func signature(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme, _ style: AppStyle) {
        let bounds = CGRect(origin: .zero, size: s)
        let unit = min(s.width, s.height)
        let anchor = CGPoint(x: s.width * 0.82, y: s.height * 0.23)
        var p = Path()
        let color = t.read.opacity(0.22)
        switch style.id {
        case "atelier": return
        case "brutalism":
            if t.backdrop != .blocks { blocks(&c, s, t) }
        case "swiss", "editorial", "minimalism", "bento":
            let inset: CGFloat = style.id == "minimalism" ? 28 : 16
            let rect = bounds.insetBy(dx: inset, dy: inset)
            if style.id == "bento" {
                for row in 0..<2 { for column in 0..<3 {
                    let tile = CGRect(x: CGFloat(column) * s.width / 3 + 8,
                                      y: CGFloat(row) * s.height / 2 + 8,
                                      width: s.width / 3 - 16, height: s.height / 2 - 16)
                    p.addRoundedRect(in: tile, cornerSize: CGSize(width: 14, height: 14))
                } }
            } else {
                p.move(to: rect.origin); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                if style.id != "minimalism" {
                    p.move(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    p.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY))
                    p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY))
                }
            }
            c.stroke(p, with: .color(color), lineWidth: fine)
        case "glass", "ethereal", "y2k", "surrealism", "clay", "neumorphism":
            let count = style.id == "y2k" ? 5 : 3
            for k in 0..<count {
                let r = unit * (0.12 + CGFloat(k) * 0.055)
                let rect = CGRect(x: anchor.x - r - CGFloat(k) * 10, y: anchor.y - r + CGFloat(k) * 8,
                                  width: r * 2, height: r * (style.id == "surrealism" ? 1.15 : 2))
                let shape = Path(roundedRect: rect, cornerRadius: style.id == "clay" ? r * 0.45 : r)
                c.fill(shape, with: .color((k.isMultiple(of: 2) ? t.ai : t.cloud).opacity(style.id == "clay" ? 0.15 : 0.07)))
                c.stroke(shape, with: .color(t.contrast.opacity(style.id == "neumorphism" ? 0.10 : 0.24)), lineWidth: fine)
            }
        case "synthwave": if t.backdrop != .neon { neon(&c, s, t) }
        case "cybercore", "cyberpunk", "pixel":
            let step: CGFloat = style.id == "pixel" ? 12 : 22
            for k in 0..<12 {
                let x = s.width - CGFloat(k + 1) * step
                let y = s.height * 0.82 + CGFloat(k % 3) * 8
                if style.id == "pixel" {
                    p.addRect(CGRect(x: x, y: y, width: step - 3, height: step - 3))
                } else {
                    p.move(to: CGPoint(x: x, y: s.height)); p.addLine(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x - step, y: y - step))
                    p.addEllipse(in: CGRect(x: x - step - 2, y: y - step - 2, width: 4, height: 4))
                }
            }
            c.stroke(p, with: .color(style.id == "cyberpunk" ? t.cloud.opacity(0.45) : color),
                     lineWidth: fine * (style.id == "pixel" ? 2 : 1))
            if style.id == "cyberpunk" {
                c.fill(Path(CGRect(x: 0, y: 0, width: 9, height: s.height)), with: .color(t.read.opacity(0.75)))
                var warning = Path()
                for k in 0..<5 {
                    let x = s.width - 110 + CGFloat(k) * 18
                    warning.move(to: CGPoint(x: x, y: 16)); warning.addLine(to: CGPoint(x: x + 9, y: 7))
                }
                c.stroke(warning, with: .color(t.read.opacity(0.70)),
                         style: StrokeStyle(lineWidth: fine * 4, lineCap: .square))
            }
        case "luxury", "victorian":
            for inset in [14.0, 20.0] {
                c.stroke(Path(bounds.insetBy(dx: inset, dy: inset)), with: .color(color), lineWidth: fine)
            }
            if style.id == "victorian" {
                for k in 0..<4 {
                    let x = k.isMultiple(of: 2) ? 28.0 : s.width - 28
                    let y = k < 2 ? 28.0 : s.height - 28
                    p.addEllipse(in: CGRect(x: x - 15, y: y - 8, width: 30, height: 16))
                    p.addEllipse(in: CGRect(x: x - 8, y: y - 15, width: 16, height: 30))
                }
                c.stroke(p, with: .color(color), lineWidth: fine)
            }
        case "scrapbook":
            for x in [s.width * 0.16, s.width * 0.75] {
                let rect = CGRect(x: x, y: 10, width: 58, height: 18)
                c.fill(Path(rect).applying(CGAffineTransform(translationX: -8, y: 0)),
                       with: .color(t.annotate.opacity(0.22)))
                c.stroke(Path(rect.insetBy(dx: -3, dy: -3)), with: .color(color),
                         style: StrokeStyle(lineWidth: fine, dash: [3, 4]))
            }
        case "sketch":
            for offset in [0.0, 3.0] {
                p.move(to: CGPoint(x: 16, y: 20 + offset))
                p.addQuadCurve(to: CGPoint(x: s.width - 20, y: 17 + offset),
                               control: CGPoint(x: s.width * 0.4, y: 25 + offset))
                p.move(to: CGPoint(x: 20 + offset, y: 16)); p.addLine(to: CGPoint(x: 17 + offset, y: s.height - 18))
            }
            c.stroke(p, with: .color(color), lineWidth: fine)
        case "wabisabi", "bohemian":
            let r = unit * 0.24
            p.addArc(center: anchor, radius: r, startAngle: .degrees(20), endAngle: .degrees(330), clockwise: false)
            c.stroke(p, with: .color(t.annotate.opacity(0.14)),
                     style: StrokeStyle(lineWidth: style.id == "wabisabi" ? 9 : 2, lineCap: .round))
            if style.id == "bohemian" {
                for k in 0..<7 {
                    let x = s.width * 0.68 + CGFloat(k) * 9
                    var line = Path(); line.move(to: CGPoint(x: x, y: s.height - 35))
                    line.addLine(to: CGPoint(x: x, y: s.height))
                    c.stroke(line, with: .color(color), lineWidth: fine)
                }
            }
        case "maximalism":
            for k in 0..<7 {
                let x = CGFloat(k) * s.width / 6
                let shape = Path(ellipseIn: CGRect(x: x - 18, y: s.height - 46 + CGFloat(k % 2) * 12, width: 52, height: 52))
                c.fill(shape, with: .color((k.isMultiple(of: 2) ? t.japanese : t.ai).opacity(0.23)))
            }
        default: break
        }
    }
}
