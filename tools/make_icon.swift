// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59
// Dessine l'icône de l'app (1024 px, sans transparence) : swiftc tools/make_icon.swift -o /tmp/icon && /tmp/icon

import AppKit
import CoreText
let n = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
let N = CGFloat(n)
// Fond : dégradé radial indigo → nuit.
let bg = CGGradient(colorsSpace: cs, colors: [c(0.20, 0.17, 0.42), c(0.07, 0.06, 0.18), c(0.03, 0.03, 0.09)] as CFArray, locations: [0, 0.6, 1])!
ctx.drawRadialGradient(bg, startCenter: CGPoint(x: N * 0.5, y: N * 0.62), startRadius: 0,
                       endCenter: CGPoint(x: N * 0.5, y: N * 0.5), endRadius: N * 0.78, options: [.drawsAfterEndLocation])
// Vagues seigaiha (bas), très discrètes.
ctx.setLineWidth(3)
let r: CGFloat = 70
for row in 0..<5 {
    let y = CGFloat(row) * r * 0.5 - 10
    for col in -1..<9 {
        let x = CGFloat(col) * r * 2 + (row % 2 == 0 ? 0 : r)
        for k in stride(from: r, to: 10, by: -16) {
            ctx.setStrokeColor(c(0.75, 0.62, 0.35, 0.07 + 0.03 * Double(5 - row) / 5))
            ctx.addArc(center: CGPoint(x: x, y: y), radius: k, startAngle: 0, endAngle: .pi, clockwise: false)
            ctx.strokePath()
        }
    }
}
// Halo doré derrière le kanji.
let halo = CGGradient(colorsSpace: cs, colors: [c(1, 0.82, 0.45, 0.35), c(1, 0.82, 0.45, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(halo, startCenter: CGPoint(x: N / 2, y: N * 0.58), startRadius: 0,
                       endCenter: CGPoint(x: N / 2, y: N * 0.58), endRadius: N * 0.36, options: [])
// Livre ouvert : deux pages courbes, liseré doré.
func page(_ left: Bool) -> CGPath {
    let p = CGMutablePath(); let s: CGFloat = left ? -1 : 1; let cx = N / 2
    p.move(to: CGPoint(x: cx, y: 250))
    p.addCurve(to: CGPoint(x: cx + s * 330, y: 285), control1: CGPoint(x: cx + s * 120, y: 300), control2: CGPoint(x: cx + s * 230, y: 300))
    p.addLine(to: CGPoint(x: cx + s * 330, y: 225))
    p.addCurve(to: CGPoint(x: cx, y: 190), control1: CGPoint(x: cx + s * 230, y: 240), control2: CGPoint(x: cx + s * 120, y: 240))
    p.closeSubpath(); return p
}
for left in [true, false] {
    ctx.saveGState(); ctx.addPath(page(left)); ctx.clip()
    let pg = CGGradient(colorsSpace: cs, colors: [c(0.98, 0.95, 0.88), c(0.86, 0.80, 0.68)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(pg, start: CGPoint(x: N / 2, y: 300), end: CGPoint(x: N / 2, y: 190), options: [])
    ctx.restoreGState()
    ctx.addPath(page(left)); ctx.setStrokeColor(c(0.86, 0.68, 0.33)); ctx.setLineWidth(6); ctx.strokePath()
}
ctx.setStrokeColor(c(0.86, 0.68, 0.33)); ctx.setLineWidth(5)
ctx.move(to: CGPoint(x: N / 2, y: 190)); ctx.addLine(to: CGPoint(x: N / 2, y: 250)); ctx.strokePath()
// Kanji 教 : dégradé or, ombre douce.
let font = CTFontCreateWithName("HiraMinProN-W6" as CFString, 520, nil)
let glyphs = UnsafeMutablePointer<CGGlyph>.allocate(capacity: 1); var ch: UniChar = 0x6559
CTFontGetGlyphsForCharacters(font, &ch, glyphs, 1)
let path = CTFontCreatePathForGlyph(font, glyphs[0], nil)!
let box = path.boundingBoxOfPath
var t = CGAffineTransform(translationX: N / 2 - box.midX, y: N * 0.585 - box.midY)
let placed = path.copy(using: &t)!
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: c(0, 0, 0, 0.6))
ctx.addPath(placed); ctx.setFillColor(c(0.9, 0.72, 0.38)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState(); ctx.addPath(placed); ctx.clip()
let gold = CGGradient(colorsSpace: cs, colors: [c(1, 0.93, 0.70), c(0.96, 0.78, 0.40), c(0.74, 0.52, 0.22)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(gold, start: CGPoint(x: 0, y: placed.boundingBoxOfPath.maxY), end: CGPoint(x: 0, y: placed.boundingBoxOfPath.minY), options: [])
ctx.restoreGState()
// Sceau rouge (hanko) « 書 » en bas à droite.
let seal = CGRect(x: 720, y: 330, width: 150, height: 150)
ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: c(0, 0, 0, 0.5))
ctx.addPath(CGPath(roundedRect: seal, cornerWidth: 22, cornerHeight: 22, transform: nil)); ctx.setFillColor(c(0.80, 0.16, 0.14)); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: seal.insetBy(dx: 10, dy: 10), cornerWidth: 14, cornerHeight: 14, transform: nil))
ctx.setStrokeColor(c(1, 0.9, 0.85, 0.85)); ctx.setLineWidth(4); ctx.strokePath()
let sfont = CTFontCreateWithName("HiraMinProN-W6" as CFString, 104, nil); var sc: UniChar = 0x66F8
CTFontGetGlyphsForCharacters(sfont, &sc, glyphs, 1)
let sp = CTFontCreatePathForGlyph(sfont, glyphs[0], nil)!; let sb = sp.boundingBoxOfPath
var st = CGAffineTransform(translationX: seal.midX - sb.midX, y: seal.midY - sb.midY)
ctx.addPath(sp.copy(using: &st)!); ctx.setFillColor(c(1, 0.94, 0.90)); ctx.fillPath()
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "AppIcon-1024.png"))
