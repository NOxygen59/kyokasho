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
        align(page, reference: reference, minSimilarity: minSimilarity).compactMap { line, proposed in
            let current = page.lines[line].text.filter { !$0.isWhitespace && !ignored.contains($0) }
            guard proposed != current, page.lines[line].edited != true else { return nil }
            return Suggestion(line: line, current: page.lines[line].text, proposed: proposed)
        }
        .sorted { $0.line < $1.line }
    }

    /// Ce que la seconde lecture dit pour **chaque** ligne qu'elle recouvre de façon fiable (texte sans espaces),
    /// identique ou non. Ligne absente : la seconde lecture n'a rien de comparable à cet endroit.
    public static func align(_ page: OCRPage, reference: String, minSimilarity: Double = 0.5) -> [Int: String] {
        let ref = plain(reference)
        var ocr: [Character] = []
        var lineOf: [Int] = []
        for (l, line) in page.lines.enumerated() {
            // Même filtre des deux côtés : un « - » ou « | » de l'OCR ne compte pas comme une différence.
            for c in line.text where !c.isWhitespace && !ignored.contains(c) { ocr.append(c); lineOf.append(l) }
        }
        let n = ocr.count, m = ref.count
        guard n > 0, m > 0, n * m <= 16_000_000 else { return [:] }
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
        var out: [Int: String] = [:]
        for (l, line) in page.lines.enumerated() {
            let current = line.text.filter { !$0.isWhitespace && !ignored.contains($0) }
            guard !current.isEmpty, let new = proposed[l] else { continue }
            let common = commonCount(Array(current), new)
            guard Double(common) / Double(max(current.count, new.count)) >= minSimilarity else { continue }
            out[l] = String(new)
        }
        return out
    }

    /// Une ligne OCR réécrite avec le texte de la seconde lecture, chaque caractère posé sur la boîte du caractère
    /// OCR en face (identique ou remplacé) ; `nil` = caractère en plus, sans boîte propre.
    public struct AlignedLine: Equatable, Sendable {
        public let line: Int
        public let text: String
        public let boxes: [NormBox?]
    }

    /// Lignes que la seconde lecture recouvre de façon fiable (`align`), avec les boîtes de caractères de l'OCR.
    /// Sert aux furigana : texte juste (IA), positions mesurées (OCR). Ligne sans boîte par caractère : absente.
    public static func alignedLines(_ page: OCRPage, reference: String, minSimilarity: Double = 0.5) -> [AlignedLine] {
        align(page, reference: reference, minSimilarity: minSimilarity).sorted { $0.key < $1.key }.compactMap { l, text in
            let line = page.lines[l]
            guard line.charBoxes.count == line.text.count else { return nil }
            // Caractères OCR gardés par `align` (même filtre), avec leur boîte.
            let kept = zip(line.text, line.charBoxes).filter { !$0.0.isWhitespace && !ignored.contains($0.0) }
            let a = Array(text), b = kept.map(\.0)
            guard !a.isEmpty, !b.isEmpty else { return nil }
            return AlignedLine(line: l, text: text, boxes: match(a, b).map { $0.map { kept[$0].1 } })
        }
    }

    /// Caractères OCR qui ne correspondent pas à la seconde lecture (remplacés ou absents chez elle) ajoutés aux
    /// doutes de leur ligne (index dans `line.text`). Lignes corrigées à la main : jamais touchées. Rejouable :
    /// les doutes déjà là restent, rien n'est ajouté deux fois.
    public static func markDifferences(_ page: OCRPage, reference: String, minSimilarity: Double = 0.5) -> OCRPage {
        var page = page
        for (l, text) in align(page, reference: reference, minSimilarity: minSimilarity) where page.lines[l].edited != true {
            let chars = Array(page.lines[l].text)
            let kept = chars.indices.filter { !chars[$0].isWhitespace && !ignored.contains(chars[$0]) }
            let ai = Array(text)
            var doubt = Set(page.lines[l].doubt ?? [])
            for (k, j) in match(kept.map { chars[$0] }, ai).enumerated() where j.map({ ai[$0] != chars[kept[k]] }) ?? true {
                doubt.insert(kept[k])
            }
            page.lines[l].doubt = doubt.sorted()
        }
        return page
    }

    /// Pour chaque caractère de `a`, l'index du caractère de `b` en face (égal ou remplacé), `nil` si ajouté.
    static func match(_ a: [Character], _ b: [Character]) -> [Int?] {
        if a == b { return Array(b.indices) }
        let n = a.count, m = b.count
        var cost = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { cost[i][0] = i }
        for j in 0...m { cost[0][j] = j }
        for i in 1...n {
            for j in 1...m {
                cost[i][j] = min(cost[i - 1][j] + 1, cost[i][j - 1] + 1, cost[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
        }
        var out = [Int?](repeating: nil, count: n)
        var i = n, j = m
        while i > 0 && j > 0 {
            if cost[i][j] == cost[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1) {
                out[i - 1] = j - 1; i -= 1; j -= 1
            } else if cost[i][j] == cost[i - 1][j] + 1 {
                i -= 1
            } else {
                j -= 1
            }
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
