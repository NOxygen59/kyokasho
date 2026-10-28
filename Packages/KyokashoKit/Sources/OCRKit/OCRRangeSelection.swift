// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation

/// Surligner en glissant sur les zones de l'OCR (RET-020, #23) : du caractère sous le pointeur à l'appui jusqu'au
/// dernier caractère survolé au relâchement, dans l'ordre des lignes de la page (sens du glisser indifférent).
public enum OCRRangeSelection {
    /// Morceau d'une ligne : indices de caractères `range` (bornes comprises au début, exclues à la fin).
    public struct Segment: Equatable, Sendable {
        public let line: Int
        public let range: Range<Int>
    }

    public static func segments(in page: OCRPage, from a: (line: Int, index: Int), to b: (line: Int, index: Int)) -> [Segment] {
        let (start, end) = (a.line, a.index) <= (b.line, b.index) ? (a, b) : (b, a)
        guard page.lines.indices.contains(start.line), page.lines.indices.contains(end.line) else { return [] }
        var result: [Segment] = []
        for l in start.line...end.line {
            let count = page.lines[l].text.count
            guard count > 0 else { continue }
            let lower = l == start.line ? min(start.index, count - 1) : 0
            let upper = l == end.line ? min(end.index, count - 1) + 1 : count
            if lower < upper { result.append(Segment(line: l, range: lower..<upper)) }
        }
        return result
    }

    /// Texte sélectionné, une ligne OCR par ligne.
    public static func text(in page: OCRPage, _ segments: [Segment]) -> String {
        segments.map { s in String(Array(page.lines[s.line].text)[s.range]) }.joined(separator: "\n")
    }

    /// Un rectangle (repère normalisé de l'OCR) par morceau : l'union des cases de ses caractères, sinon la case de
    /// la ligne entière si l'OCR n'a pas de cases par caractère.
    public static func boxes(in page: OCRPage, _ segments: [Segment]) -> [NormBox] {
        segments.compactMap { s in
            let line = page.lines[s.line]
            let chars = s.range.filter(line.charBoxes.indices.contains).map { line.charBoxes[$0].rect }
            guard let first = chars.first else { return line.box }
            let r = chars.dropFirst().reduce(first) { $0.union($1) }
            return NormBox(x: r.minX, y: r.minY, w: r.width, h: r.height)
        }
    }
}
