// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

/// Jeton de génération pour ignorer un résultat asynchrone devenu ancien (rappel JavaScript, bloc différé).
/// Chaque événement qui rend les résultats en cours caducs (nouvelle page HTML, nouvelle bascule) appelle
/// `advance()` ; un rappel garde le jeton reçu au départ et ne s'applique que si `isCurrent(_:)` est vrai.
/// Utilisé par la bascule de langue de la vue web OCR (`RubyWebView`, revue de Codex sur la PR #78).
public struct LatestGeneration: Sendable, Equatable {
    public private(set) var value = 0

    public init() {}

    /// Rend caducs tous les jetons déjà distribués et renvoie le nouveau.
    @discardableResult
    public mutating func advance() -> Int {
        value &+= 1
        return value
    }

    /// Vrai seulement pour le dernier jeton distribué.
    public func isCurrent(_ token: Int) -> Bool { token == value }
}
