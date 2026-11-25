// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DiagnosticKit
import ReaderCore
import UIKit

/// La lecture d'UIKit reste sur le fil principal, sans y attendre pour échantillonner Mach.
@MainActor
enum DiagnosticContext {
    private final class WeakReader {
        weak var reader: ReaderController?
        init(_ reader: ReaderController) { self.reader = reader }
    }

    private static weak var model: AppModel?
    private static var readers: [ObjectIdentifier: WeakReader] = [:]
    private static var gesture: (document: String, value: DiagnosticCPULog.Gesture, time: TimeInterval)?
    private static var panel: (document: String, value: DiagnosticCPULog.Panel?)?

    static func attach(_ model: AppModel) { self.model = model }

    static func observe(_ reader: ReaderController) {
        guard Diagnostics.enabled else { return }
        let key = ObjectIdentifier(reader)
        if readers[key]?.reader == nil {
            readers = readers.filter { $0.value.reader != nil }
            readers[key] = WeakReader(reader)
        }
    }

    static func note(_ value: DiagnosticCPULog.Gesture, from reader: ReaderController) {
        guard Diagnostics.enabled, reader.document.id == reader.model.openDocumentId else { return }
        gesture = (reader.document.id, value, ProcessInfo.processInfo.systemUptime)
        refresh()
    }

    static func inferPageGesture(_ value: DiagnosticCPULog.Gesture, from reader: ReaderController) {
        if let gesture, gesture.document == reader.document.id, ProcessInfo.processInfo.systemUptime - gesture.time < 1 {
            // Une action explicite récente prime sur la notification PDFKit qu'elle peut déclencher.
            return
        }
        note(value, from: reader)
    }

    static func noteOCRResize() {
        guard Diagnostics.enabled, let id = model?.openDocumentId else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let gesture, gesture.document == id, gesture.value == .ocrResize, now - gesture.time < 0.25 { return }
        gesture = (id, .ocrResize, now)
        refresh()
    }

    static func setOCRMode(_ value: StudyPanelMode?, from reader: ReaderController) {
        guard Diagnostics.enabled, reader.document.id == reader.model.openDocumentId else { return }
        panel = (reader.document.id, value.flatMap { DiagnosticCPULog.Panel(rawValue: $0.rawValue) })
        refresh()
    }

    static func refresh() {
        guard Diagnostics.enabled else { return }
        let open = model?.openDocumentId
        if gesture?.document != open { gesture = nil }
        // Revue R2 D : un geste de plus de 5 s n'explique plus un pic.
        if let gesture, ProcessInfo.processInfo.systemUptime - gesture.time > 5 { self.gesture = nil }
        if panel?.document != open { panel = nil }
        var context = DiagnosticCPULog.Context()
        context.tabs = model?.tabs.ids.count
        readers = readers.filter { $0.value.reader != nil }
        let loaded = readers.values.compactMap(\.reader).filter { $0.pdf != nil && !$0.closed }
        context.loaded = model == nil ? nil : Set(loaded.map { $0.document.id }).count
        if let current = loaded.first(where: { $0.document.id == open }) {
            context.page = current.currentSourcePage
            context.zoom = Double(current.pdfView.scaleFactor)
        }
        context.gesture = gesture?.value
        context.panel = panel?.value
        DiagnosticCPU.shared.store(context, gestureTime: gesture?.time)
    }

    static func resetActions() { gesture = nil; panel = nil }
}

/// Un seul minuteur et une seule décision d'écriture, indépendants du fil principal.
final class DiagnosticCPU: @unchecked Sendable {
    static let shared = DiagnosticCPU()
    private static let queueLabel = "fr.noxygen59.kyokasho.diagnostics.cpu"
    private let queue = DispatchQueue(label: DiagnosticCPU.queueLabel, qos: .utility)
    private let contextLock = NSLock()
    private let refreshSlot = DispatchSemaphore(value: 1)
    private var context = DiagnosticCPULog.Context()
    /// Heure du geste du contexte : son âge est revérifié à l'écriture (revue R2 D, second passage).
    private var gestureTime: TimeInterval?
    // État confiné à `queue`, sauf le contexte protégé par son verrou.
    private var timer: DispatchSourceTimer?
    private var sampler = DiagnosticMachCPU()
    private var policy = DiagnosticCPULog.Policy()
    private var threadHistory = DiagnosticThreads.History()
    private var previousTick: DiagnosticCPULog.Cost?

    @MainActor private static var lifecycleInstalled = false

    @MainActor static func updateActivation() {
        let enabled = Diagnostics.enabled
        guard enabled || lifecycleInstalled else { return }
        if enabled, !lifecycleInstalled {
            lifecycleInstalled = true
            let center = NotificationCenter.default
            _ = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                shared.configure(running: false, mainID: 0)
            }
            _ = center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { updateActivation() }
            }
        }
        ActivityCenter.shared.setDiagnostics(enabled)
        if !enabled {
            DiagnosticContext.resetActions()
            ActivityCenter.shared.clearDiagnostic()
        } else {
            DiagnosticContext.refresh()
        }
        var mainID: UInt64 = 0
        if enabled { pthread_threadid_np(nil, &mainID) }
        shared.configure(running: enabled && UIApplication.shared.applicationState != .background, mainID: mainID)
    }

    func store(_ value: DiagnosticCPULog.Context, gestureTime: TimeInterval?) {
        contextLock.withLock { context = value; self.gestureTime = gestureTime }
    }
    var visiblePage: Int? { contextLock.withLock { context.page } }

    private func configure(running: Bool, mainID: UInt64) {
        queue.async {
            if running, Diagnostics.enabled {
                guard self.timer == nil else { return }
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now())
                timer.setEventHandler {
                    self.tick(mainID: mainID)
                    self.timer?.schedule(deadline: .now() + .seconds(1), leeway: .milliseconds(50))
                }
                self.timer = timer
                timer.resume()
            } else {
                self.timer?.cancel()
                self.timer = nil
                self.sampler = DiagnosticMachCPU()
                self.threadHistory.interrupt()
                self.previousTick = nil
                self.policy.resetWindow()
            }
        }
    }

    private func tick(mainID: UInt64) {
        guard Diagnostics.enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard policy.admit(at: now) else { return }
        let cpuStart = ThreadCPU.seconds()
        defer {
            previousTick = .init(wall: ProcessInfo.processInfo.systemUptime - now,
                                 cpu: max(0, ThreadCPU.seconds() - cpuStart))
        }
        // Pas de pile de rafraîchissements si le dessin bloque le fil principal.
        if refreshSlot.wait(timeout: .now()) == .success {
            DispatchQueue.main.async {
                defer { self.refreshSlot.signal() }
                DiagnosticContext.refresh()
            }
        }
        let cutoff = Date()
        let sample = sampler.sample(mainID: mainID, samplerQueue: Self.queueLabel)
        let sampledAt = ProcessInfo.processInfo.systemUptime
        let center = ActivityCenter.shared
        let long = center.takeDiagnosticLongWork()
        let observations: [DiagnosticThreads.Observation]
        if sample.complete {
            observations = threadHistory.observe(sample.threads, at: now) {
                DiagnosticThreads.recentCategories(Diagnostics.tail().lines, before: cutoff)
            }
        } else {
            threadHistory.interrupt()
            observations = []
        }
        // Une opération par relevé : les lignes des fils persistants et la ligne du relevé la partagent (AV-03).
        let op = DiagnosticOperation.new()
        let persistent = observations.filter { $0.events != nil }
        let shown = DiagnosticCPULog.topThreads(sample.threads).map(\.id)
        let segments = center.diagnosticSegments(for: shown + persistent.map { $0.load.id }, at: sampledAt)
        for thread in persistent {
            Diagnostics.logCPU(DiagnosticCPULog.persistentLine(thread, segment: segments[thread.load.id], at: sampledAt),
                               op: op, step: "fil_persistant", zone: .cpuPersistant)
        }
        guard let decision = policy.decide(at: now, percent: sample.percent, cost: sample.cost,
                                           hasLongWork: !long.entries.isEmpty) else { return }
        // Contexte et heure du geste lus ensemble ; âge revérifié à l'heure de l'écriture : un geste de plus de 5 s
        // n'explique plus ce pic, même si le fil principal a tardé à rafraîchir le contexte.
        let (stored, gestureTime) = contextLock.withLock { (context, self.gestureTime) }
        var current = stored
        if current.gesture != nil, ProcessInfo.processInfo.systemUptime - (gestureTime ?? 0) > 5 { current.gesture = nil }
        let line = DiagnosticCPULog.line(percent: sample.percent, threads: sample.threads, active: center.diagnosticActive(),
                                         context: current, long: long, cost: sample.cost, decision: decision,
                                         observations: observations, segments: segments, at: sampledAt, previousTick: previousTick)
        Diagnostics.logCPU(line, op: op, step: "releve_cpu")
    }
}
