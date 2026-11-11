// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Corbeille des documents (idée de NOxygen59, recette 1.3.2 (62)) : « Supprimer » met un document de côté au lieu de
/// l'effacer. Il disparaît de la bibliothèque mais garde tout (PDF, notes, OCR, cartes) et peut être restauré ; il
/// n'est effacé pour de bon qu'à « Supprimer définitivement », « Vider la corbeille », ou après ``retention``.
///
/// Seule la date de mise à la corbeille est gardée ici (préférences de l'app, donc dans la sauvegarde) ; le
/// document lui-même ne bouge pas de la base ni du disque.
public struct DocumentTrash: Codable, Equatable, Sendable {
    /// Durée avant effacement automatique.
    public static let retention: TimeInterval = 30 * 86_400

    /// Document → date de mise à la corbeille.
    public private(set) var entries: [String: Date] = [:]

    public init(entries: [String: Date] = [:]) { self.entries = entries }

    public func contains(_ id: String) -> Bool { entries[id] != nil }

    public mutating func put(_ id: String, at date: Date = Date()) {
        if entries[id] == nil { entries[id] = date }
    }

    public mutating func remove(_ id: String) { entries[id] = nil }

    /// Documents dont le délai est dépassé, à effacer pour de bon.
    public func expired(at now: Date = Date()) -> [String] {
        entries.filter { now.timeIntervalSince($0.value) >= Self.retention }.map(\.key).sorted()
    }

    /// Jours restants avant l'effacement automatique (0 au plus tard aujourd'hui).
    public func daysLeft(_ id: String, at now: Date = Date()) -> Int? {
        guard let date = entries[id] else { return nil }
        return max(0, Int(ceil((Self.retention - now.timeIntervalSince(date)) / 86_400)))
    }

    /// Entrées de documents qui n'existent plus (effacés ailleurs) : retirées.
    public mutating func keep(only existing: Set<String>) {
        entries = entries.filter { existing.contains($0.key) }
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decode(_ data: Data?) -> DocumentTrash {
        guard let data, let trash = try? JSONDecoder().decode(DocumentTrash.self, from: data) else { return DocumentTrash() }
        return trash
    }
}
