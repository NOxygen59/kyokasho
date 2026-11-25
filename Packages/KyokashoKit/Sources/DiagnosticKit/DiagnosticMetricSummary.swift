// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Essai facultatif de MetricKit (PLAN-DIAG-001, E2f, DEC-04 A) : seulement des **comptes**. Jamais de JSON brut,
/// de pile, de métadonnée libre, d'envoi, ni de rattachement automatique à une session. Une valeur absente
/// (`nil`) n'est pas écrite : l'absence reste distincte de zéro.
public enum DiagnosticMetricSummary {
    /// Lot de mesures (`MXMetricPayload`) : nombre de lots, sorties au premier plan par limite mémoire et par chien de
    /// garde si iOS les fournit.
    public static func metrics(payloads: Int, memoryLimitExits: Int?, watchdogExits: Int?) -> DiagnosticEvent {
        var counts = [DiagnosticCount("lots", payloads)]
        if let memoryLimitExits { counts.append(DiagnosticCount("sorties_limite_memoire", memoryLimitExits)) }
        if let watchdogExits { counts.append(DiagnosticCount("sorties_chien_de_garde", watchdogExits)) }
        return DiagnosticEvent(.alerte, .performances, "metrickit_mesures", counts: counts)
    }

    /// Lot de diagnostics (`MXDiagnosticPayload`) : nombre de lots, de plantages et de gels si présents.
    public static func diagnostics(payloads: Int, crashes: Int?, hangs: Int?) -> DiagnosticEvent {
        var counts = [DiagnosticCount("lots", payloads)]
        if let crashes { counts.append(DiagnosticCount("plantages", crashes)) }
        if let hangs { counts.append(DiagnosticCount("gels", hangs)) }
        return DiagnosticEvent(.alerte, .performances, "metrickit_diagnostics", counts: counts)
    }

    /// Abonnement tenté (ou retiré), avec la version d'iOS en nombres.
    public static func subscription(on: Bool, systemMajor: Int, systemMinor: Int) -> DiagnosticEvent {
        DiagnosticEvent(.alerte, .performances, on ? "metrickit_abonnement" : "metrickit_desabonnement",
                        counts: [DiagnosticCount("ios_majeur", systemMajor), DiagnosticCount("ios_mineur", systemMinor)])
    }
}

/// Génération de l'abonnement : un rappel arrivé après la désactivation (ou d'un abonnement précédent) est rejeté.
public struct DiagnosticSubscriptionGate: Sendable {
    public private(set) var generation: UInt64 = 0
    public private(set) var active = false

    public init() {}

    /// Active (idempotent) ; rend la génération à capturer par l'abonné, ou `nil` si déjà actif.
    public mutating func enable() -> UInt64? {
        guard !active else { return nil }
        active = true
        generation &+= 1
        return generation
    }

    /// Désactive (idempotent) ; `true` si l'état a changé.
    public mutating func disable() -> Bool {
        guard active else { return false }
        active = false
        generation &+= 1
        return true
    }

    public func accepts(_ token: UInt64) -> Bool { active && token == generation }
}
