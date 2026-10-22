// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Relecture de l'OCR sans IA : (1) caractères hors de tout mot du dictionnaire = douteux ; (2) un caractère
/// douteux qui ressemble à un autre (未/末, 土/士, ロ/口…) est remplacé **seulement** si le remplacement forme un
/// mot connu et réduit les caractères douteux ; (3) lignes encore douteuses (ou peu sûres) signalées, pour
/// GLM-OCR ou une correction à la main.
public enum OCRProofreader {
    /// Un mot du découpage : longueur en caractères, et s'il est dans le dictionnaire.
    public typealias Segment = (length: Int, known: Bool)

    /// Caractères que l'OCR confond, dans les deux sens.
    static let pairs: [(Character, Character)] = [
        ("未", "末"), ("土", "士"), ("口", "ロ"), ("一", "ー"), ("力", "カ"), ("夕", "タ"), ("二", "ニ"), ("工", "エ"),
        ("八", "ハ"), ("卜", "ト"), ("へ", "ヘ"), ("べ", "ベ"), ("ぺ", "ペ"), ("り", "リ"), ("己", "已"), ("己", "巳"),
        ("人", "入"), ("刀", "力"), ("千", "干"), ("天", "夭"), ("大", "太"), ("犬", "太"), ("日", "曰"), ("目", "且"),
        ("貝", "見"), ("問", "間"), ("待", "持"), ("特", "持"), ("情", "清"), ("積", "績"), ("微", "徴"), ("候", "侯"),
        ("ソ", "ン"), ("シ", "ツ"), ("ク", "ケ"), ("ぱ", "ば"), ("ぴ", "び"), ("ぷ", "ぶ"), ("ぽ", "ぼ"), ("パ", "バ"),
        ("ピ", "ビ"), ("プ", "ブ"), ("ポ", "ボ"), ("っ", "つ"), ("ゃ", "や"), ("ゅ", "ゆ"), ("ょ", "よ"), ("ッ", "ツ"),
        ("ャ", "ヤ"), ("ュ", "ユ"), ("ョ", "ヨ"), ("〇", "○"), ("0", "〇"),
    ]
    static let confusions: [Character: [Character]] = {
        var map: [Character: [Character]] = [:]
        for (a, b) in pairs { map[a, default: []].append(b); map[b, default: []].append(a) }
        return map
    }()

    /// Ligne peu sûre selon le moteur, même sans caractère inconnu.
    public static let lowConfidence = 0.80

    /// Caractère japonais (kanji, kana) : seuls ceux-là peuvent être douteux (ni ponctuation ni chiffres).
    static func isJapanese(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { s in
            (0x3041...0x30FF).contains(s.value) || (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
                || s.value == 0x3005
        }
    }

    /// Index des caractères japonais hors de tout mot connu.
    public static func unknown(_ chars: [Character], _ segments: [Segment]) -> [Int] {
        guard segments.reduce(0, { $0 + $1.length }) == chars.count else { return [] }
        var out: [Int] = []
        var i = 0
        for s in segments {
            if !s.known { out += (i..<(i + s.length)).filter { isJapanese(chars[$0]) } }
            i += s.length
        }
        return out
    }

    /// Relit une ligne. `segment` : découpage du dictionnaire (plus long mot à chaque position).
    public static func proofread(_ line: OCRLine, segment: (String) async -> [Segment]) async -> OCRLine {
        guard line.edited != true else { return line }
        var line = line
        var chars = Array(line.text)
        guard chars.contains(where: isJapanese) else { line.doubt = []; return line }
        // Pas de découpage utilisable (dictionnaire pas encore chargé) : ligne laissée « non relue ».
        let first = await segment(line.text)
        guard first.reduce(0, { $0 + $1.length }) == chars.count else { return line }
        var doubt = unknown(chars, first)
        // Essais de remplacement, un caractère douteux à la fois (et ses voisins : l'erreur peut être à côté).
        var tried = Set<Int>()
        for p in doubt.flatMap({ [$0 - 1, $0, $0 + 1] }) where chars.indices.contains(p) && tried.insert(p).inserted {
            // Au plus 12 positions essayées par ligne (chaque essai redécoupe la ligne).
            if tried.count > 12 { break }
            guard let alternatives = confusions[chars[p]] else { continue }
            for alt in alternatives {
                var candidate = chars
                candidate[p] = alt
                let segments = await segment(String(candidate))
                guard segments.reduce(0, { $0 + $1.length }) == candidate.count else { continue }
                let left = unknown(candidate, segments)
                if left.count < doubt.count {
                    chars = candidate
                    doubt = left
                    break
                }
            }
            if doubt.isEmpty { break }
        }
        line.text = String(chars)
        line.doubt = doubt
        return line
    }

    public static func proofread(_ page: OCRPage, segment: (String) async -> [Segment]) async -> OCRPage {
        var page = page
        for i in page.lines.indices { page.lines[i] = await proofread(page.lines[i], segment: segment) }
        // Relue seulement si chaque ligne japonaise a pu l'être (sinon on réessaiera plus tard).
        page.proofread = page.lines.allSatisfy { $0.doubt != nil || $0.edited == true || !$0.text.contains(where: isJapanese) }
        return page
    }

    /// Lignes à relire par l'IA : caractères encore douteux, ou moteur peu sûr.
    public static func doubtful(_ page: OCRPage) -> [Int] {
        page.lines.indices.filter { i in
            let l = page.lines[i]
            guard l.edited != true, l.text.contains(where: isJapanese) else { return false }
            return !(l.doubt ?? []).isEmpty || l.confidence < lowConfidence
        }
    }
}
