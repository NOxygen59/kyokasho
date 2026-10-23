// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import YomitanKit

/// Champs d'une carte de révision fabriqués depuis un résultat du dictionnaire.
/// Noms = ceux du modèle « Japonais — mot » de ReviewKit (DictionaryKit n'en dépend pas).
public enum CardFields {
    /// Nombre de sens gardés dans le champ `Sens`.
    public static let maxSenses = 6

    public static func make(term: TermResult, sentence: String? = nil, source: String? = nil) -> [String: String] {
        var f: [String: String] = [
            "Mot": term.expression,
            "Lecture": term.reading,
            "Furigana": furigana(term.expression, term.reading),
        ]
        var senses: [String] = []
        for definition in term.definitions where senses.count < maxSenses {
            for item in GlossaryText.items(definition.glossaryJSON) where senses.count < maxSenses {
                if !senses.contains(item) { senses.append(item) }
            }
        }
        if !senses.isEmpty {
            f["Sens"] = "<ol>" + senses.map { "<li>\(escape($0))</li>" }.joined() + "</ol>"
        }
        var downsteps: [Int] = []
        for p in term.pitches { if let d = p.downstep, !downsteps.contains(d) { downsteps.append(d) } }
        if !downsteps.isEmpty { f["Accent"] = downsteps.map { "[\($0)]" }.joined(separator: " ") }
        if let freq = term.frequencies.first {
            f["Fréquence"] = escape(freq.display) + " · " + escape(freq.dictionaryTitle)
        }
        if let sentence, !sentence.isEmpty { f["Phrase"] = bold(term.matchedText, in: sentence) }
        if let source, !source.isEmpty { f["Source"] = escape(source) }
        return f
    }

    /// Carte du lexique : les champs suivent le même format que ceux du dictionnaire.
    public static func lexicon(expression: String, reading: String, meaning: String,
                               sentence: String, source: String) -> [String: String] {
        ["Mot": expression, "Lecture": reading, "Furigana": furigana(expression, reading),
         "Sens": "<ol><li>" + escape(meaning) + "</li></ol>",
         "Phrase": bold(expression, in: sentence), "Source": escape(source)]
    }

    /// Format furigana d'Anki : `食[た]べる`, une espace avant chaque segment qui a une lecture.
    public static func furigana(_ expression: String, _ reading: String) -> String {
        var out = ""
        for seg in JapaneseText.distributeFurigana(expression, reading) {
            if seg.reading.isEmpty { out += seg.text; continue }
            if !out.isEmpty { out += " " }
            out += "\(seg.text)[\(seg.reading)]"
        }
        return out
    }

    /// Phrase échappée, le mot trouvé en gras (première occurrence).
    static func bold(_ word: String, in sentence: String) -> String {
        guard !word.isEmpty, let r = sentence.range(of: word) else { return escape(sentence) }
        return escape(String(sentence[..<r.lowerBound])) + "<b>" + escape(word) + "</b>"
            + escape(String(sentence[r.upperBound...]))
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
