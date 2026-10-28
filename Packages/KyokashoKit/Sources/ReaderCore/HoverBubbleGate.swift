// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Bulle du dictionnaire ouverte au survol avec Maj dans le texte OCR (RET-042, #61), sans UIKit pour être testée
/// sur Mac.
///
/// Quitter un mot ne ferme pas la bulle tout de suite : un délai laisse au pointeur le temps d'entrer dans la bulle.
/// Avant ce correctif, ce délai fermait aussi la bulle d'un mot atteint **pendant** le délai : en balayant vite d'un
/// mot à l'autre, la bulle du nouveau mot se fermait aussitôt, ou ne se rouvrait pas. Chaque ouverture change de
/// génération ; une fermeture différée ne s'applique que si aucune ouverture n'a eu lieu depuis.
public struct HoverBubbleGate: Equatable, Sendable {
    public private(set) var generation = 0

    public init() {}

    /// Une bulle s'ouvre (ou change de mot) : toute fermeture différée en attente devient caduque.
    public mutating func opened() { generation &+= 1 }

    /// Jeton à garder pour une fermeture différée.
    public var token: Int { generation }

    /// La fermeture différée prise avec `token` s'applique-t-elle encore ?
    public func shouldClose(token: Int) -> Bool { token == generation }

    /// Passer d'un mot à un autre au survol garde la même bulle (seuls le contenu et la position changent) : elle ne
    /// rejoue pas son animation d'apparition à chaque mot.
    public static func reusesBubble(currentIsHover: Bool?, incomingIsHover: Bool) -> Bool {
        currentIsHover == true && incomingIsHover
    }
}
