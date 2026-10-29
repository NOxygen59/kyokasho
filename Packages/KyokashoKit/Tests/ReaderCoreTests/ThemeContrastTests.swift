// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import XCTest

/// Lot 3 des styles : les variantes claires (clair, sépia) gardent un contraste d'au moins 4,5:1 (WCAG AA, texte
/// normal) pour le texte sur chaque fond, les couleurs de fonction employées comme texte, et le texte posé sur une
/// couleur de fonction. Les valeurs sont lues dans `App/Design/Themes.swift`, pour ne jamais diverger du code.
final class ThemeContrastTests: XCTestCase {
    private struct RGB { var r, g, b: Double }

    private func luminance(_ c: RGB) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    private func ratio(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Encre à une opacité donnée posée sur un fond (composition en sRGB, comme SwiftUI).
    private func blend(_ ink: RGB, _ alpha: Double, over bg: RGB) -> RGB {
        RGB(r: ink.r * alpha + bg.r * (1 - alpha), g: ink.g * alpha + bg.g * (1 - alpha), b: ink.b * alpha + bg.b * (1 - alpha))
    }

    /// Blocs `static let <id> = Theme(…)` marqués `isLight: true`, champ → valeur.
    private func lightThemes() throws -> [String: [String: String]] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/Design/Themes.swift").standardizedFileURL
        let text = try String(contentsOf: file, encoding: .utf8)
        let block = try NSRegularExpression(pattern: #"static let (\w+) = Theme\(([\s\S]*?)\)\n"#)
        let field = try NSRegularExpression(pattern: #"(\w+): (?:Color\(hex: 0x([0-9A-Fa-f]{6})\)|([0-9.]+|true|false))"#)
        var out: [String: [String: String]] = [:]
        for m in block.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let name = String(text[Range(m.range(at: 1), in: text)!]), body = String(text[Range(m.range(at: 2), in: text)!])
            var values: [String: String] = [:]
            for f in field.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                let key = String(body[Range(f.range(at: 1), in: body)!])
                let value = [2, 3].compactMap { Range(f.range(at: $0), in: body).map { String(body[$0]) } }.first!
                values[key] = value
            }
            if values["isLight"] == "true" { out[name] = values }
        }
        return out
    }

    private func color(_ hex: String?) throws -> RGB {
        let v = try XCTUnwrap(hex.flatMap { UInt32($0, radix: 16) })
        return RGB(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    func testLightVariantsKeepAAContrast() throws {
        let themes = try lightThemes()
        XCTAssertEqual(Set(themes.keys), ["clair", "sepia"])
        for (name, t) in themes {
            let ink = try color(t["ink"]), onAccent = try color(t["onAccent"])
            let secondary = try XCTUnwrap(t["secondaryLevel"].flatMap(Double.init))
            let tertiary = try XCTUnwrap(t["tertiaryLevel"].flatMap(Double.init))
            for bgName in ["canvas", "surface", "surfaceHigh"] {
                let bg = try color(t[bgName])
                for (level, alpha) in [("principal", 0.96), ("légende", secondary), ("indication", tertiary)] {
                    let r = ratio(blend(ink, alpha, over: bg), bg)
                    XCTAssertGreaterThanOrEqual(r, 4.5, "\(name) : texte \(level) sur \(bgName) = \(r)")
                }
                for tint in ["read", "annotate", "japanese", "ai", "cloud"] {
                    let r = ratio(try color(t[tint]), bg)
                    XCTAssertGreaterThanOrEqual(r, 4.5, "\(name) : couleur \(tint) comme texte sur \(bgName) = \(r)")
                }
            }
            for tint in ["read", "annotate", "japanese", "ai", "cloud"] {
                let r = ratio(onAccent, try color(t[tint]))
                XCTAssertGreaterThanOrEqual(r, 4.5, "\(name) : texte sur la couleur \(tint) = \(r)")
            }
        }
    }
}
