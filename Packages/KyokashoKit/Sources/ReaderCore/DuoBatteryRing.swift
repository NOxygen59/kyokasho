// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59
//
// Géométrie, proportions et règle de couleur reprises de DuoBar, sous licence MIT :
// https://github.com/Mikeli7666/DuoBar — Copyright (c) 2026 Mike Li. Voir THIRD_PARTY_NOTICES.md.

import CoreGraphics
import Foundation

/// Anneau de batterie de l'iPhone Duo, sans SwiftUI pour être testé sur Mac.
public struct DuoBatteryRing: Equatable, Sendable {
    public enum Tint: Equatable, Sendable { case normal, charging, lowPower, low }

    /// Ouverture en bas de l'anneau, en degrés.
    public static let gapDegrees = 120.22
    /// Sens : 0° à droite, 90° en bas, l'arc passe par le haut.
    public static let startDegrees = 90 + gapDegrees / 2
    public static let endDegrees = 450 - gapDegrees / 2
    /// Proportions mesurées par DuoBar, pour un anneau de diamètre 1.
    public static let strokeRatio = 0.076378
    public static let trackOpacity = 0.24
    public static let boltFontRatio = (50 / 1.16) / 230
    public static let boltGapRatio = 14.5 / 230
    public static let lowLevel = 0.2

    public let progress: Double
    public let tint: Tint
    public let showsBolt: Bool

    /// `level` : de 0 à 1, négatif si iPadOS ne le connaît pas. `pluggedIn` : secteur branché, en charge ou pleine.
    /// Comme iOS et DuoBar : batterie pleine, blanc sans éclair ; branchée, vert ; mode économie, jaune ; sous 20 %, rouge.
    public init(level: Double, charging: Bool, full: Bool, lowPowerMode: Bool) {
        let known = level >= 0
        progress = known ? min(level, 1) : 0
        if full {
            tint = .normal
            showsBolt = false
        } else if charging {
            tint = .charging
            showsBolt = true
        } else if lowPowerMode {
            tint = .lowPower
            showsBolt = false
        } else if known, level < Self.lowLevel {
            tint = .low
            showsBolt = false
        } else {
            tint = .normal
            showsBolt = false
        }
    }

    /// Les quatre points dans l'ouverture de l'anneau, à gauche puis à droite : décalage depuis le centre pour un anneau de
    /// diamètre 1, y vers le bas. Mesures de DuoBar.
    public static let dotDiameterRatio = 0.096502
    public static var dotOffsets: [CGPoint] {
        [-32.273, -10.813, 10.813, 32.273].map { degrees in
            let radians = degrees * .pi / 180
            return CGPoint(x: sin(radians) * 0.45545, y: cos(radians) * 0.45545)
        }
    }

    /// Fin de l'arc rempli, en degrés.
    public var filledEndDegrees: Double { Self.startDegrees + (Self.endDegrees - Self.startDegrees) * progress }
}
