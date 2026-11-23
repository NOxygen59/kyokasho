// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

extension OCRPage {
    /// Boîtes des caractères de la première occurrence de `query`, **groupées par ligne**, pour surligner brièvement le
    /// mot d'un résultat de recherche (idée de la recette 1.6.2, version 1.6.4). Cherche dans le texte des lignes mis
    /// bout à bout, comme `OCRService.search` : un mot coupé entre deux lignes est trouvé (un groupe par ligne). Mêmes
    /// tolérances : casse, accents, pleine / demi-chasse. Vide si le mot est absent ou si une ligne touchée n'a pas une
    /// boîte par caractère.
    public func matchBoxes(of query: String) -> [[NormBox]] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let joined = lines.map(\.text).joined()
        guard let range = joined.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
        else { return [] }
        // Index en graphèmes : `charBoxes` a une boîte par graphème de `text`.
        let start = joined.distance(from: joined.startIndex, to: range.lowerBound)
        let end = start + joined.distance(from: range.lowerBound, to: range.upperBound)
        var groups: [[NormBox]] = []
        var offset = 0
        for line in lines {
            let count = line.text.count
            let low = max(start, offset), high = min(end, offset + count)
            if low < high {
                guard high - offset <= line.charBoxes.count else { return [] }
                groups.append(Array(line.charBoxes[(low - offset)..<(high - offset)]))
            }
            offset += count
            if offset >= end { break }
        }
        return groups
    }
}
