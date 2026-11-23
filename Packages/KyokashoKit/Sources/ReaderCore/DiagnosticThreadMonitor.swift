// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

public enum DiagnosticThreads {
    public static let limit = 12
    public static let threshold = 5.0

    /// Rejette le nom entier si un octet n'est pas autorisé, y compris après le plafond.
    public static func safeName(_ name: String?) -> String? {
        guard let name, !name.isEmpty, name.utf8.allSatisfy({
            switch $0 {
            case 45, 46, 48...57, 65...90, 95, 97...122: return true
            default: return false
            }
        }) else { return nil }
        return String(name.prefix(40))
    }

    public static func hot(_ loads: [DiagnosticCPULog.ThreadLoad]) -> [DiagnosticCPULog.ThreadLoad] {
        loads.filter { $0.percent.isFinite && $0.percent >= threshold }.sorted {
            $0.percent == $1.percent ? $0.id < $1.id : $0.percent > $1.percent
        }
    }

    public struct Alias: Sendable {
        let label: String
        public init() { label = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased() }
    }

    public struct Segment: Sendable {
        public let kind: DiagnosticCPULog.Kind
        public let document: Alias?
        public let page: Int?
        public let start: TimeInterval

        public init(kind: DiagnosticCPULog.Kind, document: Alias?, page: Int?, start: TimeInterval) {
            self.kind = kind; self.document = document; self.page = page; self.start = start
        }
    }

    /// Un jeton par entrée ; retirer une ancienne entrée ne dépile jamais une entrée plus récente.
    public struct Registry {
        private var stacks: [UInt64: [(UUID, Segment)]] = [:]
        public init() {}
        public mutating func push(_ segment: Segment, thread: UInt64) -> UUID {
            let token = UUID()
            stacks[thread, default: []].append((token, segment))
            return token
        }
        public mutating func pop(_ token: UUID, thread: UInt64) {
            guard let index = stacks[thread]?.lastIndex(where: { $0.0 == token }) else { return }
            stacks[thread]?.remove(at: index)
            if stacks[thread]?.isEmpty == true { stacks[thread] = nil }
        }
        public func current(thread: UInt64) -> Segment? { stacks[thread]?.last?.1 }
    }

    public enum Category: String, Sendable {
        case app, lecteur, ocr, ia, scan, analyse, furigana, performances, importation = "import"
        case memoire = "mémoire", affichage, gestes, panneau, bibliotheque, dictionnaire, pages
        case ui, verif, sauvegarde, notes, cartes, diagnostic, journal, lookup, clavier, mecab, export
        case ocrUI = "ocr-ui", ocrScroll = "ocr-scroll", ocrPanel = "ocr-panel", lookupWeb = "lookup-web"
        case autre
    }

    /// Le contenu des messages n'est jamais recopié ; les zones non reconnues sont réduites à « autre ».
    public static func recentCategories(_ lines: [String], before cutoff: Date) -> [Category] {
        let clock = ISO8601DateFormatter()
        clock.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        var latest: [(Date, Category)] = []
        for line in lines.reversed() {
            let fields = line.split(separator: " ", maxSplits: 2)
            guard fields.count == 3, ["[info]", "[alerte]", "[erreur]"].contains(fields[1]),
                  fields[2].first == "[", let end = fields[2].firstIndex(of: "]") else { continue }
            let area = fields[2][fields[2].index(after: fields[2].startIndex)..<end]
            guard area != "cpu", area != "cpu-persistant",
                  let time = clock.date(from: String(fields[0])), time < cutoff else { continue }
            if let index = latest.firstIndex(where: { time > $0.0 }) {
                latest.insert((time, Category(rawValue: String(area)) ?? .autre), at: index)
            } else if latest.count < 3 {
                latest.append((time, Category(rawValue: String(area)) ?? .autre))
            }
            if latest.count > 3 { latest.removeLast() }
        }
        return latest.reversed().map { $0.1 }
    }

    public struct Observation {
        public let load: DiagnosticCPULog.ThreadLoad
        public let age: TimeInterval
        public let average: Double?
        public let events: [Category]?
    }

    /// Les moyennes utilisent les compteurs cumulés, pas le lissage instantané de Mach.
    public struct History {
        private struct Point { let time: TimeInterval; let cpu: TimeInterval }
        private struct ThreadState {
            let first: TimeInterval
            var last: TimeInterval
            var points: [Point] = []
            var hotSince: TimeInterval?
            var firstEvents: [Category]?
            var reported: TimeInterval?

            mutating func average(now: TimeInterval, cpu: TimeInterval) -> Double? {
                let cutoff = now - 10
                while points.count > 1, points[1].time <= cutoff { points.removeFirst() }
                if let last = points.last, now <= last.time || cpu < last.cpu { points.removeAll() }
                points.append(Point(time: now, cpu: cpu))
                guard let oldest = points.first, now > oldest.time else { return nil }
                let start = max(oldest.time, cutoff)
                var base = oldest.cpu
                if start > oldest.time {
                    let next = points[1]
                    base += (next.cpu - base) * (start - oldest.time) / (next.time - oldest.time)
                }
                return 100 * (cpu - base) / (now - start)
            }
        }

        private var states: [UInt64: ThreadState] = [:]
        public init() {}

        /// Appelé même si aucune ligne n'est écrite ; un relevé manqué interrompt la preuve de chauffe continue.
        public mutating func observe(_ loads: [DiagnosticCPULog.ThreadLoad], at now: TimeInterval,
                                     events: () -> [Category]) -> [Observation] {
            var next: [UInt64: ThreadState] = [:]
            var snapshot: [Category]?
            var hot: [Observation] = []
            for load in loads {
                var state = states[load.id] ?? ThreadState(first: now, last: now)
                if now - state.last > 2.5 { state.hotSince = nil; state.points.removeAll() }
                state.last = now
                let average = load.cpuSeconds.flatMap { state.average(now: now, cpu: $0) }
                var report: [Category]?
                if load.percent.isFinite, load.percent >= 80 {
                    if state.hotSince == nil { state.hotSince = now }
                    if state.firstEvents == nil {
                        if snapshot == nil { snapshot = Array(events().suffix(3)) }
                        state.firstEvents = snapshot ?? []
                    }
                    if let since = state.hotSince, now - since > 10,
                       state.reported.map({ now - $0 >= 60 }) ?? true {
                        state.reported = now
                        report = state.firstEvents
                    }
                } else { state.hotSince = nil }
                next[load.id] = state
                if load.percent.isFinite, load.percent >= threshold {
                    hot.append(.init(load: load, age: now - state.first, average: average, events: report))
                }
            }
            states = next
            return hot
        }

        /// Une panne d'énumération ne prouve ni la mort du fil ni une baisse du CPU.
        public mutating func interrupt() {
            for id in states.keys {
                states[id]?.hotSince = nil
                states[id]?.points.removeAll()
            }
        }
    }
}
