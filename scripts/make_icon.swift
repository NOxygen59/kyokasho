// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59
// Dessine une des quatre icônes originales de Kyōkasho :
//   swift scripts/make_icon.swift ivory|navy|jade|charcoal <sortie.png>
// Le PNG reste opaque : l'effet de verre est dessiné dans l'image, comme l'exige une icône iOS.
import AppKit

enum IconVariant: String {
    case ivory, navy, jade, charcoal
}

guard CommandLine.arguments.count == 3,
      let variant = IconVariant(rawValue: CommandLine.arguments[1]) else {
    fputs("usage: swift scripts/make_icon.swift ivory|navy|jade|charcoal <sortie.png>\n", stderr)
    exit(2)
}

let output = CommandLine.arguments[2]
let size: CGFloat = output.contains("256") ? 256 : 1024
let unit = size / 1024

func color(_ red: Int, _ green: Int, _ blue: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255, alpha: alpha)
}

struct Palette {
    let top: NSColor
    let bottom: NSColor
    let ink: NSColor
    let edge: NSColor
}

let palette: Palette = {
    switch variant {
    case .ivory:
        return Palette(top: color(250, 247, 238), bottom: color(229, 222, 207),
                       ink: color(29, 29, 28), edge: color(255, 255, 255, 0.72))
    case .navy:
        return Palette(top: color(34, 66, 94), bottom: color(8, 28, 47),
                       ink: color(250, 242, 218), edge: color(221, 178, 101, 0.92))
    case .jade:
        return Palette(top: color(69, 112, 102), bottom: color(21, 65, 58),
                       ink: color(250, 242, 218), edge: color(198, 231, 219, 0.48))
    case .charcoal:
        return Palette(top: color(57, 65, 75), bottom: color(22, 25, 29),
                       ink: color(187, 215, 247), edge: color(211, 225, 242, 0.44))
    }
}()

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

// Fond opaque, doucement nuancé. iOS applique lui-même le masque aux coins de l'icône.
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [palette.top.cgColor, palette.bottom.cgColor] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 90 * unit, y: 970 * unit),
                           end: CGPoint(x: 920 * unit, y: 40 * unit),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// Une seule plaque de verre intérieure, très discrète.
let glass = NSBezierPath(roundedRect: NSRect(x: 40 * unit, y: 40 * unit,
                                            width: 944 * unit, height: 944 * unit),
                        xRadius: 168 * unit, yRadius: 168 * unit)
color(255, 255, 255, variant == .ivory ? 0.16 : 0.075).setFill()
glass.fill()
palette.edge.setStroke()
glass.lineWidth = (variant == .navy ? 8 : 5) * unit
glass.stroke()

// Reflet supérieur : un trait, jamais un halo spectaculaire.
let highlight = NSBezierPath()
highlight.move(to: NSPoint(x: 122 * unit, y: 858 * unit))
highlight.curve(to: NSPoint(x: 876 * unit, y: 902 * unit),
                controlPoint1: NSPoint(x: 330 * unit, y: 964 * unit),
                controlPoint2: NSPoint(x: 690 * unit, y: 960 * unit))
color(255, 255, 255, variant == .ivory ? 0.40 : 0.27).setStroke()
highlight.lineWidth = 10 * unit
highlight.lineCapStyle = .round
highlight.stroke()

switch variant {
case .ivory:
    // Le petit carré vermillon rappelle un sceau sans ajouter un second caractère.
    color(194, 62, 43, 0.92).setFill()
    NSBezierPath(roundedRect: NSRect(x: 805 * unit, y: 126 * unit,
                                    width: 105 * unit, height: 105 * unit),
                 xRadius: 17 * unit, yRadius: 17 * unit).fill()
case .navy:
    break
case .jade:
    // Une page abstraite, derrière le signe et assez large pour survivre à petite taille.
    let page = NSBezierPath()
    page.move(to: NSPoint(x: 130 * unit, y: 310 * unit))
    page.curve(to: NSPoint(x: 512 * unit, y: 270 * unit),
               controlPoint1: NSPoint(x: 270 * unit, y: 344 * unit),
               controlPoint2: NSPoint(x: 420 * unit, y: 330 * unit))
    page.curve(to: NSPoint(x: 894 * unit, y: 310 * unit),
               controlPoint1: NSPoint(x: 604 * unit, y: 330 * unit),
               controlPoint2: NSPoint(x: 754 * unit, y: 344 * unit))
    page.line(to: NSPoint(x: 850 * unit, y: 470 * unit))
    page.curve(to: NSPoint(x: 512 * unit, y: 430 * unit),
               controlPoint1: NSPoint(x: 720 * unit, y: 445 * unit),
               controlPoint2: NSPoint(x: 610 * unit, y: 430 * unit))
    page.curve(to: NSPoint(x: 174 * unit, y: 470 * unit),
               controlPoint1: NSPoint(x: 414 * unit, y: 430 * unit),
               controlPoint2: NSPoint(x: 304 * unit, y: 445 * unit))
    page.close()
    color(220, 238, 228, 0.16).setFill()
    page.fill()
case .charcoal:
    color(125, 161, 205, 0.20).setFill()
    NSBezierPath(ovalIn: NSRect(x: 515 * unit, y: 460 * unit,
                                width: 360 * unit, height: 360 * unit)).fill()
}

// Le glyphe est produit par la police japonaise du système, donc toujours exactement 「教」.
let font = NSFont(name: "HiraginoSans-W6", size: 590 * unit)
    ?? NSFont.systemFont(ofSize: 590 * unit, weight: .semibold)
let shadow = NSShadow()
shadow.shadowColor = color(0, 0, 0, variant == .ivory ? 0.08 : 0.20)
shadow.shadowBlurRadius = 12 * unit
shadow.shadowOffset = NSSize(width: 0, height: -5 * unit)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: palette.ink,
    .shadow: shadow,
]
let mark = NSAttributedString(string: "教", attributes: attributes)
let markSize = mark.size()
mark.draw(at: NSPoint(x: (size - markSize.width) / 2,
                      y: (size - markSize.height) / 2 - 8 * unit))

image.unlockFocus()
var proposed = NSRect(x: 0, y: 0, width: size, height: size)
guard let source = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
      let rgbContext = CGContext(data: nil, width: Int(size), height: Int(size),
                                 bitsPerComponent: 8, bytesPerRow: Int(size) * 4,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
rgbContext.interpolationQuality = .high
rgbContext.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
guard let flattened = rgbContext.makeImage() else { exit(1) }
let representation = NSBitmapImageRep(cgImage: flattened)
guard let png = representation.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: output))
