// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Mise à l'écart des fichiers de diagnostic écrits avant PLAN-DIAG-001 (DEC-07 A), comme **condition d'accès** :
/// tant qu'elle n'a pas réussi, l'app n'écrit, ne lit ni ne partage aucun fichier de diagnostic (réunion DIAG du
/// 25/11, arbitrage D1). Jamais d'effacement ni d'écrasement : un ancien fichier est déplacé vers un nom libre de sa
/// famille, et un échec laisse l'état bloqué jusqu'au lancement suivant.
///
/// Logique pure, opérations disque injectées (tests de chaque échec).
public enum DiagnosticFileMigration {
    /// Révision de la migration, distincte de l'ancienne valeur « 2 » de `diagnostics.formatVersion` : une version
    /// intermédiaire (f067d83) écrivait « 2 » sans avoir isolé le relevé de batterie, ce « 2 » ne prouve donc rien.
    public static let revision = 3

    /// Familles d'anciens fichiers : l'actif et le nom de base de sa mise à l'écart.
    public enum Family: Sendable { case journal, energy }

    public struct Active: Sendable, Equatable {
        public let name: String
        public let family: Family
        public init(name: String, family: Family) { self.name = name; self.family = family }
    }

    /// Fichiers actifs à vérifier : `journal.1.txt` compris (origine incertaine si une tentative précédente a tourné
    /// un ancien journal, cas S4).
    public static let actives: [Active] = [
        Active(name: "journal.txt", family: .journal),
        Active(name: "journal.1.txt", family: .journal),
        Active(name: "energie.csv", family: .energy),
    ]

    /// Noms de mise à l'écart d'une famille : le nom de base, puis `-2` … `-20`.
    public static func isolatedNames(_ family: Family) -> [String] {
        let (base, ext) = family == .journal ? ("journal-avant-diagnostics", "txt") : ("energie-avant-diagnostics", "csv")
        return ["\(base).\(ext)"] + (2...20).map { "\(base)-\($0).\(ext)" }
    }

    /// État d'un fichier : absent, présent, ou illisible (une erreur d'accès n'est **pas** une absence).
    public enum Presence: Sendable { case absent, present, unknown }

    public struct Operations {
        public var presence: (String) -> Presence
        /// Déplace sans jamais remplacer ; `false` si la cible existe ou si le déplacement échoue.
        public var move: (_ from: String, _ to: String) -> Bool
        public init(presence: @escaping (String) -> Presence, move: @escaping (String, String) -> Bool) {
            self.presence = presence
            self.move = move
        }
    }

    public enum Outcome: Equatable, Sendable {
        /// Rien d'ancien n'est actif : écriture, lecture et partage permis ; la révision peut être enregistrée.
        case ready
        /// Au moins un ancien fichier n'a pas pu être isolé (ou une révision future inconnue) : tout reste bloqué.
        case blocked
    }

    /// Décide et agit. `storedRevision` : valeur enregistrée lors d'une migration réussie (0 si aucune).
    public static func run(storedRevision: Int, operations: Operations) -> Outcome {
        if storedRevision == revision { return .ready }
        if storedRevision > revision { return .blocked }   // version future inconnue : prudence
        var ok = true
        for active in actives {      // chaque actif est traité, même après l'échec d'un autre
            switch operations.presence(active.name) {
            case .absent: continue
            case .unknown: ok = false
            case .present:
                let free = isolatedNames(active.family).first { operations.presence($0) == .absent }
                if let free, operations.move(active.name, free) { continue }
                ok = false
            }
        }
        return ok ? .ready : .blocked
    }
}
