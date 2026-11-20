// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

public enum DiagnosticCPULog {
    public enum Kind: String, Sendable {
        case thumbnails, importing, comicImport, comicConversion, backup
        case pageRender, pageText, sharpening, tone, furigana
    }

    public enum Gesture: String, Sendable { case pageTurn, scroll, zoom, ocrResize }
    public enum Panel: String, Sendable { case docked, floating, full, minimized }
    public enum ThreadRole: String, Sendable { case main, sampler, eventFetcher, webThread, javascriptGC }

    public struct Context: Sendable {
        public var tabs: Int?
        public var loaded: Int?
        public var page: Int?
        public var zoom: Double?
        public var gesture: Gesture?
        public var panel: Panel?
        public init() {}
    }

    public struct ThreadLoad: Sendable {
        public let id: UInt64
        public let percent: Double
        public let role: ThreadRole?

        public init(id: UInt64, percent: Double, role: ThreadRole? = nil) {
            self.id = id
            self.percent = percent
            self.role = role
        }
    }

    public struct Work: Sendable {
        public let kind: Kind
        public let seconds: TimeInterval
        public let page: Int?
        public let visiblePage: Int?
        public let cpuSeconds: TimeInterval?

        public init(kind: Kind, seconds: TimeInterval, page: Int? = nil, visiblePage: Int? = nil, cpuSeconds: TimeInterval? = nil) {
            self.kind = kind
            self.seconds = seconds
            self.page = page
            self.visiblePage = visiblePage
            self.cpuSeconds = cpuSeconds
        }
    }

    /// Garde les travaux les plus longs si une rafale dépasserait la taille d'une ligne.
    public struct LongWork: Sendable {
        public private(set) var entries: [Work] = []
        public private(set) var omitted = 0
        public init() {}

        public mutating func add(_ work: Work) {
            guard work.seconds > 0.100 else { return }
            entries.append(work)
            entries.sort { $0.seconds > $1.seconds }
            if entries.count > 8 { entries.removeLast(); omitted += 1 }
        }
    }

    public struct Cost: Sendable {
        public let wall: TimeInterval
        public let cpu: TimeInterval
        public init(wall: TimeInterval, cpu: TimeInterval) { self.wall = wall; self.cpu = cpu }
    }

    public struct Summary: Sendable {
        var samples = 0
        var loads = 0
        var sum = 0.0
        var peak = 0.0
        var wall = 0.0
        var wallMax = 0.0
        var cpu = 0.0

        mutating func add(percent: Double?, cost: Cost) {
            samples += 1
            wall += cost.wall
            wallMax = max(wallMax, cost.wall)
            cpu += cost.cpu
            if let percent { loads += 1; sum += percent; peak = max(peak, percent) }
        }
    }

    public struct Decision: Sendable {
        public let hot: Bool
        public let spike: Bool
        public let summary: Summary?
    }

    /// Un seul décideur pour les pointes, les travaux longs et le résumé : une seule ligne par tick admis.
    public struct Policy: Sendable {
        private var lastTick: TimeInterval?
        private var pendingTick: TimeInterval?
        private var windowStart: TimeInterval?
        private var previous: Double?
        private var summary = Summary()

        public init() {}

        public mutating func resetWindow() {
            pendingTick = nil
            previous = nil
            windowStart = nil
            summary = Summary()
        }

        public mutating func admit(at now: TimeInterval) -> Bool {
            guard lastTick.map({ now - $0 >= 1 }) ?? true else { return false }
            lastTick = now
            pendingTick = now
            if windowStart == nil { windowStart = now }
            return true
        }

        public mutating func decide(at now: TimeInterval, percent: Double?, cost: Cost, hasLongWork: Bool) -> Decision? {
            guard pendingTick == now else { return nil }
            pendingTick = nil
            summary.add(percent: percent, cost: cost)
            let hot = percent.map { $0 > 60 } ?? false
            let spike = percent.flatMap { current in previous.map { current - $0 >= 25 } } ?? false
            previous = percent
            let due = windowStart.map { now - $0 >= 30 } ?? false
            guard hot || spike || due || hasLongWork else { return nil }
            let report = due ? summary : nil
            if due { summary = Summary(); windowStart = now }
            return Decision(hot: hot, spike: spike, summary: report)
        }
    }

    public static func topThreads(_ threads: [ThreadLoad]) -> [ThreadLoad] {
        Array(threads.filter { $0.percent.isFinite && $0.percent > 0 }.sorted {
            $0.percent == $1.percent ? $0.id < $1.id : $0.percent > $1.percent
        }.prefix(3))
    }

    private static func number(_ value: Double?, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "?" }
        return String(format: "%.*f", digits, value)
    }

    private static func workLabel(_ work: Work) -> String {
        var label = "\(work.kind.rawValue):\(number(work.seconds * 1000))ms"
        if let page = work.page { label += "@p\(page)" }
        else if let page = work.visiblePage { label += "@visible:\(page)" }
        else { label += "@p?" }
        if let cpu = work.cpuSeconds { label += "/cpu:\(number(cpu * 1000))ms" }
        return label
    }

    /// N'accepte aucun texte libre (ni titres, ni détails d'activité, ni noms de fil arbitraires).
    public static func line(percent: Double?, threads: [ThreadLoad], active: [Work], context: Context,
                            long: LongWork, cost: Cost, decision: Decision) -> String {
        let top = topThreads(threads).map {
            let id = String(String($0.id, radix: 16).suffix(8))
            return "\($0.role?.rawValue ?? "fil")#\(id):\(number($0.percent))%"
        }
        let running = active.prefix(8).map(workLabel).joined(separator: ",")
        let completed = long.entries.map(workLabel).joined(separator: ",")
        var line = "total=\(number(percent))% fils=[\(top.joined(separator: ","))] actifs=[\(running)] actifs_omis=\(max(0, active.count - 8))"
        line += " onglets=\(context.tabs.map(String.init) ?? "?") chargés=\(context.loaded.map(String.init) ?? "?")"
        line += " page=\(context.page.map(String.init) ?? "?") zoom=\(number(context.zoom, digits: 2))"
        line += " geste=\(context.gesture?.rawValue ?? "?") ocr=\(context.panel?.rawValue ?? "?")"
        line += " longs=[\(completed)] longs_omis=\(long.omitted) seuil=\(decision.hot) pic=\(decision.spike)"
        line += " sonde_ms=\(number(cost.wall * 1000, digits: 3)) sonde_cpu_ms=\(number(cost.cpu * 1000, digits: 3))"
        if let s = decision.summary {
            let mean = s.loads == 0 ? nil : s.sum / Double(s.loads)
            line += " résumé n=\(s.samples) total_moy=\(number(mean))% total_max=\(number(s.loads == 0 ? nil : s.peak))%"
            line += " sonde_moy_ms=\(number(s.wall * 1000 / Double(s.samples), digits: 3))"
            line += " sonde_max_ms=\(number(s.wallMax * 1000, digits: 3)) sonde_cpu_moy_ms=\(number(s.cpu * 1000 / Double(s.samples), digits: 3))"
        }
        return line
    }
}
