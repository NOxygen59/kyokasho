// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreText
import SwiftUI

/// Fonds du lot du 24/11/2026 (maquette `THEMES-ORIGINAUX-v3`, choisie par NOxygen59) : tirés de l'écriture et de
/// l'école japonaises plutôt que de dessins décoratifs. Mêmes règles que les autres fonds : aucun asset, aucune
/// animation, hasard fixé, nombre de tracés borné. Les kanji viennent des polices Hiragino livrées avec iOS.
extension ThemeBackdrop {
    private static var hair: CGFloat { 1 }

    /// Genkō : une feuille d'exercice 練習 verticale sur le bord droit. Le kanji modèle d'abord, puis ses copies qui
    /// pâlissent jusqu'aux cases vides ; croix de repère pointillées ; petit hanamaru rouge sur la meilleure copie.
    static func genko(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme) {
        let cell = min(40, s.height / 14), gap = cell * 0.25
        let left = s.width - 2 * (cell + gap) - cell * 0.5
        let fades: [Double] = [0.42, 0.26, 0.18, 0.12, 0.08, 0.05]
        let kanji = ["学", "読"]  // lu de droite à gauche : 読 (lire) puis 学 (apprendre)
        var frames = Path(), guides = Path()
        for column in 0..<2 {
            let x = left + CGFloat(column) * (cell + gap)
            var y = s.height * 0.16, row = 0
            while y < s.height - cell * 0.6 {
                let box = CGRect(x: x, y: y, width: cell, height: cell)
                frames.addRect(box)
                guides.move(to: CGPoint(x: box.midX, y: box.minY)); guides.addLine(to: CGPoint(x: box.midX, y: box.maxY))
                guides.move(to: CGPoint(x: box.minX, y: box.midY)); guides.addLine(to: CGPoint(x: box.maxX, y: box.midY))
                if row < fades.count {
                    c.draw(Text(kanji[column]).font(.custom("HiraMinProN-W3", size: cell * 0.72))
                        .foregroundColor(t.ink.opacity(fades[row])), at: CGPoint(x: box.midX, y: box.midY))
                }
                if column == 1, row == 2 { c.stroke(hanamaru(center: CGPoint(x: box.midX, y: box.midY), radius: cell * 0.62),
                                                    with: .color(t.japanese.opacity(0.55)), lineWidth: hair * 1.6) }
                y += cell; row += 1
            }
        }
        c.stroke(frames, with: .color(t.read.opacity(0.28)), lineWidth: hair)
        c.stroke(guides, with: .color(t.read.opacity(0.14)), style: StrokeStyle(lineWidth: hair, dash: [2, 3]))
        c.fill(Path(CGRect(x: left - cell * 0.35, y: 0, width: hair, height: s.height)), with: .color(t.read.opacity(0.18)))
    }

    /// Cercle festonné de la note はなまる (« fleur ») qu'un professeur dessine sur un bon devoir.
    private static func hanamaru(center: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        for step in 0...128 {
            let a = Double(step) / 128 * 2 * .pi
            let r = radius * CGFloat(1 + 0.12 * abs(sin(a * 3.5)))
            let point = CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
            if step == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p
    }

    /// Riso : kanji géant 読 imprimé en trame de points, passage rose puis passage bleu décalé de quelques points,
    /// comme une affiche risographie mal calée. Les points grossissent vers la droite (le centre reste calme).
    static func riso(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme) {
        let m = min(s.width, s.height)
        guard let glyph = glyphPath("読", font: "HiraginoSans-W8", size: m * 0.78,
                                    center: CGPoint(x: s.width * 0.74, y: s.height * 0.56)) else { return }
        let step = max(6, m / 80), bounds = glyph.boundingRect
        var dots = Path()
        var x = (bounds.minX / step).rounded(.down) * step + step / 2
        while x < bounds.maxX {
            var y = (bounds.minY / step).rounded(.down) * step + step / 2
            let radius = step * 0.36 * min(1, max(0.25, x / s.width))
            while y < bounds.maxY {
                if glyph.contains(CGPoint(x: x, y: y)) {
                    dots.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                }
                y += step
            }
            x += step
        }
        c.fill(dots.applying(CGAffineTransform(translationX: 5, y: 4)), with: .color(t.read.opacity(0.16)))
        c.fill(dots, with: .color(t.japanese.opacity(0.22)))
    }

    /// Shōwa : arcs-en-ciel à bandes des années 70 dans le coin bas droit, soleil à rayons fins en haut à gauche.
    static func showa(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme) {
        let m = min(s.width, s.height), band = m * 0.045
        for (i, color) in [t.read, t.annotate, t.japanese, t.cloud].enumerated() {
            var arc = Path()
            arc.addArc(center: CGPoint(x: s.width, y: s.height), radius: m * 0.32 + CGFloat(i) * band,
                       startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            c.stroke(arc, with: .color(color.opacity(0.20)), lineWidth: band * 0.8)
        }
        var rays = Path()
        for k in 0..<22 {
            let a = Double(k) / 22 * .pi / 2
            rays.move(to: .zero)
            rays.addLine(to: CGPoint(x: CGFloat(cos(a)) * m * 0.7, y: CGFloat(sin(a)) * m * 0.7))
        }
        c.stroke(rays, with: .color(t.read.opacity(0.06)), lineWidth: hair)
        c.fill(Path(ellipseIn: CGRect(x: -m * 0.09, y: -m * 0.09, width: m * 0.18, height: m * 0.18)),
               with: .color(t.annotate.opacity(0.12)))
    }

    /// Kokuban : traces de brosse mal effacée, et à droite, à la craie et en vertical, la date du jour en kanji et
    /// 日直 (élève de service), comme sur les tableaux des classes japonaises. Le fond change donc chaque jour.
    static func kokuban(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme, date: Date = Date()) {
        var rng = Seeded(5)
        let m = min(s.width, s.height)
        for _ in 0..<5 {
            let center = CGPoint(x: s.width * CGFloat(rng.next(0.15, 0.85)), y: s.height * CGFloat(rng.next(0.2, 0.8)))
            let radius = m * CGFloat(rng.next(0.25, 0.5)), start = rng.next(0, 6), span = rng.next(0.9, 1.7)
            let brush = m * 0.09
            for line in 0..<14 {
                var arc = Path()
                arc.addArc(center: center, radius: radius - brush / 2 + CGFloat(line) * brush / 14,
                           startAngle: .radians(start), endAngle: .radians(start + span), clockwise: false)
                c.stroke(arc, with: .color(t.ink.opacity(rng.next(0.03, 0.08))), lineWidth: hair * CGFloat(rng.next(1, 4)))
            }
        }
        let size = min(30, s.height / 22), x = s.width - size * 1.1
        let parts = Calendar(identifier: .gregorian).dateComponents([.month, .day, .weekday], from: date)
        let weekday = Array("日月火水木金土")[(parts.weekday ?? 1) - 1]
        let line = "\(kanjiNumber(parts.month ?? 1))月\(kanjiNumber(parts.day ?? 1))日\(weekday)曜"
        chalk(&c, line, x: x, top: size * 0.8, size: size, color: t.ink.opacity(0.30))
        chalk(&c, "日直", x: x, top: s.height - size * 4.2, size: size * 0.9, color: t.read.opacity(0.32))
        c.fill(Path(CGRect(x: 0, y: s.height - 8, width: s.width, height: 8)), with: .color(t.ink.opacity(0.10)))
        for (i, color) in [t.ink, t.read, t.japanese, t.cloud].enumerated() {
            c.fill(Path(CGRect(x: s.width * 0.08 + CGFloat(i) * 26, y: s.height - 13, width: 18, height: 6)),
                   with: .color(color.opacity(0.35)))
        }
    }

    /// Texte vertical à la craie, un caractère sous l'autre.
    private static func chalk(_ c: inout GraphicsContext, _ text: String, x: CGFloat, top: CGFloat, size: CGFloat, color: Color) {
        for (i, ch) in text.enumerated() {
            c.draw(Text(String(ch)).font(.custom("HiraMinProN-W3", size: size)).foregroundColor(color),
                   at: CGPoint(x: x, y: top + CGFloat(i) * size * 1.08), anchor: .top)
        }
    }

    /// Nombre de 1 à 99 en kanji (十一, 二十四), pour la date du tableau.
    static func kanjiNumber(_ n: Int) -> String {
        let digits = Array("〇一二三四五六七八九")
        guard n >= 10 else { return String(digits[max(0, n)]) }
        let tens = n / 10, ones = n % 10
        return (tens == 1 ? "" : String(digits[tens])) + "十" + (ones == 0 ? "" : String(digits[ones]))
    }

    /// Contour : kanji géant 学 coupé par le bord, dessiné seulement par ses contours successifs (courbes de niveau).
    /// Chaque anneau = un trait large de la teinte, puis un trait un peu plus fin couleur du fond qui l'évide.
    static func contour(_ c: inout GraphicsContext, _ s: CGSize, _ t: Theme) {
        let m = min(s.width, s.height)
        guard let glyph = glyphPath("学", font: "HiraginoSans-W6", size: m * 0.95,
                                    center: CGPoint(x: s.width * 0.26, y: s.height * 0.6)) else { return }
        let rings = 8
        for i in stride(from: rings, through: 1, by: -1) {
            let width = CGFloat(i) * m * 0.026
            c.stroke(glyph, with: .color(t.read.opacity(0.07 + Double(rings - i) * 0.022)),
                     style: StrokeStyle(lineWidth: width, lineJoin: .round))
            c.stroke(glyph, with: .color(t.canvas), style: StrokeStyle(lineWidth: width - hair * 2.4, lineJoin: .round))
        }
        c.fill(glyph, with: .color(t.canvas))
        c.stroke(glyph, with: .color(t.annotate.opacity(0.35)), lineWidth: hair * 1.4)
    }

    /// Contour d'un caractère, centré sur `center` (CoreText compte les y vers le haut : on retourne le tracé).
    static func glyphPath(_ character: String, font name: String, size: CGFloat, center: CGPoint) -> Path? {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        var units = Array(character.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count),
              let outline = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { return nil }
        let box = outline.boundingBox
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: center.x - box.midX, ty: center.y + box.midY)
        return Path(outline).applying(flip)
    }
}
