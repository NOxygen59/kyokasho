// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Compare le texte OCR d'une page (lignes) à une seconde lecture de la même page (ex. OvisOCR2, en Markdown) :
/// alignement caractère par caractère (distance d'édition), puis, pour chaque ligne, le morceau de la seconde
/// lecture qui lui correspond. Une ligne différente devient une **proposition** (jamais appliquée seule).
public enum OCRReferenceDiff {
    public struct Suggestion: Identifiable, Equatable, Sendable {
        public var id: Int { line }
        public let line: Int
        public let current: String
        public let proposed: String
    }

    /// Markdown / HTML → texte nu sans espaces (titres, gras, tableaux, images, formules retirés).
    static let ignored = Set<Character>("#*_`>|-")

    public static func plain(_ markdown: String) -> [Character] {
        var t = markdown
        for pattern in ["<img[^>]*>", "<[^>]+>", "\\$[^$]*\\$", "!\\[[^\\]]*\\]\\([^)]*\\)"] {
            t = t.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return t.filter { !$0.isWhitespace && !ignored.contains($0) }
    }

    /// `minSimilarity` : part de caractères communs exigée entre la ligne et sa proposition (sinon l'ordre de
    /// lecture diffère à cet endroit et l'alignement n'a pas de sens).
    public static func suggestions(_ page: OCRPage, reference: String, minSimilarity: Double = 0.5) -> [Suggestion] {
        let ref = plain(reference)
        var ocr: [Character] = []
        var lineOf: [Int] = []
        for (l, line) in page.lines.enumerated() {
            // Même filtre des deux côtés : un « - » ou « | » de l'OCR ne compte pas comme une différence.
            for c in line.text where !c.isWhitespace && !ignored.contains(c) { ocr.append(c); lineOf.append(l) }
        }
        let n = ocr.count, m = ref.count
        guard n > 0, m > 0, n * m <= 16_000_000 else { return [] }
        // Distance d'édition, une rangée à la fois ; directions gardées pour remonter (0 diag, 1 haut, 2 gauche).
        var dir = [UInt8](repeating: 0, count: (n + 1) * (m + 1))
        var prev = [Int](0...m), cur = [Int](repeating: 0, count: m + 1)
        for j in 1...m { dir[j] = 2 }
        for i in 1...n {
            cur[0] = i
            dir[i * (m + 1)] = 1
            for j in 1...m {
                let diag = prev[j - 1] + (ocr[i - 1] == ref[j - 1] ? 0 : 1)
                let up = prev[j] + 1, left = cur[j - 1] + 1
                if diag <= up && diag <= left { cur[j] = diag; dir[i * (m + 1) + j] = 0 }
                else if up <= left { cur[j] = up; dir[i * (m + 1) + j] = 1 }
                else { cur[j] = left; dir[i * (m + 1) + j] = 2 }
            }
            swap(&prev, &cur)
        }
        // Remontée : chaque caractère de la seconde lecture est rattaché à la ligne OCR en face (ou la précédente).
        var refLine = [Int](repeating: -1, count: m)
        var i = n, j = m
        while i > 0 || j > 0 {
            switch dir[i * (m + 1) + j] {
            case 0 where i > 0 && j > 0:
                refLine[j - 1] = lineOf[i - 1]; i -= 1; j -= 1
            case 1 where i > 0:
                i -= 1
            default:
                // Texte en plus : gardé seulement s'il tombe **dans** une ligne (entre deux de ses caractères) ;
                // avant la première ligne, entre deux lignes ou après la dernière, il n'appartient à aucune.
                let inside = i > 0 && i < n && lineOf[i - 1] == lineOf[i]
                refLine[j - 1] = inside ? lineOf[i - 1] : -1; j -= 1
            }
        }
        var proposed: [Int: [Character]] = [:]
        for (k, l) in refLine.enumerated() where l >= 0 { proposed[l, default: []].append(ref[k]) }
        var out: [Suggestion] = []
        for (l, line) in page.lines.enumerated() {
            let current = line.text.filter { !$0.isWhitespace && !ignored.contains($0) }
            guard !current.isEmpty, line.edited != true, let new = proposed[l], String(new) != current else { continue }
            let common = commonCount(Array(current), new)
            guard Double(common) / Double(max(current.count, new.count)) >= minSimilarity else { continue }
            out.append(Suggestion(line: l, current: line.text, proposed: String(new)))
        }
        return out
    }

    /// Longueur de la plus longue sous-suite commune.
    static func commonCount(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var prev = [Int](repeating: 0, count: b.count + 1), cur = prev
        for x in a {
            for (k, y) in b.enumerated() { cur[k + 1] = x == y ? prev[k] + 1 : max(prev[k + 1], cur[k]) }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
