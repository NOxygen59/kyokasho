// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Temps de lecture active affiché sur l'accueil à la place de « Progression XX/XX pages » (RET-037, #52).
///
/// « Active » : un livre est ouvert à l'écran et l'app est au premier plan. Le compteur démarre à l'ouverture du
/// lecteur et s'arrête à sa fermeture, au passage en arrière-plan ou au verrouillage. Il part de zéro : le temps
/// passé avant cette version n'a jamais été enregistré.
public struct ReadingClock: Equatable, Sendable {
    /// Plafond d'une seule séance : protège le total si un arrêt n'a pas été reçu (app tuée en arrière-plan).
    public static let maxSession: TimeInterval = 6 * 3600

    public private(set) var total: TimeInterval
    public private(set) var startedAt: Date?

    public init(total: TimeInterval = 0) { self.total = max(0, total) }

    public mutating func start(at date: Date) {
        if startedAt == nil { startedAt = date }
    }

    /// Arrête la séance et ajoute sa durée (bornée entre 0 et ``maxSession``). Sans séance en cours, rien.
    public mutating func stop(at date: Date) {
        guard let startedAt else { return }
        total += min(max(0, date.timeIntervalSince(startedAt)), Self.maxSession)
        self.startedAt = nil
    }

    /// Total, séance en cours comprise.
    public func elapsed(at date: Date) -> TimeInterval {
        guard let startedAt else { return total }
        return total + min(max(0, date.timeIntervalSince(startedAt)), Self.maxSession)
    }

    /// « 35 min », « 4 h 12 », « 2 j 5 h », « 1 mois 3 j » : la plus grande unité utile et la suivante.
    public static func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let hours = minutes / 60, days = hours / 24, months = days / 30
        if months > 0 { return days % 30 > 0 ? "\(months) mois \(days % 30) j" : "\(months) mois" }
        if days > 0 { return hours % 24 > 0 ? "\(days) j \(hours % 24) h" : "\(days) j" }
        if hours > 0 { return String(format: "%d h %02d", hours, minutes % 60) }
        return "\(minutes) min"
    }
}
