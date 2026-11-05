// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Temps processeur du fil courant : ce fil a vraiment calculé pendant ce temps, attente exclue. Lire la valeur avant et
/// après un travail synchrone mesure le coût réel de ce travail, sans rien supposer du reste de l'app.
public enum ThreadCPU {
    public static func seconds() -> TimeInterval {
        var info = thread_basic_info()
        var size = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        // `pthread_mach_thread_np` ne prend pas de référence de port, à la différence de `mach_thread_self`.
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                thread_info(pthread_mach_thread_np(pthread_self()), thread_flavor_t(THREAD_BASIC_INFO), $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.user_time.seconds + info.system_time.seconds)
            + Double(info.user_time.microseconds + info.system_time.microseconds) / 1_000_000
    }
}

/// Activités coûteuses de l'app, pour le moniteur. iPadOS ne dit pas quelle fonction consomme le processeur. Deux valeurs
/// différentes sont donc tenues : la part de temps où l'activité a tourné, et, pour le travail synchrone mesuré par
/// `addCPU`, son vrai temps processeur. Sans verrou ni horloge : `ActivityCenter` s'en charge, ce qui rend le calcul testable.
public struct ActivityLedger: Sendable {
    public struct Row: Equatable, Sendable {
        public let kind: String
        public let running: Int
        /// Part de temps active depuis le relevé précédent, de 0 à 1.
        public let busyShare: Double
        /// Secondes de processeur des travaux finis depuis le relevé précédent, sans division par l'intervalle : un relevé
        /// peut tarder, et le travail n'est compté qu'à sa fin. `nil` : activité non mesurée.
        public let cpuSeconds: TimeInterval?
        public let detail: String?
        public let progress: Double?
    }

    private struct Item { let kind: String; var detail: String?; var progress: Double? }
    private struct Clock { var running = 0; var since = Date.distantPast; var busy: TimeInterval = 0; var reported: TimeInterval = 0; var cpu: TimeInterval = 0; var cpuReported: TimeInterval = 0; var measured = false }

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

    /// Temps processeur consommé par ce travail, ajouté à son activité.
    public mutating func addCPU(kind: String, seconds: TimeInterval) {
        var clock = clocks[kind] ?? Clock()
        clock.cpu += max(0, seconds)
        clock.measured = true
        clocks[kind] = clock
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
            let cpu = max(0, clock.cpu - clock.cpuReported)
            clock.reported = busy
            clock.cpuReported = clock.cpu
            clocks[kind] = clock
            guard clock.running > 0 || share > 0 || cpu > 0 else { continue }
            let current = items.values.first { $0.kind == kind }
            rows.append(Row(kind: kind, running: clock.running, busyShare: share, cpuSeconds: clock.measured ? cpu : nil, detail: current?.detail, progress: current?.progress))
        }
        return rows.sorted { ($0.cpuSeconds ?? -1, $0.busyShare, $0.kind) > ($1.cpuSeconds ?? -1, $1.busyShare, $1.kind) }
    }
}
