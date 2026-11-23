// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

extension TermResult {
    /// Niveau JLPT (« N3 ») si un dictionnaire l'indique dans ses étiquettes (« jlpt-n3 », « N3 », « JLPT N3 ») ;
    /// `nil` sinon — rien n'est deviné. Le plus facile l'emporte s'il y en a plusieurs (N5 avant N1).
    public var jlptLevel: String? {
        Self.jlptLevel(tagNames: definitions.flatMap { ($0.tags + $0.termTags).map(\.name) })
    }

    /// Calcul seul, sur les noms d'étiquettes (testable sans dictionnaire).
    public static func jlptLevel(tagNames names: [String]) -> String? {
        let levels = names.compactMap { name -> Int? in
            let lowered = name.lowercased().replacingOccurrences(of: " ", with: "")
            let core = lowered.hasPrefix("jlpt") ? String(lowered.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "-_:")) : lowered
            guard core.count == 2, core.first == "n", let digit = Int(String(core.last!)), (1...5).contains(digit) else { return nil }
            return digit
        }
        return levels.max().map { "N\($0)" }
    }
}
