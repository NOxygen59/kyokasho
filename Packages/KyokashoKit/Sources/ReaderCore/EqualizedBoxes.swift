// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics

/// Cache des pages « égalisées » (même hauteur) : une boîte source par page, écrite en `[[x, y, largeur, hauteur]]`.
/// C1.4 (audit du 09/11/2026) : une ligne sans ses quatre valeurs faisait planter la lecture du cache (`$0[3]`).
public enum EqualizedBoxes {
    /// Boîtes du cache, ou `nil` si une ligne n'a pas exactement quatre valeurs (cache à refaire).
    public static func rects(_ saved: [[CGFloat]]) -> [CGRect]? {
        guard saved.allSatisfy({ $0.count == 4 }) else { return nil }
        return saved.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
    }
}
