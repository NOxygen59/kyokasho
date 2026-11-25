// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Travaux longs suivis par la session (PLAN-DIAG-001, E2c) : liste **fermée**, rien d'autre (ni page, ni document,
/// ni texte). Les travaux non suivis (IA, OCR…) restent inconnus en E2 ; E4 élargira.
public enum DiagnosticTrackedWork: String, Codable, Sendable, CaseIterable {
    case sauvegarde, importPDF = "import_pdf", importCBZ = "import_cbz", conversionCBZ = "conversion_cbz"

    /// Zone du journal de la ligne qui rapporte ce travail.
    public var zone: DiagnosticZone { self == .sauvegarde ? .sauvegarde : .importation }
}

/// Un travail en cours : son type et son `op`, tels qu'écrits au début du travail.
public struct DiagnosticOngoingEntry: Codable, Equatable, Sendable {
    public let kind: DiagnosticTrackedWork
    public let op: UInt32
    public init(kind: DiagnosticTrackedWork, op: UInt32) { self.kind = kind; self.op = op }
}

/// Projection bornée des travaux en cours, avec sa révision : une publication plus ancienne que la dernière écrite
/// est ignorée. Tronquée ou vide = connaissance limitée, jamais « rien ne tournait ».
public struct DiagnosticOngoing: Equatable, Sendable {
    public static let limit = 8
    public var entries: [DiagnosticOngoingEntry]
    public var truncated: Bool
    public var revision: UInt64

    public init(entries: [DiagnosticOngoingEntry] = [], truncated: Bool = false, revision: UInt64 = 0) {
        self.entries = entries
        self.truncated = truncated
        self.revision = revision
    }
}

/// Registre des travaux suivis (sous le verrou de l'appelant) : ordre stable d'arrivée, une révision par changement.
public struct DiagnosticOngoingRegistry: Sendable {
    private var items: [(token: UUID, entry: DiagnosticOngoingEntry)] = []
    private var revision: UInt64 = 0

    public init() {}

    /// Début d'un travail suivi : son `op` (fourni, sinon nouveau) et la projection à publier.
    public mutating func begin(_ token: UUID, kind: DiagnosticTrackedWork,
                               op: DiagnosticOperation = .new()) -> DiagnosticOngoing {
        items.append((token, DiagnosticOngoingEntry(kind: kind, op: op.raw)))
        revision &+= 1
        return snapshot
    }

    /// Fin (réussie, en erreur ou annulée) : `nil` si ce travail n'était pas suivi.
    public mutating func end(_ token: UUID) -> DiagnosticOngoing? {
        guard let index = items.firstIndex(where: { $0.token == token }) else { return nil }
        items.remove(at: index)
        revision &+= 1
        return snapshot
    }

    public func op(for token: UUID) -> UInt32? { items.first { $0.token == token }?.entry.op }

    public var snapshot: DiagnosticOngoing {
        DiagnosticOngoing(entries: Array(items.prefix(DiagnosticOngoing.limit).map(\.entry)),
                          truncated: items.count > DiagnosticOngoing.limit, revision: revision)
    }
}
