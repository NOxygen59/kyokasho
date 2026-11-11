// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit
import ReaderCore
import SwiftUI

/// Recherche dans le texte de la page (panneau d'étude) : kanji, kana ou romaji.
/// Le romaji devient des hiragana, les katakana comptent comme des hiragana, et chaque ligne est aussi
/// comparée à sa lecture (kanji remplacés par leurs furigana) : « tenjou » trouve 天井.
enum PageTextSearch {
    struct Match: Identifiable {
        let id: Int
        let text: String
        /// Zones trouvées dans le texte écrit (vide si seule la lecture correspond).
        let ranges: [Range<Int>]
        let byReading: Bool
    }

    /// Katakana → hiragana, minuscules : même longueur que le texte d'origine (caractère par caractère).
    static func fold(_ s: String) -> String { String(foldChars(s)) }

    /// Même chose, caractère par caractère, sans recoller (les index restent ceux de `Array(s)`).
    static func foldChars(_ s: String) -> [Character] {
        s.map { c -> Character in
            let folded = String(c).lowercased().applyingTransform(.hiraganaToKatakana, reverse: true) ?? String(c)
            return folded.count == 1 ? Character(folded) : c
        }
    }

    /// Formes de la requête à chercher : telle quelle, et en hiragana si elle contient du romaji.
    static func needles(_ query: String) -> [String] {
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return [] }
        var list = [q]
        if q.contains(where: { $0.isASCII && $0.isLetter }),
           let kana = q.applyingTransform(.latinToHiragana, reverse: false), kana != q,
           !kana.contains(where: { $0.isASCII && $0.isLetter }) {
            list.append(kana)
        }
        return list
    }

    /// Lecture de la ligne : chaque groupe de kanji remplacé par sa lecture.
    static func reading(_ text: String) -> String {
        var chars = Array(text)
        for ruby in Furigana.rubies(for: text).sorted(by: { $0.range.lowerBound > $1.range.lowerBound })
            where ruby.range.upperBound <= chars.count {
            chars.replaceSubrange(ruby.range, with: Array(ruby.reading))
        }
        return String(chars)
    }

    static func ranges(of needle: [Character], in hay: [Character]) -> [Range<Int>] {
        guard !needle.isEmpty, needle.count <= hay.count else { return [] }
        var found: [Range<Int>] = []
        var i = 0
        while i + needle.count <= hay.count {
            if Array(hay[i..<(i + needle.count)]) == needle { found.append(i..<(i + needle.count)); i += needle.count } else { i += 1 }
        }
        return found
    }

    static func search(_ query: String, in page: OCRPage) -> [Match] {
        let forms = needles(query).map(Array.init)
        guard !forms.isEmpty else { return [] }
        return page.lines.enumerated().compactMap { index, line in
            let folded = foldChars(line.text)
            let ranges = forms.flatMap { ranges(of: $0, in: folded) }.sorted { $0.lowerBound < $1.lowerBound }
            if !ranges.isEmpty { return Match(id: index, text: line.text, ranges: ranges, byReading: false) }
            let read = Array(fold(reading(line.text)))
            guard forms.contains(where: { !Self.ranges(of: $0, in: read).isEmpty }) else { return nil }
            return Match(id: index, text: line.text, ranges: [], byReading: true)
        }
    }

    /// Texte de la ligne avec les zones trouvées surlignées.
    static func highlighted(_ match: Match, tint: Color) -> AttributedString {
        var out = AttributedString()
        let chars = Array(match.text)
        var cursor = 0
        for r in match.ranges where r.lowerBound >= cursor && r.upperBound <= chars.count {
            out += AttributedString(String(chars[cursor..<r.lowerBound]))
            var hit = AttributedString(String(chars[r]))
            hit.backgroundColor = tint.opacity(0.35)
            hit.foregroundColor = Atelier.contrastInk
            out += hit
            cursor = r.upperBound
        }
        out += AttributedString(String(chars[cursor...]))
        return out
    }
}

/// Champ de recherche + lignes trouvées (en haut de l'onglet Texte).
struct PageSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Atelier.textTertiary)
            TextField("Chercher dans la page (漢字, かな, romaji)", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Atelier.textPrimary)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(Atelier.textTertiary)
                    .accessibilityLabel("Effacer la recherche")
            }
        }
        .font(Atelier.font(14))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Atelier.surfaceHigh, in: Capsule())
    }
}

struct PageSearchResults: View {
    let matches: [PageTextSearch.Match]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(matches.isEmpty ? String(localized: "Rien trouvé dans cette page.") : String(localized: "\(matches.count) ligne\(matches.count > 1 ? "s" : "")"))
                .font(.caption).foregroundStyle(Atelier.textTertiary)
            ForEach(matches) { match in
                VStack(alignment: .leading, spacing: 2) {
                    Text(PageTextSearch.highlighted(match, tint: Atelier.Tint.japanese))
                        .font(Atelier.jp)
                        .foregroundStyle(Atelier.textPrimary)
                        .textSelection(.enabled)
                    if match.byReading {
                        Text("trouvé par la lecture").font(.caption2).foregroundStyle(Atelier.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Atelier.surfaceHigh.opacity(0.5), in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
            }
        }
    }
}
