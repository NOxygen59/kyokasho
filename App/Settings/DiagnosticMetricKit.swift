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
        MetricKitTrial.shared.set(UserDefaults.standard.bool(forKey: enabledKey))
        #endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(MetricKit)
/// Un abonné **neuf** par activation, avec son jeton de génération : un rappel d'un ancien abonné, ou arrivé après
/// la coupure, est rejeté ; la vérification et la publication se font sous le même verrou que la coupure (revue E2f).
private final class MetricKitTrial {
    static let shared = MetricKitTrial()
    private let lock = NSLock()
    private var gate = DiagnosticSubscriptionGate()
    private var subscriber: Subscriber?

    func set(_ on: Bool) {
        let change: (add: Subscriber?, remove: Subscriber?)? = lock.withLock {
            if on {
                guard let token = gate.enable() else { return nil }
                let new = Subscriber(token: token, owner: self)
                subscriber = new
                return (new, nil)
            }
            guard gate.disable() else { return nil }
            defer { subscriber = nil }
            return (nil, subscriber)
        }
        guard let change else { return }
        if let add = change.add { MXMetricManager.shared.add(add) }
        if let remove = change.remove { MXMetricManager.shared.remove(remove) }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let event = DiagnosticMetricSummary.subscription(on: on, systemMajor: version.majorVersion, systemMinor: version.minorVersion)
        DiagnosticCenter.shared.emit(event.level, event)
    }

    /// Publie seulement si le jeton est celui de l'abonnement actif, sans lâcher le verrou entre les deux.
    func publish(_ event: DiagnosticEvent, token: UInt64) {
        lock.withLock {
            guard gate.accepts(token) else { return }
            DiagnosticCenter.shared.emit(event.level, event)
        }
    }
}

private final class Subscriber: NSObject, MXMetricManagerSubscriber {
    let token: UInt64
    weak var owner: MetricKitTrial?

    init(token: UInt64, owner: MetricKitTrial) {
        self.token = token
        self.owner = owner
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        let exits = payloads.compactMap { $0.applicationExitMetrics }
        let fg = exits.map(\.foregroundExitData), bg = exits.map(\.backgroundExitData)
        func sum<T>(_ items: [T], _ value: (T) -> Int) -> Int? { items.isEmpty ? nil : items.reduce(0) { $0 + value($1) } }
        let event = DiagnosticMetricSummary.metrics(
            payloads: payloads.count,
            foreground: .init(memoryLimit: sum(fg) { $0.cumulativeMemoryResourceLimitExitCount }, watchdog: sum(fg) { $0.cumulativeAppWatchdogExitCount }),
            background: .init(memoryLimit: sum(bg) { $0.cumulativeMemoryResourceLimitExitCount }, watchdog: sum(bg) { $0.cumulativeAppWatchdogExitCount }))
        owner?.publish(event, token: token)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes = payloads.compactMap { $0.crashDiagnostics?.count }
        let hangs = payloads.compactMap { $0.hangDiagnostics?.count }
        let event = DiagnosticMetricSummary.diagnostics(payloads: payloads.count,
                                                        crashes: crashes.isEmpty ? nil : crashes.reduce(0, +),
                                                        hangs: hangs.isEmpty ? nil : hangs.reduce(0, +))
        owner?.publish(event, token: token)
    }
}
#endif
