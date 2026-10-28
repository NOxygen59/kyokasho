// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Surlignages sans couches empilées (recette 1.3.2 (62), L5) : un nouveau surlignage absorbe ceux de la même page
/// qu'il recouvre, et les rectangles qui se chevauchent sont fusionnés (sinon leur transparence s'additionne).
public enum HighlightLayers {
    /// Deux rectangles se recouvrent vraiment : intersection d'au moins 30 % du plus petit (deux lignes voisines
    /// qui se touchent à peine ne fusionnent pas).
    public static func overlaps(_ a: PageRect, _ b: PageRect) -> Bool {
        let w = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
        let h = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
        guard w > 0, h > 0 else { return false }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 && w * h >= smaller * 0.3
    }

    /// Fusionne les rectangles qui se recouvrent, jusqu'à ce qu'il n'en reste plus deux à fusionner.
    public static func merged(_ rects: [PageRect]) -> [PageRect] {
        var result = rects
        var changed = true
        while changed {
            changed = false
            outer: for i in result.indices {
                for j in result.indices where j > i && overlaps(result[i], result[j]) {
                    let a = result[i], b = result[j]
                    let minX = min(a.x, b.x), minY = min(a.y, b.y)
                    result[i] = PageRect(x: minX, y: minY,
                                         width: max(a.x + a.width, b.x + b.width) - minX,
                                         height: max(a.y + a.height, b.y + b.height) - minY)
                    result.remove(at: j)
                    changed = true
                    break outer
                }
            }
        }
        return result
    }

    /// Surlignages existants de la page que le nouveau recouvre (ils seront remplacés par la fusion).
    public static func covered(by rects: [PageRect], among existing: [Highlight], page: Int) -> [Highlight] {
        existing.filter { h in h.pageIndex == page && h.rects.contains { r in rects.contains { overlaps($0, r) } } }
    }

    /// Point (repère de la page) sur un surlignage : la gomme l'efface.
    public static func hit(_ x: Double, _ y: Double, in existing: [Highlight], page: Int) -> Highlight? {
        existing.last { h in
            h.pageIndex == page && h.rects.contains { x >= $0.x && x <= $0.x + $0.width && y >= $0.y && y <= $0.y + $0.height }
        }
    }
}
