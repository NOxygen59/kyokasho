// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Un ajout de pages réussi (« Ajouter des pages… ») : historique montré dans « Ce document » (RET-033, #48).
public struct PageAddition: Codable, Equatable, Sendable {
    public var date: Date
    /// Pages ajoutées en tout.
    public var added: Int
    /// Pages ajoutées **avant** celles du document (0 : tout à la fin).
    public var insertedBefore: Int
    public var totalAfter: Int
    /// Noms des PDF ajoutés, dans l'ordre choisi.
    public var sources: [String]

    public init(date: Date, added: Int, insertedBefore: Int, totalAfter: Int, sources: [String]) {
        self.date = date
        self.added = added
        self.insertedBefore = insertedBefore
        self.totalAfter = totalAfter
        self.sources = sources
    }

    /// « 12 pages ajoutées au début · 3 pages à la fin » ; une seule partie quand l'autre est vide.
    public var summary: String {
        let after = added - insertedBefore
        var parts: [String] = []
        if insertedBefore > 0 { parts.append(String(localized: "\(Self.pages(insertedBefore)) ajoutée\(insertedBefore > 1 ? "s" : "") au début", bundle: .main)) }
        if after > 0 { parts.append(insertedBefore > 0 ? String(localized: "\(Self.pages(after)) à la fin", bundle: .main) : String(localized: "\(Self.pages(after)) ajoutée\(after > 1 ? "s" : "") à la fin", bundle: .main)) }
        return parts.joined(separator: " · ")
    }

    private static func pages(_ n: Int) -> String { String(localized: "\(n) page\(n > 1 ? "s" : "")", bundle: .main) }
}

/// Historique des ajouts de pages d'un document, le plus récent en dernier. Il part de cette version : les ajouts
/// plus anciens n'ont jamais été enregistrés.
public struct PageAdditionLog: Equatable, Sendable {
    /// Au-delà, les plus anciens partent (un manuel reçoit quelques ajouts, pas des centaines).
    public static let maxEntries = 100

    public private(set) var entries: [PageAddition]

    public init(entries: [PageAddition] = []) { self.entries = entries }

    /// Rien si aucune page n'a été ajoutée.
    public mutating func record(_ addition: PageAddition) {
        guard addition.added > 0 else { return }
        entries.append(addition)
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(entries) }

    /// Données absentes ou illisibles : historique vide (le document n'en dépend pas).
    public static func decode(_ data: Data?) -> PageAdditionLog {
        guard let data, let entries = try? JSONDecoder().decode([PageAddition].self, from: data) else { return PageAdditionLog() }
        return PageAdditionLog(entries: entries)
    }
}
