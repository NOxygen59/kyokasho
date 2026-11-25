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
    private var thermal = DiagnosticThermalTracker()          // seulement sur `queue` (E2d)
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
        // E2d : état thermique lu **avant** l'inscription à ses notifications (règle du SDK), sans signal.
        checkThermalState()
        let center = NotificationCenter.default
        let foreground: (Notification) -> Void = { [weak self] _ in
            // Retour au premier plan sans clôture : l'assertion demandée tôt est rendue.
            self?.earlyAssertion?.end()
            self?.earlyAssertion = nil
            self?.handle(.foreground, phase: true)
            self?.checkThermalState()   // E2d : relu au retour (changement pendant la suspension)
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
            // E2d : un seul observateur thermique pour le processus ; état du système, jamais une température.
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
                self?.checkThermalState()
            },
        ]
    }

    /// Relit l'état thermique du système et journalise un vrai changement (E2d) ; indépendant du relevé de batterie,
    /// sans minuterie.
    /// Lu **sur la file série**, au moment du traitement : l'ordre des lectures est celui de la file, un rappel
    /// retardé ne peut pas fabriquer une transition inverse (revue E2d).
    private func checkThermalState() {
        queue.async { [self] in
            let raw = ProcessInfo.processInfo.thermalState.rawValue
            if let event = thermal.observe(raw: raw) { DiagnosticCenter.shared.emit(event.level, event) }
        }
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
    /// Les transitions (premier plan, fond) sont **prioritaires** : comptées au signal sur le fil principal, avant
    /// d'entrer dans la file ; tant qu'une transition attend, aucune capture de travaux ni alerte mémoire n'écrit
    /// (la transition écrira l'état complet). Revue R2 E2c, B4.
    /// `phase` : phase réelle publiée **dans le même verrou** que la réservation de la transition (revue R2 E2c,
    /// passage 4) : aucune capture ne peut se glisser entre les deux.
    private func handle(_ event: DiagnosticSessionMachine.Event, phase: Bool? = nil, done: (() -> Void)? = nil) {
        let isTransition = event != .inactive
        pendingLock.withLock {
            if let phase { foreground = phase }
            if isTransition { pendingTransitions += 1 }
        }
        queue.async { [self] in
            defer { if isTransition { pendingLock.withLock { pendingTransitions -= 1 } } }
            // Retour après une clôture ratée : nouvelle génération, jamais d'écriture dans l'ancienne (passage 5).
            if event == .foreground, closeFailed {
                machine.abandonAfterFailedClose()
                closeFailed = false
            }
            let wasArmed = machine.armed
            if let file, machine.next(event, now: Date(), memoryMB: nil) != nil,
               let state = machine.next(event, now: Date(), memoryMB: Int(Diagnostics.footprintMB())), file.write(state) {
                machine.commit(state)
                ongoingDirty = false   // l'état écrit porte les travaux courants (armé) ou n'en porte pas (clos)
            } else if event == .background, wasArmed {
                closeFailed = true      // clôture non écrite : le rattrapage ne doit pas écrire dans cette génération
            } else if event == .foreground, !closeFailed, ongoingDirty, let file, machine.armed, isForeground,
                      let state = machine.next(ongoing: nil, now: Date(), memoryMB: nil), file.write(state) {
                // Transition sans effet (déjà armée) : écrit la capture écartée pendant qu'elle attendait.
                ongoingDirty = false
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
        // Phase réelle « fond » publiée avec la réservation : aucune écriture de travaux ou de mémoire en attente ne
        // passe après le signal, même si l'écriture de clôture échoue (revue R2 E2c, B4).
        handle(.background, phase: false) { assertion.end() }
    }


    /// Nouvelle projection des travaux suivis (E2c), publiée par `ActivityCenter` hors de son verrou, aux bornes
    /// début/fin. **Coalescée** : seule la plus récente attend, un seul passage sur la file l'écrit (un lot d'imports
    /// ne fait pas une écriture par fichier) ; une projection plus ancienne est ignorée (revue R2 E2c, B4).
    func updateOngoing(_ ongoing: DiagnosticOngoing) {
        let schedule: Bool = pendingLock.withLock {
            if let current = pendingOngoing, current.revision >= ongoing.revision { return false }
            let first = pendingOngoing == nil
            pendingOngoing = ongoing
            return first
        }
        guard schedule else { return }
        queue.async { [self] in
            guard let latest = pendingLock.withLock({ () -> DiagnosticOngoing? in defer { pendingOngoing = nil }; return pendingOngoing })
            else { return }
            // Connaissance en mémoire adoptée même si l'écriture échoue : une fin de travail n'est pas perdue pour
            // les écritures suivantes ni pour l'alerte mémoire (B3). L'écriture n'a lieu que session armée.
            let previous = machine.ongoing
            machine.commit(ongoing: latest)
            guard machine.ongoing != previous || ongoingDirty else { return }
            guard let file, capturesMayWrite, machine.armed,
                  let state = machine.next(ongoing: nil, now: Date(), memoryMB: nil), file.write(state) else {
                ongoingDirty = true   // à écrire par la prochaine transition ou capture (passage 4)
                return
            }
            ongoingDirty = false
        }
    }
    private let pendingLock = NSLock()
    private var pendingOngoing: DiagnosticOngoing?
    /// Phase réelle du processus, notée au signal (fil principal), distincte de l'état écrit.
    private var foreground = false
    /// Transitions signalées et pas encore traitées par la file (B4).
    private var pendingTransitions = 0
    /// Projection adoptée en mémoire mais pas encore écrite (seulement sur `queue`).
    private var ongoingDirty = false
    /// La dernière clôture n'a pas pu être écrite (seulement sur `queue`).
    private var closeFailed = false
    private var isForeground: Bool { pendingLock.withLock { foreground } }
    /// Une capture peut écrire : premier plan réel et aucune transition en attente.
    private var capturesMayWrite: Bool { pendingLock.withLock { foreground && pendingTransitions == 0 } }

    /// Un seul observateur de la pression mémoire pour le processus (E2c), installé une fois. L'empreinte est relevée
    /// **avant** les libérations (0 = inconnue), notée dans l'état armé avec les travaux en cours, puis les
    /// libérations existantes sont lancées une fois. Aucune cause n'est déduite. Fil principal.
    func installMemoryObserver(release: @escaping () -> Void) {
        guard memoryObserver == nil else { return }
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            // Empreinte et travaux figés au moment du signal (revue R2 E2c, B2).
            let footprint = Int(Diagnostics.footprintMB())
            self?.memoryWarning(memoryMB: footprint > 0 ? footprint : nil, ongoing: ActivityCenter.shared.trackedSnapshot())
            release()
        }
    }

    private func memoryWarning(memoryMB: Int?, ongoing: DiagnosticOngoing) {
        let foregroundNow = isForeground
        queue.async { [self] in
            var counts = [DiagnosticCount("operations_suivies", ongoing.entries.count)]
            if ongoing.truncated { counts.append(DiagnosticCount("tronquee", 1)) }
            if memoryMB == nil { counts.append(DiagnosticCount("memoire_inconnue", 1)) }
            DiagnosticCenter.shared.emit(.alerte, DiagnosticEvent(.alerte, .memoire, "alerte_memoire", memoryMB: memoryMB, counts: counts))
            // Travaux connus au moment de l'alerte, avec leur op (revue R2 E2c, B2).
            for entry in ongoing.entries {
                DiagnosticCenter.shared.emit(.alerte, DiagnosticEvent(.alerte, entry.kind.zone, "travail_connu_alerte_memoire",
                                                                      op: DiagnosticOperation(raw: entry.op)))
            }
            // Jamais en fond : une clôture ratée ne doit pas être réécrite « armée » (B4).
            if foregroundNow, capturesMayWrite, let file, let state = machine.next(ongoing: nil, now: Date(), memoryMB: memoryMB) {
                file.write(state)
            }
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
