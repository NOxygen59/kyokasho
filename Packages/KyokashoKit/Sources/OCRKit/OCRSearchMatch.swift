// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

extension OCRPage {
    /// Boîtes des caractères de la première occurrence de `query` dans la page (une ligne à la fois), pour surligner
    /// brièvement le mot d'un résultat de recherche (idée de la recette 1.6.2, version 1.6.4). Mêmes tolérances que la
    /// recherche du lecteur : casse, accents et pleine / demi-chasse. Vide si le mot est absent, coupé entre deux
    /// lignes, ou si la ligne n'a pas une boîte par caractère.
    public func matchBoxes(of query: String) -> [NormBox] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        for line in lines {
            guard let range = line.text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
            else { continue }
            // Index en graphèmes : `charBoxes` a une boîte par graphème de `text`.
            let start = line.text.distance(from: line.text.startIndex, to: range.lowerBound)
            let count = line.text.distance(from: range.lowerBound, to: range.upperBound)
            guard count > 0, start + count <= line.charBoxes.count else { continue }
            return Array(line.charBoxes[start..<(start + count)])
        }
        return []
    }
}
