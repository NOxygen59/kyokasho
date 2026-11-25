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
    /// Assertion demandée tôt, à `willResignActive`, pour couvrir une clôture éventuelle (fil principal).
    private var earlyAssertion: BackgroundAssertion?

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
            // Exclusion de la sauvegarde iOS **confirmée** avant toute lecture ou écriture ; sinon, pas de suivi de
            // session pour ce lancement, et le constat est « inconnu » (revue R2 E2a, B4).
            guard Self.excludeFromBackup(folder) else {
                reportLock.withLock { report = .unknown }
                Self.publish(.unknown)
                return
            }
            let file = DiagnosticSessionFile(folder: folder)
            self.file = file
            let (previous, lastGeneration) = file.consumeAtLaunch(now: Date())
            machine = DiagnosticSessionMachine(lastGeneration: lastGeneration)
            reportLock.withLock { report = previous }
            Self.publish(previous)
        }
        let center = NotificationCenter.default
        let foreground: (Notification) -> Void = { [weak self] _ in
            // Retour au premier plan sans clôture : l'assertion demandée tôt est rendue.
            self?.earlyAssertion?.end()
            self?.earlyAssertion = nil
            self?.handle(.foreground)
        }
        observers = [
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: foreground),
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: foreground),
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                // Sans clore : on demande seulement tôt la protection d'une clôture possible (revue R2 E2a, B1).
                guard let self else { return }
                if self.earlyAssertion == nil { self.earlyAssertion = BackgroundAssertion.begin() }
                self.handle(.inactive)
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.close()
            },
        ]
    }

    /// Pose et **relit** l'exclusion de la sauvegarde iOS sur le dossier.
    private static func excludeFromBackup(_ folder: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var url = folder
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            url.removeAllCachedResourceValues()
            return try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
        } catch {
            return false
        }
    }

    /// L'automate n'adopte l'état qu'après une écriture réussie (B2) ; la mémoire n'est lue que s'il y a à écrire.
    private func handle(_ event: DiagnosticSessionMachine.Event, done: (() -> Void)? = nil) {
        queue.async { [self] in
            if let file, machine.next(event, now: Date(), memoryMB: nil) != nil,
               let state = machine.next(event, now: Date(), memoryMB: Int(Diagnostics.footprintMB())), file.write(state) {
                machine.commit(state)
            }
            if let done { DispatchQueue.main.async(execute: done) }
        }
    }

    /// Vrai arrière-plan : clôture durable. **Une assertion par clôture**, rendue exactement une fois par celle-ci
    /// (fin d'écriture ou expiration) : une clôture ancienne ne peut pas rendre celle d'une autre (revue R2 E2a, B1).
    /// Fil principal (notification).
    private func close() {
        let assertion = earlyAssertion ?? BackgroundAssertion.begin()
        earlyAssertion = nil
        handle(.background) { assertion.end() }
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


/// Une assertion d'arrière-plan et sa fin unique (fil principal).
private final class BackgroundAssertion {
    var id: UIBackgroundTaskIdentifier = .invalid

    /// Demande une assertion qui se rend d'elle-même à l'expiration.
    static func begin() -> BackgroundAssertion {
        let assertion = BackgroundAssertion()
        assertion.id = UIApplication.shared.beginBackgroundTask(withName: "diagnostic.session") { assertion.end() }
        return assertion
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
