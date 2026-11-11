// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Correspondance entre les pages d'un document avant et après une modification de ses pages
/// (ajout, suppression, restauration ; #49, plan revu par Codex le 29/10/2026).
///
/// Invariants, vérifiés à la construction **et** au décodage d'un journal (un journal altéré ne passe pas) :
/// - chaque ancienne page apparaît exactement une fois : une nouvelle position, ou `nil` si elle est retirée ;
/// - les positions gardées sont dans `0..<newCount`, strictement croissantes (donc uniques, ordre conservé) ;
/// - il reste au moins une page.
/// Les positions nouvelles absentes de l'image sont les pages insérées.
public struct PageMapping: Codable, Equatable, Sendable {
    public let oldCount: Int
    public let newCount: Int
    /// `targets[ancienne] = nouvelle position`, ou `nil` si la page est retirée.
    public let targets: [Int?]

    public enum Failure: LocalizedError, Equatable {
        case emptySelection
        case pageOutOfRange(Int)
        case removesEverything
        case invalidTargets

        public var errorDescription: String? {
            switch self {
            case .emptySelection: return String(localized: "Aucune page choisie.", bundle: .main)
            case .pageOutOfRange(let page): return String(localized: "La page \(page + 1) n'existe pas dans ce document.", bundle: .main)
            case .removesEverything: return String(localized: "Impossible de supprimer toutes les pages d'un document.", bundle: .main)
            case .invalidTargets: return String(localized: "Correspondance de pages invalide : aucune modification effectuée.", bundle: .main)
            }
        }
    }

    public init(oldCount: Int, newCount: Int, targets: [Int?]) throws {
        guard oldCount > 0, newCount > 0, targets.count == oldCount else { throw Failure.invalidTargets }
        var previous = -1
        for case let target? in targets {
            guard target > previous, target < newCount else { throw Failure.invalidTargets }
            previous = target
        }
        guard previous >= 0 else { throw Failure.removesEverything }
        self.oldCount = oldCount
        self.newCount = newCount
        self.targets = targets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(oldCount: container.decode(Int.self, forKey: .oldCount),
                      newCount: container.decode(Int.self, forKey: .newCount),
                      targets: container.decode([Int?].self, forKey: .targets))
    }

    /// `inserted` pages ajoutées avant l'ancienne page `offset` (`offset == oldCount` : à la fin).
    public static func insertion(oldCount: Int, inserted: Int, at offset: Int) throws -> PageMapping {
        guard inserted > 0 else { throw Failure.emptySelection }
        guard offset >= 0, offset <= oldCount else { throw Failure.pageOutOfRange(offset) }
        return try PageMapping(oldCount: oldCount, newCount: oldCount + inserted,
                               targets: (0..<oldCount).map { $0 < offset ? $0 : $0 + inserted })
    }

    /// Retire les pages `removed` (indices de base 0) ; les suivantes remontent.
    public static func removal(oldCount: Int, removing removed: Set<Int>) throws -> PageMapping {
        guard !removed.isEmpty else { throw Failure.emptySelection }
        if let outside = removed.sorted().first(where: { $0 < 0 || $0 >= oldCount }) { throw Failure.pageOutOfRange(outside) }
        guard removed.count < oldCount else { throw Failure.removesEverything }
        var next = 0
        let targets: [Int?] = (0..<oldCount).map { page in
            guard !removed.contains(page) else { return nil }
            defer { next += 1 }
            return next
        }
        return try PageMapping(oldCount: oldCount, newCount: oldCount - removed.count, targets: targets)
    }

    public func target(of page: Int) -> Int? {
        targets.indices.contains(page) ? targets[page] : nil
    }

    /// Anciennes pages retirées, dans l'ordre.
    public var removed: [Int] { targets.indices.filter { targets[$0] == nil } }

    /// Nouvelles positions qui ne viennent d'aucune ancienne page (pages insérées).
    public var inserted: [Int] {
        let kept = Set(targets.compactMap { $0 })
        return (0..<newCount).filter { !kept.contains($0) }
    }

    /// `self` puis `next` : sert à suivre une ancienne référence de page (liens du chat, R4) à travers plusieurs
    /// modifications. Une page retirée par l'une des deux étapes reste retirée.
    public func then(_ next: PageMapping) throws -> PageMapping {
        guard next.oldCount == newCount else { throw Failure.invalidTargets }
        return try PageMapping(oldCount: oldCount, newCount: next.newCount,
                               targets: targets.map { $0.flatMap(next.target(of:)) })
    }
}
