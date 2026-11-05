// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Activités coûteuses de l'app, pour le moniteur de l'accueil. iPadOS ne dit pas quelle fonction consomme le processeur :
/// la valeur donnée ici est la part de temps où l'activité a tourné, jamais un pourcentage de CPU. Sans verrou ni horloge :
/// `ActivityCenter` s'en charge, ce qui rend le calcul testable.
public struct ActivityLedger: Sendable {
    public struct Row: Equatable, Sendable {
        public let kind: String
        public let running: Int
        /// Part de temps active depuis le relevé précédent, de 0 à 1.
        public let busyShare: Double
        public let detail: String?
        public let progress: Double?
    }

    private struct Item { let kind: String; var detail: String?; var progress: Double? }
    private struct Clock { var running = 0; var since = Date.distantPast; var busy: TimeInterval = 0; var reported: TimeInterval = 0 }

    private var items: [UUID: Item] = [:]
    private var clocks: [String: Clock] = [:]
    private var lastSnapshot: Date?

    public init() {}

    public mutating func begin(_ id: UUID, kind: String, detail: String?, at now: Date) {
        items[id] = Item(kind: kind, detail: detail)
        var clock = clocks[kind] ?? Clock()
        if clock.running == 0 { clock.since = now }
        clock.running += 1
        clocks[kind] = clock
    }

    public mutating func update(_ id: UUID, detail: String?, progress: Double?) {
        if let detail { items[id]?.detail = detail }
        items[id]?.progress = progress
    }

    /// Sans effet si l'activité est déjà finie : une fin en double ne fausse aucun compteur.
    public mutating func end(_ id: UUID, at now: Date) {
        guard let item = items.removeValue(forKey: id), var clock = clocks[item.kind] else { return }
        clock.running -= 1
        if clock.running == 0 { clock.busy += now.timeIntervalSince(clock.since) }
        clocks[item.kind] = clock
    }

    /// Activités en cours ou actives depuis le dernier relevé, les plus actives d'abord.
    public mutating func snapshot(at now: Date) -> [Row] {
        let window = max(lastSnapshot.map { now.timeIntervalSince($0) } ?? 1, 0.001)
        lastSnapshot = now
        var rows: [Row] = []
        for (kind, clock) in clocks {
            var clock = clock
            let busy = clock.busy + (clock.running > 0 ? now.timeIntervalSince(clock.since) : 0)
            let share = min(1, max(0, (busy - clock.reported) / window))
            clock.reported = busy
            clocks[kind] = clock
            guard clock.running > 0 || share > 0 else { continue }
            let current = items.values.first { $0.kind == kind }
            rows.append(Row(kind: kind, running: clock.running, busyShare: share, detail: current?.detail, progress: current?.progress))
        }
        return rows.sorted { ($0.busyShare, $0.kind) > ($1.busyShare, $1.kind) }
    }
}
