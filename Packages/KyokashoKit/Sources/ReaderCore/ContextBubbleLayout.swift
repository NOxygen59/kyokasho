// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics

/// Placement de la bulle de dictionnaire ancrée au mot dans la fenêtre OCR (Issue #13).
///
/// Règles : au plus `maxSize` (360 × 300 pt) et `maxFraction` (80 %) de la zone ; sous le mot s'il y a la place,
/// sinon au-dessus, sinon du côté le plus grand ; jamais hors de la zone (marge `margin`). Le calcul est pur pour
/// être testé sans UIKit ; les rectangles sont dans le repère de la zone qui contient la bulle.
public enum ContextBubbleLayout {
    public static let maxSize = CGSize(width: 360, height: 300)
    public static let maxFraction: CGFloat = 0.8
    public static let margin: CGFloat = 8
    public static let gap: CGFloat = 6

    /// Taille de la bulle pour une zone donnée.
    public static func size(in container: CGSize) -> CGSize {
        CGSize(width: max(0, min(maxSize.width, container.width * maxFraction, container.width - 2 * margin)),
               height: max(0, min(maxSize.height, container.height * maxFraction, container.height - 2 * margin)))
    }

    /// Cadre de la bulle pour le mot `word` dans une zone de taille `container`.
    public static func frame(word: CGRect, in container: CGSize) -> CGRect {
        let size = size(in: container)
        let below = container.height - margin - (word.maxY + gap)
        let above = word.minY - gap - margin
        let y: CGFloat
        if below >= size.height {
            y = word.maxY + gap
        } else if above >= size.height {
            y = word.minY - gap - size.height
        } else {
            // Aucune place entière : du côté le plus grand, bornée à la zone (elle peut alors couvrir le mot).
            y = below >= above ? container.height - margin - size.height : margin
        }
        // Centrée sur le mot à l'horizontale, puis ramenée dans la zone.
        let x = min(max(margin, word.midX - size.width / 2), max(margin, container.width - margin - size.width))
        return CGRect(x: x, y: max(margin, y), width: size.width, height: size.height)
    }
}
