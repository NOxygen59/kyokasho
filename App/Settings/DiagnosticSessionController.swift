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
    /// Observateur unique de la pression mémoire du processus (E2c), fil principal.
    private var memoryObserver: NSObjectProtocol?

    /// Constat du lancement, pour Réglages › Diagnostic (ce lancement seulement, en mémoire).
    private let reportLock = NSLock()
    private var report: DiagnosticPreviousSession = .none
    private var detail: DiagnosticDetailWindow?
    var launchReport: DiagnosticPreviousSession { reportLock.withLock { report } }
    /// Fenêtre de détail automatique de ce lancement (E2b), pour l'affichage.
    var detailWindow: DiagnosticDetailWindow? { reportLock.withLock { detail } }

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
                Self.publish(.unknown, detail: nil)
                return
            }
            let file = DiagnosticSessionFile(folder: folder)
            self.file = file
            let launch = file.consumeAtLaunch(now: Date())
            machine = DiagnosticSessionMachine(lastGeneration: launch.lastGeneration, detail: launch.detail)
            // E2b : détail du journal pendant 24 h après une session non clôturée (réglage manuel inchangé).
            DiagnosticCenter.shared.setAutoDetail(launch.detail)
            reportLock.withLock { report = launch.previous; detail = launch.detail }
            Self.publish(launch.previous, detail: launch.detail)
            Self.publishOngoing(launch)
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
        // L'assertion anticipée n'est reprise que si iOS l'a accordée et qu'elle court encore.
        let early = earlyAssertion
        earlyAssertion = nil
        let assertion: BackgroundAssertion
        if let early, early.id != .invalid { assertion = early } else { assertion = BackgroundAssertion.begin() }
        handle(.background) { assertion.end() }
    }


    /// Nouvelle projection des travaux suivis (E2c), publiée par `ActivityCenter` hors de son verrou, aux bornes
    /// début/fin. Écrite seulement si la session est armée ; une projection plus ancienne est ignorée.
    func updateOngoing(_ ongoing: DiagnosticOngoing) {
        queue.async { [self] in
            guard let file else { return }
            if machine.armed {
                guard let state = machine.next(ongoing: ongoing, now: Date(), memoryMB: nil), file.write(state) else { return }
            }
            machine.commit(ongoing: ongoing)
        }
    }

    /// Un seul observateur de la pression mémoire pour le processus (E2c), installé une fois. L'empreinte est relevée
    /// **avant** les libérations (0 = inconnue), notée dans l'état armé avec les travaux en cours, puis les
    /// libérations existantes sont lancées une fois. Aucune cause n'est déduite. Fil principal.
    func installMemoryObserver(release: @escaping () -> Void) {
        guard memoryObserver == nil else { return }
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            let footprint = Int(Diagnostics.footprintMB())
            self?.memoryWarning(memoryMB: footprint > 0 ? footprint : nil)
            release()
        }
    }

    private func memoryWarning(memoryMB: Int?) {
        queue.async { [self] in
            let ongoing = machine.ongoing
            var counts = [DiagnosticCount("operations_suivies", ongoing.entries.count)]
            if ongoing.truncated { counts.append(DiagnosticCount("tronquee", 1)) }
            DiagnosticCenter.shared.emit(.alerte, DiagnosticEvent(.alerte, .memoire, "alerte_memoire", memoryMB: memoryMB, counts: counts))
            if let file, let state = machine.next(ongoing: nil, now: Date(), memoryMB: memoryMB) { file.write(state) }
        }
    }

    /// Travaux suivis qui tournaient lors du dernier état écrit d'une session non clôturée (E2c) : une ligne par
    /// travail avec son `op` d'origine, ou « aucun travail suivi connu » (connaissance limitée, pas une absence).
    private static func publishOngoing(_ launch: DiagnosticSessionFile.Launch) {
        guard case .notClosed = launch.previous else { return }
        for entry in launch.ongoing {
            DiagnosticCenter.shared.emit(.alerte, DiagnosticEvent(.alerte, entry.kind.zone, "travail_en_cours_avant_arret",
                                                                  op: DiagnosticOperation(raw: entry.op)))
        }
        if launch.ongoing.isEmpty {
            DiagnosticCenter.shared.emit(.alerte, DiagnosticEvent(.alerte, .diagnostic, "aucun_travail_suivi_connu"))
        }
        if launch.ongoingTruncated {
            DiagnosticCenter.shared.emit(.alerte, DiagnosticEvent(.alerte, .diagnostic, "travaux_suivis_tronques",
                                                                  counts: [DiagnosticCount("limite", DiagnosticOngoing.limit)]))
        }
    }

    /// Une ligne au journal, au plus une fois par lancement ; aucun travail ni cause déduits.
    private static func publish(_ previous: DiagnosticPreviousSession, detail: DiagnosticDetailWindow?) {
        switch previous {
        case .none:
            return
        case .notClosed(let age, let memory, let generation):
            var counts = [DiagnosticCount("generation", Int(clamping: generation))]
            if let age { counts.append(DiagnosticCount("age_s", age)) }
            DiagnosticCenter.shared.emit(.alerte, DiagnosticEvent(.alerte, .diagnostic, "session_precedente_non_cloturee",
                                                                  memoryMB: memory, counts: counts))
            if detail != nil {
                DiagnosticCenter.shared.emit(.alerte, DiagnosticEvent(.alerte, .diagnostic, "detail_automatique_24h",
                                                                      counts: [DiagnosticCount("duree_s", Int(DiagnosticDetailWindow.duration))]))
            }
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
