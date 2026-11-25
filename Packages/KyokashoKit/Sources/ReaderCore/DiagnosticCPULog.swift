// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

public enum DiagnosticCPULog {
    public static let activeLimit = 8

    public enum Kind: String, Sendable {
        case thumbnails, importing, comicImport, comicConversion, backup
        case pageRender, pageText, sharpening, tone, furigana
        case ocr, analysis, aiReading
        case readerBuild, autoCrop, pdfProbe, ocrEngine, ocrRender, ocrNormalize, vision
        case onnxSession, onnxRun, ovisRender, neuralLayout, readerClose, pdfRelease
        case aiPrepare, aiGenerate
    }

    public enum Stage: String, Sendable {
        case waiting, pdfText, ocr, aiReading, voting, translation, corrections, saving
    }

    /// Index source (base zéro), nombre de pages du document et étape issue d'une liste fermée.
    public struct Progress: Sendable {
        public let page: Int?
        public let total: Int?
        public let stage: Stage?

        public init(page: Int? = nil, total: Int? = nil, stage: Stage? = nil) {
            let validTotal = total.flatMap { $0 > 0 ? $0 : nil }
            self.total = validTotal
            self.page = page.flatMap { index in
                index >= 0 && (validTotal.map { index < $0 } ?? true) ? index : nil
            }
            self.stage = stage
        }
    }

    /// Additionne les segments synchrones ; un segment imbriqué sur le même fil est déjà compté.
    public struct CPUTime: Sendable {
        private var running: [UInt32: TimeInterval] = [:]
        private var accumulated: TimeInterval?

        public init() {}

        public mutating func begin(thread: UInt32, at start: TimeInterval) -> Bool {
            guard running[thread] == nil else { return false }
            running[thread] = start
            return true
        }

        public mutating func end(thread: UInt32, at end: TimeInterval?) {
            guard let start = running.removeValue(forKey: thread), let elapsed = Self.delta(start, end) else { return }
            accumulated = (accumulated ?? 0) + elapsed
        }

        public func seconds(read: (UInt32) -> TimeInterval?) -> TimeInterval? {
            running.reduce(accumulated) { sum, segment in
                guard let elapsed = Self.delta(segment.value, read(segment.key)) else { return sum }
                return (sum ?? 0) + elapsed
            }
        }

        private static func delta(_ start: TimeInterval, _ end: TimeInterval?) -> TimeInterval? {
            guard let end, start.isFinite, end.isFinite, end >= start else { return nil }
            return end - start
        }
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
        public let name: String?
        public let queue: String?
        public let cpuSeconds: TimeInterval?

        public init(id: UInt64, percent: Double, role: ThreadRole? = nil, name: String? = nil,
                    queue: String? = nil, cpuSeconds: TimeInterval? = nil) {
            self.id = id
            self.percent = percent
            self.role = role
            self.name = DiagnosticThreads.safeName(name)
            self.queue = DiagnosticThreads.safeName(queue)
            self.cpuSeconds = cpuSeconds
        }
    }

    public struct Work: Sendable {
        public let kind: Kind
        public let seconds: TimeInterval
        public let document: DiagnosticThreads.Alias?
        public let page: Int?
        public let visiblePage: Int?
        public let cpuSeconds: TimeInterval?
        public let progress: Progress?

        public init(kind: Kind, seconds: TimeInterval, document: DiagnosticThreads.Alias? = nil,
                    page: Int? = nil, visiblePage: Int? = nil,
                    cpuSeconds: TimeInterval? = nil, progress: Progress? = nil) {
            self.kind = kind
            self.seconds = seconds
            self.document = document
            self.page = page
            self.visiblePage = visiblePage
            self.cpuSeconds = cpuSeconds
            self.progress = progress
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
        Array(DiagnosticThreads.hot(threads).prefix(DiagnosticThreads.limit))
    }

    private static func number(_ value: Double?, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "?" }
        return String(format: "%.*f", digits, value)
    }

    private static func workLabel(_ work: Work) -> String {
        var label = "\(work.kind.rawValue):\(number(work.seconds * 1000))ms"
        if let page = work.progress?.page ?? work.page { label += "@p\(page)" }
        else if let page = work.visiblePage { label += "@visible:\(page)" }
        else { label += "@p?" }
        label += "/total:\(work.progress?.total.map(String.init) ?? "?")/étape:\(work.progress?.stage?.rawValue ?? "?")"
        if let cpu = work.cpuSeconds { label += "/cpu:\(number(cpu * 1000))ms" }
        else { label += "/cpu:?" }
        if let document = work.document { label += "/doc:\(document.label)" }
        return label
    }

    private static func threadLabel(_ load: ThreadLoad, segment: DiagnosticThreads.Segment?, at now: TimeInterval) -> String {
        // Étiquettes fermées au rendu, pour les deux lignes (relevé et fil persistant).
        let name = DiagnosticThreads.closedLabel(load.name) ?? "sans-nom"
        let queue = DiagnosticThreads.closedLabel(load.queue) ?? "?"
        let runtime = [load.name, load.queue].compactMap { $0 }.contains { $0.hasSuffix(".cooperative") }
            ? "/runtime:swift-probable" : ""
        var label = "\(load.role?.rawValue ?? "fil")#\(String(load.id, radix: 16)):\(number(load.percent))%/nom:\(name)/file:\(queue)\(runtime)"
        label += "/fonction:\(segment?.kind.rawValue ?? "inconnue")"
        if let segment {
            label += "/doc:\(segment.document?.label ?? "?")/page:\(segment.page.map(String.init) ?? "?")/segment_s:\(number(max(0, now - segment.start)))"
        }
        return label
    }

    public static func persistentLine(_ thread: DiagnosticThreads.Observation, segment: DiagnosticThreads.Segment?,
                                      at now: TimeInterval) -> String {
        let events = (thread.events ?? []).map(\.rawValue).joined(separator: ",")
        return "\(threadLabel(thread.load, segment: segment, at: now))/âge_s:\(number(thread.age)) événements=[\(events)]"
    }

    /// N'accepte aucun titre, chemin ou détail libre ; les noms de fil et de file sont filtrés à la construction.
    public static func line(percent: Double?, threads: [ThreadLoad], active: [Work], context: Context,
                            long: LongWork, cost: Cost, decision: Decision,
                            observations: [DiagnosticThreads.Observation] = [],
                            segments: [UInt64: DiagnosticThreads.Segment] = [:], at now: TimeInterval = 0,
                            previousTick: Cost? = nil) -> String {
        let hot = DiagnosticThreads.hot(threads)
        let byID = Dictionary(observations.map { ($0.load.id, $0) }, uniquingKeysWith: { first, _ in first })
        let top = hot.prefix(DiagnosticThreads.limit).map {
            let observation = byID[$0.id]
            return threadLabel($0, segment: segments[$0.id], at: now)
                + "/âge_s:\(number(observation?.age))/moy10s:\(number(observation?.average))%"
        }
        let running = active.prefix(activeLimit).map(workLabel).joined(separator: ",")
        let completed = long.entries.map(workLabel).joined(separator: ",")
        var line = "total=\(number(percent))% fils=[\(top.joined(separator: ","))] fils_omis=\(max(0, hot.count - DiagnosticThreads.limit)) actifs=[\(running)] actifs_omis=\(max(0, active.count - activeLimit))"
        line += " onglets=\(context.tabs.map(String.init) ?? "?") chargés=\(context.loaded.map(String.init) ?? "?")"
        line += " page=\(context.page.map(String.init) ?? "?") zoom=\(number(context.zoom, digits: 2))"
        line += " geste=\(context.gesture?.rawValue ?? "?") ocr=\(context.panel?.rawValue ?? "?")"
        line += " longs=[\(completed)] longs_omis=\(long.omitted) seuil=\(decision.hot) pic=\(decision.spike)"
        line += " sonde_ms=\(number(cost.wall * 1000, digits: 3)) sonde_cpu_ms=\(number(cost.cpu * 1000, digits: 3))"
        line += " tick_préc_ms=\(number(previousTick.map { $0.wall * 1000 }, digits: 3))"
        line += " tick_préc_cpu_ms=\(number(previousTick.map { $0.cpu * 1000 }, digits: 3))"
        if let s = decision.summary {
            let mean = s.loads == 0 ? nil : s.sum / Double(s.loads)
            line += " résumé n=\(s.samples) total_moy=\(number(mean))% total_max=\(number(s.loads == 0 ? nil : s.peak))%"
            line += " sonde_moy_ms=\(number(s.wall * 1000 / Double(s.samples), digits: 3))"
            line += " sonde_max_ms=\(number(s.wallMax * 1000, digits: 3)) sonde_cpu_moy_ms=\(number(s.cpu * 1000 / Double(s.samples), digits: 3))"
        }
        return line
    }
}
