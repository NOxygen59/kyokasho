// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59
// Dessine l'icône de l'app (formes vectorielles originales) : swift scripts/make_icon.swift <sortie.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
// Fond : dégradé nuit
let colors = [NSColor(srgbRed: 0.11, green: 0.12, blue: 0.16, alpha: 1).cgColor,
              NSColor(srgbRed: 0.05, green: 0.05, blue: 0.08, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
// Livre ouvert : deux pages incurvées
func page(_ left: Bool) -> NSBezierPath {
    let p = NSBezierPath()
    let spine = size / 2, top: CGFloat = 760, bottom: CGFloat = 300, outer: CGFloat = left ? 170 : size - 170
    p.move(to: NSPoint(x: spine, y: bottom))
    p.curve(to: NSPoint(x: outer, y: bottom + 40), controlPoint1: NSPoint(x: spine - (left ? 120 : -120), y: bottom - 40),
            controlPoint2: NSPoint(x: outer + (left ? 60 : -60), y: bottom + 10))
    p.line(to: NSPoint(x: outer, y: top))
    p.curve(to: NSPoint(x: spine, y: top - 30), controlPoint1: NSPoint(x: outer + (left ? 80 : -80), y: top + 30),
            controlPoint2: NSPoint(x: spine - (left ? 110 : -110), y: top + 20))
    p.close()
    return p
}
NSColor(srgbRed: 0.96, green: 0.94, blue: 0.89, alpha: 1).setFill()
page(true).fill(); page(false).fill()
// Lignes de texte verticales (écriture japonaise) sur la page droite, horizontales à gauche
NSColor(srgbRed: 0.35, green: 0.36, blue: 0.42, alpha: 1).setFill()
for i in 0..<4 { NSBezierPath(roundedRect: NSRect(x: 600 + CGFloat(i) * 62, y: 380, width: 22, height: 300 - CGFloat(i % 2) * 70), xRadius: 11, yRadius: 11).fill() }
for i in 0..<4 { NSBezierPath(roundedRect: NSRect(x: 230, y: 640 - CGFloat(i) * 70, width: 210 - CGFloat(i % 2) * 60, height: 22), xRadius: 11, yRadius: 11).fill() }
// Surlignage + marque-page rouge
NSColor(srgbRed: 1.0, green: 0.84, blue: 0.25, alpha: 0.75).setFill()
NSBezierPath(roundedRect: NSRect(x: 220, y: 485, width: 230, height: 40), xRadius: 8, yRadius: 8).fill()
NSColor(srgbRed: 0.94, green: 0.40, blue: 0.37, alpha: 1).setFill()
let ribbon = NSBezierPath()
ribbon.move(to: NSPoint(x: 700, y: 790)); ribbon.line(to: NSPoint(x: 700, y: 560)); ribbon.line(to: NSPoint(x: 735, y: 600))
ribbon.line(to: NSPoint(x: 770, y: 560)); ribbon.line(to: NSPoint(x: 770, y: 800)); ribbon.close(); ribbon.fill()
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
