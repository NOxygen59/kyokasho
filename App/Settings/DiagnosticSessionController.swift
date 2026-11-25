// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DiagnosticKit
import Foundation
import UIKit

/// Session du processus (PLAN-DIAG-001, E2a) : propriétaire **unique**, branché sur les notifications de
/// l'application (jamais sur la phase d'une vue ou d'une scène). Armée au premier plan, close au vrai arrière-plan ;
/// `willResignActive` (Centre de contrôle, Split View, sélecteur) ne change rien. Au lancement suivant, une session
/// restée armée donne une seule alerte « session précédente non clôturée » : jamais « plantage » ni cause.
///
/// Tout l'état vit sur une file série : la consommation du lancement passe avant toute transition.
final class DiagnosticSessionController: @unchecked Sendable {
    static let shared = DiagnosticSessionController()

    /// Hors de `Documents` (invisible dans Fichiers), hors des archives `.kyokasho` et des préférences ; dossier exclu
    /// de la sauvegarde système.
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KyokashoDiagnosticState", isDirectory: true)
    }

    private let queue = DispatchQueue(label: "fr.noxygen59.kyokasho.diagnostics.session", qos: .utility)
    private var machine = DiagnosticSessionMachine()          // seulement sur `queue`
    private var file: DiagnosticSessionFile?                  // seulement sur `queue`
    private var observers: [NSObjectProtocol] = []            // fil principal
    private var closingTask: UIBackgroundTaskIdentifier = .invalid   // fil principal

    /// Constat du lancement, pour Réglages › Diagnostic (ce lancement seulement, en mémoire).
    private let reportLock = NSLock()
    private var report: DiagnosticPreviousSession = .none
    var launchReport: DiagnosticPreviousSession { reportLock.withLock { report } }

    private init() {}

    /// Une seule fois, au lancement, après `Diagnostics.start()` (récepteur des événements branché). Fil principal.
    func install() {
        guard observers.isEmpty else { return }
        let folder = Self.folder
        queue.async { [self] in
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var excluded = folder
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? excluded.setResourceValues(values)
            let file = DiagnosticSessionFile(folder: folder)
            self.file = file
            let (previous, lastGeneration) = file.consumeAtLaunch(now: Date())
            machine = DiagnosticSessionMachine(lastGeneration: lastGeneration)
            reportLock.withLock { report = previous }
            Self.publish(previous)
        }
        let center = NotificationCenter.default
        let foreground: (Notification) -> Void = { [weak self] _ in self?.handle(.foreground) }
        observers = [
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: foreground),
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: foreground),
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.handle(.inactive)
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.close()
            },
        ]
    }

    private func handle(_ event: DiagnosticSessionMachine.Event, done: (() -> Void)? = nil) {
        let memory = Int(Diagnostics.footprintMB())
        queue.async { [self] in
            if let state = machine.handle(event, now: Date(), memoryMB: memory) { file?.write(state) }
            if let done { DispatchQueue.main.async(execute: done) }
        }
    }

    /// Vrai arrière-plan : clôture durable. Une seule assertion d'arrière-plan, pour cette écriture seulement,
    /// rendue exactement une fois. Fil principal (notification).
    private func close() {
        if closingTask == .invalid {
            closingTask = UIApplication.shared.beginBackgroundTask(withName: "diagnostic.session") { [weak self] in
                self?.endClosingTask()
            }
        }
        handle(.background) { [weak self] in self?.endClosingTask() }
    }

    /// Fil principal (fin d'écriture ou expiration) : `endBackgroundTask` une seule fois.
    private func endClosingTask() {
        guard closingTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(closingTask)
        closingTask = .invalid
    }

    /// Une ligne au journal, au plus une fois par lancement ; aucun travail ni cause déduits.
    private static func publish(_ previous: DiagnosticPreviousSession) {
        switch previous {
        case .none:
            return
        case .notClosed(let age, let memory, let generation):
            var counts = [DiagnosticCount("generation", Int(clamping: generation))]
            if let age { counts.append(DiagnosticCount("age_s", age)) }
            DiagnosticCenter.shared.emit(.alerte, DiagnosticEvent(.alerte, .diagnostic, "session_precedente_non_cloturee",
                                                                  memoryMB: memory, counts: counts))
        case .unknown:
            DiagnosticCenter.shared.emit(.alerte, DiagnosticEvent(.alerte, .diagnostic, "etat_session_precedente_inconnu"))
        }
    }
}
