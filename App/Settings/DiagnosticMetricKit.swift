// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DiagnosticKit
import Foundation
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(MetricKit)
import MetricKit
#endif

/// Essai facultatif de MetricKit (PLAN-DIAG-001, E2f, DEC-04 A) : éteint par défaut, iPad seulement. iOS peut ne
/// rien livrer (installation TrollStore, fenêtre de 24 h) : le silence ne prouve rien. Seulement des comptes au
/// journal ; jamais de JSON brut, de pile, d'envoi ni de rattachement à une session.
enum DiagnosticMetricKit {
    static let enabledKey = "diagnostics.metricKit"

    /// Applique le réglage (au lancement et à chaque changement). Fil principal.
    static func apply() {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(MetricKit)
        Subscriber.shared.set(UserDefaults.standard.bool(forKey: enabledKey))
        #endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(MetricKit)
private final class Subscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = Subscriber()
    private let lock = NSLock()
    private var gate = DiagnosticSubscriptionGate()

    /// Abonnement et désabonnement idempotents ; la génération rejette un rappel tardif.
    func set(_ on: Bool) {
        let changed: Bool = lock.withLock { on ? gate.enable() != nil : gate.disable() }
        guard changed else { return }
        if on { MXMetricManager.shared.add(self) } else { MXMetricManager.shared.remove(self) }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let event = DiagnosticMetricSummary.subscription(on: on, systemMajor: version.majorVersion, systemMinor: version.minorVersion)
        DiagnosticCenter.shared.emit(event.level, event)
    }

    private var accepting: Bool { lock.withLock { gate.accepts(gate.generation) } }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard accepting else { return }
        let exits = payloads.compactMap { $0.applicationExitMetrics?.foregroundExitData }
        let memory = exits.isEmpty ? nil : exits.reduce(0) { $0 + $1.cumulativeMemoryResourceLimitExitCount }
        let watchdog = exits.isEmpty ? nil : exits.reduce(0) { $0 + $1.cumulativeAppWatchdogExitCount }
        let event = DiagnosticMetricSummary.metrics(payloads: payloads.count, memoryLimitExits: memory, watchdogExits: watchdog)
        DiagnosticCenter.shared.emit(event.level, event)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard accepting else { return }
        let crashes = payloads.compactMap { $0.crashDiagnostics?.count }
        let hangs = payloads.compactMap { $0.hangDiagnostics?.count }
        let event = DiagnosticMetricSummary.diagnostics(payloads: payloads.count,
                                                        crashes: crashes.isEmpty ? nil : crashes.reduce(0, +),
                                                        hangs: hangs.isEmpty ? nil : hangs.reduce(0, +))
        DiagnosticCenter.shared.emit(event.level, event)
    }
}
#endif
