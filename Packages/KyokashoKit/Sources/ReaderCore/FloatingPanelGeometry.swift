// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Géométrie du panneau flottant. Le même calcul sert à l'aperçu et au relâchement du geste.
public enum FloatingPanelGeometry {
    /// Rectangle visible de départ après rotation/Split View, indépendamment des valeurs persistées.
    public static func constrained(_ stored: CGRect, area: CGSize, minimum: CGSize) -> CGRect {
        let available = CGSize(width: max(0, area.width), height: max(0, area.height))
        let w = min(max(minimum.width, stored.width), available.width)
        let h = min(max(minimum.height, stored.height), available.height)
        return CGRect(x: min(max(0, stored.minX), available.width - w),
                      y: min(max(0, stored.minY), available.height - h), width: w, height: h)
    }

    /// Translation totale depuis le début du geste, appliquée une seule fois au rectangle de départ.
    public static func moved(_ start: CGRect, by translation: CGSize, area: CGSize, minimum: CGSize) -> CGRect {
        let base = constrained(start, area: area, minimum: minimum)
        return constrained(base.offsetBy(dx: translation.width, dy: translation.height), area: area, minimum: minimum)
    }

    /// Le coin supérieur gauche reste fixe ; le coin inférieur droit s'arrête aux limites disponibles.
    public static func resized(_ start: CGRect, by translation: CGSize, area: CGSize, minimum: CGSize) -> CGRect {
        let base = constrained(start, area: area, minimum: minimum)
        return CGRect(origin: base.origin,
                      size: CGSize(width: min(max(minimum.width, base.width + translation.width), max(0, area.width - base.minX)),
                                   height: min(max(minimum.height, base.height + translation.height), max(0, area.height - base.minY))))
    }
}
