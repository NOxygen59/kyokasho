// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Lectures (furigana) des kanji d'un texte, avec l'analyseur japonais intégré au système
/// (`CFStringTokenizer`, hors ligne). Seuls les groupes de kanji reçoivent une lecture :
/// 食べ物 → 食[た] べ 物[もの], 読む → 読[よ] む.
public enum Furigana {
    public struct Ruby: Equatable, Sendable {
        /// Caractères (graphèmes) du texte couverts par la lecture.
        public var range: Range<Int>
        /// Même zone en UTF-16 (index de `NSString`, ceux de `PDFPage.characterBounds`).
        public var utf16: NSRange
        public var reading: String
    }

    /// Lectures fausses connues de l'analyseur (mot entier → lecture).
    static let corrections: [String: String] = ["日本": "にほん", "日本語": "にほんご", "日本人": "にほんじん"]

    public static func rubies(for text: String) -> [Ruby] {
        let ns = text as NSString
        guard ns.length > 0, text.contains(where: isKanji) else { return [] }
        // Index UTF-16 → index de graphème (les boîtes OCR sont par graphème).
        var graphemeAt = [Int](repeating: 0, count: ns.length + 1)
        var g = 0, u = 0
        for c in text {
            let n = c.utf16.count
            for k in 0..<n { graphemeAt[u + k] = g }
            u += n; g += 1
        }
        graphemeAt[ns.length] = g

        let tokenizer = CFStringTokenizerCreate(nil, text as CFString, CFRange(location: 0, length: ns.length),
                                                kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale)
        var result: [Ruby] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let surface = ns.substring(with: NSRange(location: r.location, length: r.length))
            guard surface.contains(where: isKanji) else { continue }
            let reading: String
            if let fixed = corrections[surface] {
                reading = fixed
            } else {
                guard let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String,
                      let kana = latin.applyingTransform(.latinToHiragana, reverse: false),
                      kana.allSatisfy(isKana) else { continue }
                reading = kana
            }
            for (sub, kana) in align(surface, reading) {
                let start = r.location + utf16Offset(surface, sub.lowerBound)
                let end = r.location + utf16Offset(surface, sub.upperBound)
                result.append(Ruby(range: graphemeAt[start]..<graphemeAt[end],
                                   utf16: NSRange(location: start, length: end - start), reading: kana))
            }
        }
        return result
    }

    /// Découpe la lecture d'un mot entre ses groupes de kanji (les kana du mot servent de repères).
    /// Renvoie des plages de graphèmes du mot. Si l'alignement échoue : une lecture pour tout le mot
    /// s'il n'a que des kanji, sinon rien (mieux vaut pas de furigana qu'un furigana à cheval sur les kana).
    static func align(_ surface: String, _ reading: String) -> [(Range<Int>, String)] {
        let chars = Array(surface)
        var groups: [(range: Range<Int>, kanji: Bool)] = []
        for (i, c) in chars.enumerated() {
            let k = isKanji(c)
            if let last = groups.last, last.kanji == k {
                groups[groups.count - 1].range = last.range.lowerBound..<(i + 1)
            } else {
                groups.append((i..<(i + 1), k))
            }
        }
        let pattern = "^" + groups.map { group -> String in
            if group.kanji { return "(.+?)" }
            let kana = String(chars[group.range]).applyingTransform(.hiraganaToKatakana, reverse: true) ?? ""
            return NSRegularExpression.escapedPattern(for: kana)
        }.joined() + "$"
        let whole = groups.count == 1 && groups[0].kanji ? [(0..<chars.count, reading)] : []
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: reading, range: NSRange(location: 0, length: (reading as NSString).length))
        else { return whole }
        var out: [(Range<Int>, String)] = []
        var capture = 1
        for group in groups where group.kanji {
            let range = match.range(at: capture)
            capture += 1
            guard range.location != NSNotFound else { return whole }
            out.append((group.range, (reading as NSString).substring(with: range)))
        }
        return out
    }

    private static func utf16Offset(_ s: String, _ grapheme: Int) -> Int {
        s.prefix(grapheme).utf16.count
    }

    public static func isKanji(_ c: Character) -> Bool {
        c.unicodeScalars.contains { s in
            (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
                || (0xF900...0xFAFF).contains(s.value) || (0x20000...0x2FA1F).contains(s.value)
                || s.value == 0x3005 || s.value == 0x3006 || s.value == 0x30F6  // 々 〆 ヶ
        }
    }

    static func isKana(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) || $0.value == 0x30FC }
    }
}
