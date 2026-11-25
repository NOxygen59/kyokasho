// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Sonde du fil principal (PLAN-DIAG-001, E2e, DEC-03 A) : décisions seulement, sans minuterie ni fil, pour être
/// éprouvée sur Mac. L'app envoie un battement au fil principal (une seule requête en vol) et passe ici l'instant
/// d'envoi et l'instant de réponse. On ne note que le **délai observé** au-delà du seuil, jamais une durée exacte de
/// blocage ni une cause.
///
/// Écartés : la première mesure après un (ré)armement (démarrage à froid), une mesure qui a traversé une veille de
/// l'appareil (les deux horloges divergent), une mesure pendant laquelle l'observateur lui-même s'est tu (trou
/// d'observation : tout le processus était figé ou suspendu, ce n'est pas le fil principal seul), et les lignes trop
/// rapprochées (dédoublonnage, nombre et pire délai omis reportés sur la ligne suivante).
public struct DiagnosticMainThreadProbe: Sendable {
    /// Deux horloges monotones lues au même instant : `uptime` s'arrête pendant la veille, `continuous` non.
    public struct Instant: Sendable, Equatable {
        public let uptimeNs: UInt64
        public let continuousNs: UInt64
        public init(uptimeNs: UInt64, continuousNs: UInt64) {
            self.uptimeNs = uptimeNs
            self.continuousNs = continuousNs
        }

        public static func now() -> Instant {
            Instant(uptimeNs: clock_gettime_nsec_np(CLOCK_UPTIME_RAW), continuousNs: clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW))
        }
    }

    /// DEC-03 A : seuil de 250 ms.
    public static let thresholdMs = 250
    /// Intervalle entre deux battements, en millisecondes.
    public static let intervalMs = 500
    /// Au plus une ligne toutes les 10 s ; les délais entre-temps sont comptés.
    public static let minimumGapNs: UInt64 = 10_000_000_000
    /// Écart toléré entre les deux horloges avant de conclure à une veille (bruit de lecture, ordonnancement).
    static let sleepMarginNs: UInt64 = 100_000_000
    /// Silence de l'observateur au-delà duquel la mesure est un trou d'observation (4 battements).
    public static let observationHoleNs: UInt64 = 2_000_000_000

    private var warm = false
    private var lastTickNs: UInt64?
    private var hole = false
    private var lastLineNs: UInt64?
    private var omitted = 0
    private var omittedWorstMs = 0

    public init() {}

    /// Nouveau départ (mode allumé, retour au premier plan) : la mesure suivante est ignorée.
    public mutating func rearm() { warm = false }

    /// Chaque réveil de l'observateur, requête en vol ou non. Un silence plus long que `observationHoleNs` marque la
    /// requête en vol comme traversant un trou d'observation.
    public mutating func tick(at now: Instant) {
        if let last = lastTickNs, now.uptimeNs &- last > Self.observationHoleNs { hole = true }
        lastTickNs = now.uptimeNs
    }

    /// Envoi d'un battement : départ d'une nouvelle mesure, sans trou.
    public mutating func send(at now: Instant) {
        lastTickNs = now.uptimeNs
        hole = false
    }

    /// Une réponse du fil principal. Renvoie l'événement à écrire, ou nil.
    public mutating func observe(sent: Instant, answered: Instant) -> DiagnosticEvent? {
        let wasWarm = warm
        warm = true
        // La mesure commence à son envoi : un réveil plus ancien (ou un trou d'avant) ne la concerne pas.
        if lastTickNs.map({ $0 < sent.uptimeNs }) ?? true { send(at: sent) }
        // Trou jusqu'à la réponse elle-même (processus repris : réponse et réveil arrivent ensemble).
        tick(at: answered)
        let crossedHole = hole
        hole = false
        guard !crossedHole else { return nil }
        guard answered.uptimeNs >= sent.uptimeNs, answered.continuousNs >= sent.continuousNs else { return nil }
        let delayNs = answered.uptimeNs - sent.uptimeNs
        // Veille : l'horloge continue a avancé nettement plus que celle qui s'arrête pendant la veille.
        guard wasWarm, answered.continuousNs - sent.continuousNs <= delayNs + Self.sleepMarginNs else { return nil }
        let delayMs = Int(clamping: delayNs / 1_000_000)
        guard delayMs >= Self.thresholdMs else { return nil }
        if let last = lastLineNs, answered.uptimeNs &- last < Self.minimumGapNs {
            omitted += 1
            omittedWorstMs = max(omittedWorstMs, delayMs)
            return nil
        }
        var counts = [DiagnosticCount("seuil_ms", Self.thresholdMs)]
        if omitted > 0 {
            counts.append(DiagnosticCount("omis", omitted))
            counts.append(DiagnosticCount("omis_max_ms", omittedWorstMs))
        }
        lastLineNs = answered.uptimeNs
        omitted = 0
        omittedWorstMs = 0
        return DiagnosticEvent(.info, .performances, "fil_principal_lent", durationMs: delayMs, counts: counts)
    }
}
