// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Transitions de l'état thermique **du système** (PLAN-DIAG-001, E2d) : jamais une température ni une cause. États
/// fermés (valeurs de `ProcessInfo.ThermalState`), valeur inconnue gardée comme telle.
public enum DiagnosticThermalLevel: Equatable, Sendable {
    case nominal, fair, serious, critical
    case unknown(Int)

    public init(raw: Int) {
        switch raw {
        case 0: self = .nominal
        case 1: self = .fair
        case 2: self = .serious
        case 3: self = .critical
        default: self = .unknown(raw)
        }
    }

    /// Code écrit dans le journal (0 à 3, sinon -1 pour inconnu).
    public var code: Int {
        switch self {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        case .unknown: return -1
        }
    }

    var isHigh: Bool { self == .serious || self == .critical }
}

/// Suivi dédoublonné : le premier relevé pose la référence sans événement ; ensuite, un événement par vrai
/// changement (alerte vers sérieux/critique ou en en sortant, détail sinon). Relire au retour au premier plan.
public struct DiagnosticThermalTracker: Sendable {
    private var last: DiagnosticThermalLevel?

    public init() {}

    public mutating func observe(raw: Int) -> DiagnosticEvent? {
        let level = DiagnosticThermalLevel(raw: raw)
        defer { last = level }
        guard let previous = last, previous != level else { return nil }
        let important = level.isHigh || previous.isHigh || { if case .unknown = level { return true } else { return false } }()
        let severity: DiagnosticLevel = important ? .alerte : .info
        return DiagnosticEvent(severity, .energie, "etat_thermique", counts: [DiagnosticCount("avant", previous.code),
                                                                            DiagnosticCount("apres", level.code)])
    }
}
