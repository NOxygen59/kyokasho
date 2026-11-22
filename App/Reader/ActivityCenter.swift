// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Darwin
import Foundation
import ReaderCore

/// Registre partagé, appelé depuis n'importe quel fil. Le diagnostic ne consomme pas les compteurs de l'accueil.
final class ActivityCenter: @unchecked Sendable {
    static let shared = ActivityCenter()
    private let lock = NSLock()
    private var ledger = ActivityLedger()

    typealias Kind = DiagnosticCPULog.Kind
    typealias Progress = DiagnosticCPULog.Progress
    private struct Observed {
        let kind: Kind
        let start: TimeInterval
        let page: Int?
        let visiblePage: Int?
        var progress: Progress?
        var cpu = DiagnosticCPULog.CPUTime()

        func work(at now: TimeInterval, readCPU: Bool = true) -> DiagnosticCPULog.Work {
            .init(kind: kind, seconds: now - start, page: page, visiblePage: visiblePage,
                  cpuSeconds: readCPU ? cpu.seconds(read: DiagnosticMachCPU.threadCPUSeconds) : nil, progress: progress)
        }
    }
    private var diagnosticRunning: [UUID: Observed] = [:]
    private var diagnosticLong = DiagnosticCPULog.LongWork()
    private var diagnosticThreads = DiagnosticThreads.Registry()
    private var aliases: [String: DiagnosticThreads.Alias] = [:]
    /// Copie en mémoire du mode diagnostic (revue R2 D) : les chemins fréquents ne relisent pas les préférences.
    private var diagnosticsOn = false

    func setDiagnostics(_ on: Bool) {
        lock.withLock {
            diagnosticsOn = on
            if !on { diagnosticRunning.removeAll(); diagnosticLong = .init(); diagnosticThreads = .init() }
        }
        let hook: DiagnosticThreadHook.Begin = { [self] kind, documentID, page in
            self.beginSynchronous(kind, documentID: documentID, page: page)
        }
        DiagnosticThreadHook.install(on ? hook : nil)
    }

    /// `end` part avec le `defer` de l'appelant : une erreur ou une annulation ferment aussi la mesure.
    func begin(_ kind: Kind, detail: String? = nil, page: Int? = nil, progress: Progress? = nil) -> UUID {
        let id = UUID()
        lock.withLock {
            ledger.begin(id, kind: kind.rawValue, detail: detail, at: Date())
            if diagnosticsOn { register(id, kind: kind, page: page, progress: progress) }
        }
        return id
    }

    /// Pour une tâche asynchrone qui a déjà son propre suivi UI. Ne chronomètre pas les `await` comme du CPU.
    func beginDiagnostic(_ kind: Kind, progress: Progress? = nil) -> UUID? {
        lock.withLock {
            guard diagnosticsOn else { return nil }
            let id = UUID()
            register(id, kind: kind, page: nil, progress: progress, inferVisiblePage: false)
            return id
        }
    }

    func updateDiagnostic(_ id: UUID?, progress: Progress) {
        guard let id else { return }
        lock.withLock { if diagnosticsOn { diagnosticRunning[id]?.progress = progress } }
    }

    func endDiagnostic(_ id: UUID?) {
        guard let id else { return }
        lock.withLock { if diagnosticsOn { finishDiagnostic(id) } }
    }

    // Le registre, la progression et les segments sont lus et modifiés sous le même verrou.
    private func register(_ id: UUID, kind: Kind, page: Int?, progress: Progress?, inferVisiblePage: Bool = true) {
        diagnosticRunning[id] = Observed(kind: kind, start: ProcessInfo.processInfo.systemUptime, page: page,
                                         visiblePage: page == nil && inferVisiblePage ? DiagnosticCPU.shared.visiblePage : nil,
                                         progress: progress)
    }

    private func finishDiagnostic(_ id: UUID) {
        guard let observed = diagnosticRunning.removeValue(forKey: id) else { return }
        diagnosticLong.add(observed.work(at: ProcessInfo.processInfo.systemUptime))
    }

    func end(_ id: UUID) {
        lock.withLock {
            if diagnosticsOn { diagnosticRunning.removeValue(forKey: id) }
            ledger.end(id, at: Date())
        }
    }

    /// Travail synchrone dont le vrai temps processeur est mesuré. À garder hors de tout `await` : la mesure suit un seul fil.
    func measure<Result>(_ kind: Kind, detail: String? = nil, page: Int? = nil, progress: Progress? = nil,
                         _ work: () throws -> Result) rethrows -> Result {
        let id = UUID()
        let segment: Segment? = lock.withLock {
            ledger.begin(id, kind: kind.rawValue, detail: detail, at: Date())
            guard diagnosticsOn else { return nil }
            register(id, kind: kind, page: page, progress: progress)
            return startSegment(id)
        }
        let start = segment?.start ?? ThreadCPU.seconds()
        defer {
            let untrackedEnd = segment == nil ? ThreadCPU.seconds() : nil
            lock.withLock {
                let end = segment.flatMap { endSegment(id, $0, forLedger: true) } ?? untrackedEnd
                ledger.addCPU(kind: kind.rawValue, seconds: (end ?? start) - start)
                ledger.end(id, at: Date())
                if diagnosticsOn { finishDiagnostic(id) }
            }
        }
        return try work()
    }

    /// Ajoute un segment synchrone à une activité déjà ouverte, sans créer une deuxième activité.
    func measure<Result>(activity id: UUID?, _ work: () throws -> Result) rethrows -> Result {
        guard let id, let segment = lock.withLock({ startSegment(id) }) else { return try work() }
        defer { lock.withLock { _ = endSegment(id, segment) } }
        return try work()
    }

    /// Les nouveaux segments n'ajoutent rien au moniteur UI quand le diagnostic est coupé.
    func measureDiagnostic<Result>(_ kind: Kind, documentID: String? = nil, page: Int? = nil,
                                   _ work: () throws -> Result) rethrows -> Result {
        let end = beginSynchronous(kind, documentID: documentID, page: page)
        defer { end?() }
        return try work()
    }

    private func beginSynchronous(_ kind: Kind, documentID: String?, page: Int?) -> (() -> Void)? {
        lock.withLock {
            guard diagnosticsOn else { return nil }
            let id = UUID()
            register(id, kind: kind, page: page, progress: nil, inferVisiblePage: false)
            let segment = startSegment(id, documentID: documentID)
            return { [self] in
                lock.withLock {
                    if let segment { _ = endSegment(id, segment) }
                    if diagnosticsOn { finishDiagnostic(id) }
                }
            }
        }
    }

    private struct Segment {
        let port: thread_t
        let start: TimeInterval
        let ownsCounter: Bool
        let thread: UInt64
        let token: UUID?
        let restoreName: (() -> Void)?
    }

    private func startSegment(_ id: UUID, documentID: String? = nil) -> Segment? {
        guard diagnosticsOn, let observed = diagnosticRunning[id] else { return nil }
        // Le droit reste vivant jusqu'au defer du segment, même si le diagnostic est désactivé entre-temps.
        let port = mach_thread_self()
        if let start = DiagnosticMachCPU.threadCPUSeconds(port) {
            // Le compteur logique peut déjà couvrir ce fil ; la pile suit tout de même le segment le plus précis.
            let ownsCounter = diagnosticRunning[id]?.cpu.begin(thread: port, at: start) == true
            var thread: UInt64 = 0
            var token: UUID?
            if pthread_threadid_np(nil, &thread) == 0 {
                let parent = diagnosticThreads.current(thread: thread)
                let alias = documentID.map { key in
                    if let alias = aliases[key] { return alias }
                    let alias = DiagnosticThreads.Alias()
                    aliases[key] = alias
                    return alias
                } ?? parent?.document
                let page = observed.progress?.page ?? observed.page ?? (documentID == nil ? parent?.page : nil)
                token = diagnosticThreads.push(.init(kind: observed.kind, document: alias, page: page,
                                                     start: ProcessInfo.processInfo.systemUptime), thread: thread)
            }
            return Segment(port: port, start: start, ownsCounter: ownsCounter, thread: thread, token: token,
                           restoreName: DiagnosticThreadHook.restoreNameAfterSetting(observed.kind))
        }
        mach_port_deallocate(mach_task_self_, port)
        return nil
    }

    private func endSegment(_ id: UUID, _ segment: Segment, forLedger: Bool = false) -> TimeInterval? {
        defer { mach_port_deallocate(mach_task_self_, segment.port) }
        segment.restoreName?()
        if let token = segment.token { diagnosticThreads.pop(token, thread: segment.thread) }
        guard segment.ownsCounter else { return nil }
        guard forLedger || (diagnosticsOn && diagnosticRunning[id] != nil) else { return nil }
        let end = DiagnosticMachCPU.threadCPUSeconds(segment.port)
        if diagnosticsOn { diagnosticRunning[id]?.cpu.end(thread: segment.port, at: end) }
        return end
    }

    func snapshot() -> [ActivityLedger.Row] { lock.withLock { ledger.snapshot(at: Date()) } }

    func diagnosticSegments(for threads: [UInt64], at time: TimeInterval) -> [UInt64: DiagnosticThreads.Segment] {
        lock.withLock {
            var result: [UInt64: DiagnosticThreads.Segment] = [:]
            for thread in threads {
                if let segment = diagnosticThreads.current(thread: thread), segment.start <= time { result[thread] = segment }
            }
            return result
        }
    }

    /// Ne consomme pas le relevé de l'accueil et ne reprend jamais ses libellés libres.
    func diagnosticActive() -> [DiagnosticCPULog.Work] {
        lock.withLock {
            guard diagnosticsOn else { return [] }
            let now = ProcessInfo.processInfo.systemUptime
            return diagnosticRunning.values.sorted { $0.start < $1.start }.enumerated().map { index, observed in
                // Pas de lecture Mach pour les entrées que la ligne omettra.
                observed.work(at: now, readCPU: index < DiagnosticCPULog.activeLimit)
            }
        }
    }

    func takeDiagnosticLongWork() -> DiagnosticCPULog.LongWork {
        lock.withLock {
            let batch = diagnosticLong
            diagnosticLong = .init()
            return batch
        }
    }

    func clearDiagnostic() {
        lock.withLock { diagnosticRunning.removeAll(); diagnosticLong = .init(); diagnosticThreads = .init() }
    }
}

extension DiagnosticCPULog.Kind {
    var title: String {
        switch self {
        case .thumbnails: return String(localized: "Miniatures")
        case .importing: return String(localized: "Import de documents")
        case .comicImport: return String(localized: "Import de CBZ")
        case .comicConversion: return String(localized: "Conversion de CBZ en PDF")
        case .backup: return String(localized: "Sauvegarde")
        case .pageRender: return String(localized: "Dessin des pages")
        case .pageText: return String(localized: "Texte des pages")
        case .sharpening: return String(localized: "Nettoyage des scans")
        case .tone: return String(localized: "Teinte des pages")
        case .furigana: return String(localized: "Furigana")
        case .ocr: return String(localized: "OCR")
        case .analysis: return String(localized: "Analyse du document")
        case .aiReading: return String(localized: "Lecture OCR")
        // Ces cas sont réservés au journal, jamais ajoutés au registre UI.
        case .readerBuild, .autoCrop, .pdfProbe, .ocrEngine, .ocrRender, .ocrNormalize, .vision,
             .onnxSession, .onnxRun, .ovisRender, .neuralLayout, .readerClose, .pdfRelease: return rawValue
        }
    }
}
