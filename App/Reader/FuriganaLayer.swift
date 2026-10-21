// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreText
import Foundation
import OCRKit
import PDFKit
import ReaderCore

/// Furigana dessinés sur la page (option) : au-dessus des kanji en horizontal, à droite en vertical.
/// Positions : texte intégré du PDF (`characterBounds`) ou boîtes de caractères de l'OCR (scans).
/// Lectures : `Furigana` (analyseur japonais du système, hors ligne) — parfois fausses sur les noms propres.
enum FuriganaLayer {
    static let storageKey = "reader.furigana"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: storageKey) }

    /// Une lecture, dans le repère absolu de la page (celui de `cropBox`).
    struct Mark: Sendable {
        var rect: CGRect
        var reading: String
        var vertical: Bool
    }

    // MARK: Cache (lu par PDFKit depuis ses fils de dessin)

    private static let lock = NSLock()
    private static var marks: [String: [Mark]] = [:]
    private static var order: [String] = []
    private static let limit = 40

    static func marks(for key: String) -> [Mark]? {
        guard enabled else { return nil }
        return lock.withLock { marks[key] }
    }

    static func has(_ key: String) -> Bool { lock.withLock { marks[key] != nil } }

    static func set(_ list: [Mark], for key: String) {
        lock.withLock {
            marks[key] = list
            order.removeAll { $0 == key }
            order.append(key)
            while order.count > limit { marks[order.removeFirst()] = nil }
        }
    }

    static func clearMemory() { lock.withLock { marks = [:]; order = [] } }

    // MARK: Calcul

    /// Scan : boîtes OCR normalisées (haut-gauche, cadre d'origine `box`) → repère de la page.
    static func marks(from ocr: OCRPage, box: CGRect) -> [Mark] {
        ocr.lines.flatMap { line -> [Mark] in
            // Une boîte par caractère, sinon les lectures tomberaient sur les mauvais caractères.
            guard line.charBoxes.count == line.text.count else { return [] }
            return Furigana.rubies(for: line.text).compactMap { ruby in
                let rect = line.charBoxes[ruby.range].reduce(CGRect.null) { union, n in
                    union.union(CGRect(x: box.minX + n.x * box.width, y: box.maxY - (n.y + n.h) * box.height,
                                       width: n.w * box.width, height: n.h * box.height))
                }
                guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }
                return Mark(rect: rect, reading: ruby.reading, vertical: line.vertical)
            }
        }
    }

    /// PDF numérique : texte intégré, ligne par ligne, positions de chaque caractère.
    static func marks(from page: PDFPage) -> [Mark] {
        guard let text = page.string, !text.isEmpty else { return [] }
        let ns = text as NSString
        var out: [Mark] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let rubies = Furigana.rubies(for: ns.substring(with: lineRange))
            guard !rubies.isEmpty else { return }
            // Sens de la ligne : deux premiers caractères visibles l'un sous l'autre → vertical.
            // (`selection(for:)` suit les index de `page.string` ; `characterBounds` compte autrement les fins de ligne.)
            func bounds(_ range: NSRange) -> CGRect { page.selection(for: range)?.bounds(for: page) ?? .null }
            let visible = (lineRange.location..<NSMaxRange(lineRange)).lazy
                .map { bounds(NSRange(location: $0, length: 1)) }.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }.prefix(2)
            let pair = Array(visible)
            let vertical = pair.count == 2 && abs(pair[1].midY - pair[0].midY) > abs(pair[1].midX - pair[0].midX)
            for ruby in rubies {
                let rect = bounds(NSRange(location: lineRange.location + ruby.utf16.location, length: ruby.utf16.length))
                if !rect.isNull, rect.width > 0, rect.height > 0 { out.append(Mark(rect: rect, reading: ruby.reading, vertical: vertical)) }
            }
        }
        return out
    }

    // MARK: Dessin

    /// Dans le repère de la page (y vers le haut), déjà transformé par l'appelant.
    static func draw(_ marks: [Mark], in context: CGContext) {
        context.saveGState()
        context.textMatrix = .identity
        context.setFillColor(gray: 0.1, alpha: 0.95)
        for mark in marks {
            let kana = Array(mark.reading)
            guard !kana.isEmpty else { continue }
            let count = CGFloat(kana.count)
            // Taille : ≈ 45 % du caractère, réduite si la lecture déborde trop du mot.
            let base = mark.vertical ? mark.rect.width : mark.rect.height
            let span = mark.vertical ? mark.rect.height : mark.rect.width
            var size = base * 0.45
            if size * count > span * 1.6 { size = max(base * 0.28, span * 1.6 / count) }
            let font = CTFontCreateWithName("HiraginoSans-W4" as CFString, size, nil)
            let total = size * count
            for (i, c) in kana.enumerated() {
                let attributes: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
                ]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(c), attributes: attributes))
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                if mark.vertical {
                    let x = mark.rect.maxX + size * 0.15 + (size - width) / 2
                    let y = mark.rect.midY + total / 2 - CGFloat(i + 1) * size + size * 0.12
                    context.textPosition = CGPoint(x: x, y: y)
                } else {
                    let x = mark.rect.midX - total / 2 + CGFloat(i) * size + (size - width) / 2
                    context.textPosition = CGPoint(x: x, y: mark.rect.maxY + size * 0.2)
                }
                CTLineDraw(line, context)
            }
        }
        context.restoreGState()
    }
}
