// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Termes proposés pour le lexique du domaine (#50, lot D4, pistes A et C) : relevés par l'IA dans les pages déjà
/// lues, ou importés d'un glossaire en tableau. Toujours **proposés** : NOxygen59 choisit ceux qui entrent.
public struct LexiconCandidate: Equatable, Hashable, Sendable, Identifiable {
    public var id: String { term }
    public var term: String
    public var reading: String
    public var meaning: String
    /// Page où le terme a été vu (relevé par l'IA), `nil` pour un import.
    public var page: Int?

    public init(term: String, reading: String, meaning: String, page: Int? = nil) {
        self.term = term
        self.reading = reading
        self.meaning = meaning
        self.page = page
    }
}

public enum LexiconCandidates {
    /// Une ligne par terme : « terme | lecture | sens », séparateur `|`, `;`, tabulation ou `,` (le premier trouvé).
    /// Lignes vides, en-têtes (« terme », « term ») et puces Markdown ignorées ; le terme doit contenir du japonais.
    public static func parse(_ text: String, page: Int? = nil) -> [LexiconCandidate] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            var line = String(raw).trimmingCharacters(in: .whitespaces)
            while let first = line.first, "-*•·0123456789.)".contains(first) { line.removeFirst() }
            line = line.trimmingCharacters(in: .whitespaces)
            guard let separator = ["|", ";", "\t", ","].first(where: { line.contains($0) }) else { return nil }
            let parts = line.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let term = parts.first, isJapanese(term), !["terme", "term", "用語"].contains(term.lowercased()),
                  seen.insert(term).inserted else { return nil }
            let reading = parts.count > 2 ? parts[1] : (parts.count == 2 && isKana(parts[1]) ? parts[1] : "")
            let meaning = parts.count > 2 ? parts[2...].joined(separator: ", ") : (parts.count == 2 && !isKana(parts[1]) ? parts[1] : "")
            return LexiconCandidate(term: term, reading: isKana(reading) ? reading : "", meaning: meaning, page: page)
        }
    }

    /// Candidats absents du lexique (`known` : termes déjà présents), dans l'ordre, sans doublon.
    public static func new(_ candidates: [LexiconCandidate], known: Set<String>) -> [LexiconCandidate] {
        var seen = known
        return candidates.filter { seen.insert($0.term).inserted }
    }

    static func isJapanese(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }

    static func isKana(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { (0x3040...0x30FF).contains($0.value) || $0 == "・" || $0 == "ー" }
    }
}
