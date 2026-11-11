// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024-2026  Yomitan Authors
// Copyright (C) 2020-2022  Yomichan Authors
// Swift port: Copyright (C) 2026 NOxygen59
//
// Porté de yomidevs/yomitan, ext/js/language/ja/japanese.js
// (commit 876253ca12e38aa6b0be3617e84827db5d9782b3).
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import Foundation

/// Fonctions sur le texte japonais (kana, kanji, furigana, mores, accent).
public enum JapaneseText {
    static let hiraganaSmallTsu: UInt32 = 0x3063
    static let katakanaSmallTsu: UInt32 = 0x30C3
    static let katakanaSmallKa: UInt32 = 0x30F5
    static let katakanaSmallKe: UInt32 = 0x30F6
    static let prolongedSoundMark: UInt32 = 0x30FC

    static let hiraganaRange: ClosedRange<UInt32> = 0x3040...0x309F
    static let katakanaRange: ClosedRange<UInt32> = 0x30A0...0x30FF
    static let hiraganaConversionRange: ClosedRange<UInt32> = 0x3041...0x3096
    static let katakanaConversionRange: ClosedRange<UInt32> = 0x30A1...0x30F6

    static let cjkIdeographRanges: [ClosedRange<UInt32>] = [
        0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F,
        0x2B820...0x2CEAF, 0x2CEB0...0x2EBEF, 0x30000...0x3134F, 0x31350...0x323AF, 0x2EBF0...0x2EE5F,
        0x323B0...0x3347F, 0xF900...0xFAFF, 0x2F800...0x2FA1F,
    ]
    static let cjkCompatibility: ClosedRange<UInt32> = 0x3300...0x33FF

    static let japaneseRanges: [ClosedRange<UInt32>] = [
        hiraganaRange, katakanaRange,
        0x3000...0x303F,   // ponctuation CJK
        0xFF00...0xFFEF,   // formes pleine/demi-chasse
        0x30FB...0x30FC,   // ・ー
        0x3190...0x319F,   // kanbun
    ] + cjkIdeographRanges

    static let smallKana: Set<Character> = Set("ぁぃぅぇぉゃゅょゎァィゥェォャュョヮ")

    static let halfwidthKatakana: [Character: [Character]] = {
        let pairs: [(Character, String)] = [
            ("･", "・--"), ("ｦ", "ヲヺ-"), ("ｧ", "ァ--"), ("ｨ", "ィ--"), ("ｩ", "ゥ--"), ("ｪ", "ェ--"), ("ｫ", "ォ--"),
            ("ｬ", "ャ--"), ("ｭ", "ュ--"), ("ｮ", "ョ--"), ("ｯ", "ッ--"), ("ｰ", "ー--"), ("ｱ", "ア--"), ("ｲ", "イ--"),
            ("ｳ", "ウヴ-"), ("ｴ", "エ--"), ("ｵ", "オ--"), ("ｶ", "カガ-"), ("ｷ", "キギ-"), ("ｸ", "クグ-"), ("ｹ", "ケゲ-"),
            ("ｺ", "コゴ-"), ("ｻ", "サザ-"), ("ｼ", "シジ-"), ("ｽ", "スズ-"), ("ｾ", "セゼ-"), ("ｿ", "ソゾ-"), ("ﾀ", "タダ-"),
            ("ﾁ", "チヂ-"), ("ﾂ", "ツヅ-"), ("ﾃ", "テデ-"), ("ﾄ", "トド-"), ("ﾅ", "ナ--"), ("ﾆ", "ニ--"), ("ﾇ", "ヌ--"),
            ("ﾈ", "ネ--"), ("ﾉ", "ノ--"), ("ﾊ", "ハバパ"), ("ﾋ", "ヒビピ"), ("ﾌ", "フブプ"), ("ﾍ", "ヘベペ"), ("ﾎ", "ホボポ"),
            ("ﾏ", "マ--"), ("ﾐ", "ミ--"), ("ﾑ", "ム--"), ("ﾒ", "メ--"), ("ﾓ", "モ--"), ("ﾔ", "ヤ--"), ("ﾕ", "ユ--"),
            ("ﾖ", "ヨ--"), ("ﾗ", "ラ--"), ("ﾘ", "リ--"), ("ﾙ", "ル--"), ("ﾚ", "レ--"), ("ﾛ", "ロ--"), ("ﾜ", "ワ--"), ("ﾝ", "ン--"),
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, Array($0.1)) })
    }()

    static let kanaToVowel: [Character: Character?] = {
        let mapping: [(Character?, String)] = [
            ("a", "ぁあかがさざただなはばぱまゃやらゎわヵァアカガサザタダナハバパマャヤラヮワヵヷ"),
            ("i", "ぃいきぎしじちぢにひびぴみりゐィイキギシジチヂニヒビピミリヰヸ"),
            ("u", "ぅうくぐすずっつづぬふぶぷむゅゆるゥウクグスズッツヅヌフブプムュユルヴ"),
            ("e", "ぇえけげせぜてでねへべぺめれゑヶェエケゲセゼテデネヘベペメレヱヶヹ"),
            ("o", "ぉおこごそぞとどのほぼぽもょよろをォオコゴソゾトドノホボポモョヨロヲヺ"),
            (nil, "のノ"),
        ]
        var result: [Character: Character?] = [:]
        for (vowel, characters) in mapping { for c in characters { result[c] = vowel } }
        return result
    }()

    // MARK: Tests de caractères

    @inline(__always) static func code(_ c: Character) -> UInt32 { c.unicodeScalars.first?.value ?? 0 }

    public static func isKanji(_ c: Character) -> Bool {
        let v = code(c)
        return cjkIdeographRanges.contains { $0.contains(v) }
    }

    public static func isKana(_ c: Character) -> Bool {
        let v = code(c)
        return hiraganaRange.contains(v) || katakanaRange.contains(v)
    }

    public static func isJapanese(_ c: Character) -> Bool {
        let v = code(c)
        return japaneseRanges.contains { $0.contains(v) }
    }

    // MARK: Mores et accent

    public static func isMoraPitchHigh(_ moraIndex: Int, downstep: Int) -> Bool {
        switch downstep {
        case 0: return moraIndex > 0
        case 1: return moraIndex < 1
        default: return moraIndex > 0 && moraIndex < downstep
        }
    }

    public enum PitchCategory: String { case heiban, atamadaka, nakadaka, odaka, kifuku }

    public static func pitchCategory(_ text: String, downstep: Int, isVerbOrAdjective: Bool) -> PitchCategory? {
        if downstep == 0 { return .heiban }
        if isVerbOrAdjective { return downstep > 0 ? .kifuku : nil }
        if downstep == 1 { return .atamadaka }
        if downstep > 1 { return downstep >= moraCount(text) ? .odaka : .nakadaka }
        return nil
    }

    public static func morae(_ text: String) -> [String] {
        var result: [String] = []
        for c in text {
            if smallKana.contains(c), !result.isEmpty {
                result[result.count - 1].append(c)
            } else {
                result.append(String(c))
            }
        }
        return result
    }

    public static func moraCount(_ text: String) -> Int {
        var count = 0
        for c in text where !(smallKana.contains(c) && count > 0) { count += 1 }
        return count
    }

    // MARK: Conversions

    static func prolongedHiragana(after previous: Character) -> Character? {
        switch kanaToVowel[previous] ?? nil {
        case "a": return "あ"
        case "i": return "い"
        case "u": return "う"
        case "e": return "え"
        case "o": return "う"
        default: return nil
        }
    }

    public static func katakanaToHiragana(_ text: String, keepProlongedSoundMarks: Bool = false) -> String {
        let offset = hiraganaConversionRange.lowerBound &- katakanaConversionRange.lowerBound
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for var c in text {
            let v = code(c)
            switch v {
            case katakanaSmallKa, katakanaSmallKe:
                break
            case prolongedSoundMark:
                if !keepProlongedSoundMarks, let last = result.last, let p = prolongedHiragana(after: last) { c = p }
            default:
                if katakanaConversionRange.contains(v), let s = Unicode.Scalar(v &+ offset) { c = Character(s) }
            }
            result.append(c)
        }
        return result
    }

    public static func hiraganaToKatakana(_ text: String) -> String {
        let offset = katakanaConversionRange.lowerBound - hiraganaConversionRange.lowerBound
        var result = ""
        for var c in text {
            let v = code(c)
            if hiraganaConversionRange.contains(v), let s = Unicode.Scalar(v + offset) { c = Character(s) }
            result.append(c)
        }
        return result
    }

    public static func alphanumericToFullWidth(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { s -> Unicode.Scalar in
            var v = s.value
            if (0x30...0x39).contains(v) { v += 0xFF10 - 0x30 }
            else if (0x41...0x5A).contains(v) { v += 0xFF21 - 0x41 }
            else if (0x61...0x7A).contains(v) { v += 0xFF41 - 0x61 }
            return Unicode.Scalar(v) ?? s
        }))
    }

    public static func fullWidthAlphanumericToNormal(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { s -> Unicode.Scalar in
            var v = s.value
            if (0xFF10...0xFF19).contains(v) { v -= 0xFF10 - 0x30 }
            else if (0xFF21...0xFF3A).contains(v) { v -= 0xFF21 - 0x41 }
            else if (0xFF41...0xFF5A).contains(v) { v -= 0xFF41 - 0x61 }
            return Unicode.Scalar(v) ?? s
        }))
    }

    public static func halfWidthKanaToFullWidth(_ text: String) -> String {
        // Les marques ﾞ/ﾟ sont des caractères séparés : on travaille sur les scalaires.
        let scalars = Array(text.unicodeScalars)
        var result = ""
        var i = 0
        while i < scalars.count {
            let c = Character(scalars[i])
            guard let mapping = halfwidthKatakana[c] else {
                result.unicodeScalars.append(scalars[i])
                i += 1
                continue
            }
            var index = 0
            if i + 1 < scalars.count {
                switch scalars[i + 1].value {
                case 0xFF9E: index = 1
                case 0xFF9F: index = 2
                default: break
                }
            }
            var c2 = mapping[index]
            if index > 0 {
                if c2 == "-" { index = 0; c2 = mapping[0] } else { i += 1 }
            }
            result.append(c2)
            i += 1
        }
        return result
    }

    static func dakutenAllowed(_ v: UInt32) -> Bool {
        (0x304B...0x3068).contains(v) || (0x306F...0x307B).contains(v) || (0x30AB...0x30C8).contains(v) || (0x30CF...0x30DB).contains(v)
    }

    static func handakutenAllowed(_ v: UInt32) -> Bool {
        (0x306F...0x307B).contains(v) || (0x30CF...0x30DB).contains(v)
    }

    /// ト + ゛ (combinant) → ド.
    public static func normalizeCombiningCharacters(_ text: String) -> String {
        let s = Array(text.unicodeScalars)
        guard s.count > 1 else { return text }
        var out: [Unicode.Scalar] = []
        var i = s.count - 1
        while i > 0 {
            if s[i].value == 0x3099, dakutenAllowed(s[i - 1].value), let c = Unicode.Scalar(s[i - 1].value + 1) {
                out.append(c); i -= 2; continue
            }
            if s[i].value == 0x309A, handakutenAllowed(s[i - 1].value), let c = Unicode.Scalar(s[i - 1].value + 2) {
                out.append(c); i -= 2; continue
            }
            out.append(s[i]); i -= 1
        }
        if i == 0 { out.append(s[0]) }
        return String(String.UnicodeScalarView(out.reversed()))
    }

    /// ㌀ → アパート.
    public static func normalizeCJKCompatibilityCharacters(_ text: String) -> String {
        var result = ""
        for c in text {
            if cjkCompatibility.contains(code(c)) {
                result += String(c).decomposedStringWithCompatibilityMapping
            } else {
                result.append(c)
            }
        }
        return result
    }

    public static func isEmphatic(_ c: Character) -> Bool {
        let v = code(c)
        return v == hiraganaSmallTsu || v == katakanaSmallTsu || v == prolongedSoundMark
    }

    /// すっっごーーい → すっごーい (ou すごい si `full`).
    public static func collapseEmphaticSequences(_ text: String, full: Bool) -> String {
        let chars = Array(text)
        var left = 0
        while left < chars.count && isEmphatic(chars[left]) { left += 1 }
        var right = chars.count - 1
        while right >= 0 && isEmphatic(chars[right]) { right -= 1 }
        if left > right { return text }
        var middle = ""
        var current: Character?
        for i in left...right {
            let c = chars[i]
            if isEmphatic(c) {
                if current != c {
                    current = c
                    if !full { middle.append(c); continue }
                }
            } else {
                current = nil
                middle.append(c)
            }
        }
        return String(chars[..<left]) + middle + String(chars[(right + 1)...])
    }

    // MARK: Furigana

    public struct FuriganaSegment: Equatable, Sendable {
        public var text: String
        public var reading: String
        public init(_ text: String, _ reading: String) {
            self.text = text
            self.reading = reading
        }
    }

    struct FuriganaGroup {
        var isKana: Bool
        var text: [Character]
        var textNormalized: [Character]?
    }

    static func segmentize(_ reading: [Character], _ readingNormalized: [Character], _ groups: [FuriganaGroup], _ start: Int) -> [FuriganaSegment]? {
        let groupCount = groups.count - start
        if groupCount <= 0 { return reading.isEmpty ? [] : nil }
        let group = groups[start]
        let textLength = group.text.count
        if group.isKana {
            if let normalized = group.textNormalized, readingNormalized.starts(with: normalized),
               var segments = segmentize(Array(reading.dropFirst(textLength)), Array(readingNormalized.dropFirst(textLength)), groups, start + 1) {
                if reading.starts(with: group.text) {
                    segments.insert(FuriganaSegment(String(group.text), ""), at: 0)
                } else {
                    segments.insert(contentsOf: kanaSegments(group.text, reading), at: 0)
                }
                return segments
            }
            return nil
        }
        var result: [FuriganaSegment]?
        var i = reading.count
        while i >= textLength {
            if var segments = segmentize(Array(reading[i...]), Array(readingNormalized[min(i, readingNormalized.count)...]), groups, start + 1) {
                if result != nil { return nil } // ambigu
                segments.insert(FuriganaSegment(String(group.text), String(reading[..<i])), at: 0)
                result = segments
            }
            if groupCount == 1 { break }
            i -= 1
        }
        return result
    }

    static func kanaSegments(_ text: [Character], _ reading: [Character]) -> [FuriganaSegment] {
        var segments: [FuriganaSegment] = []
        var start = 0
        func same(_ i: Int) -> Bool { i < reading.count && reading[i] == text[i] }
        var state = same(0)
        for i in 1..<max(text.count, 1) {
            let newState = same(i)
            if state == newState { continue }
            segments.append(FuriganaSegment(String(text[start..<i]), state ? "" : String(reading[start..<min(i, reading.count)])))
            state = newState
            start = i
        }
        segments.append(FuriganaSegment(String(text[start...]), state ? "" : String(reading[min(start, reading.count)..<min(text.count, reading.count)])))
        return segments
    }

    /// Répartit la lecture sur les kanji : 食べ物 + たべもの → [食|た][べ][物|もの].
    public static func distributeFurigana(_ term: String, _ reading: String) -> [FuriganaSegment] {
        if reading == term || reading.isEmpty { return [FuriganaSegment(term, "")] }
        var groups: [FuriganaGroup] = []
        for c in term {
            let kana = isKana(c)
            if let last = groups.last, last.isKana == kana {
                groups[groups.count - 1].text.append(c)
            } else {
                groups.append(FuriganaGroup(isKana: kana, text: [c], textNormalized: nil))
            }
        }
        for i in groups.indices where groups[i].isKana {
            groups[i].textNormalized = Array(katakanaToHiragana(String(groups[i].text)))
        }
        let readingChars = Array(reading)
        let normalized = Array(katakanaToHiragana(reading))
        guard normalized.count == readingChars.count else { return [FuriganaSegment(term, reading)] }
        return segmentize(readingChars, normalized, groups, 0) ?? [FuriganaSegment(term, reading)]
    }

}
