// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DiagnosticKit
import Foundation
import UIKit

/// Sonde du fil principal (PLAN-DIAG-001, E2e, DEC-03 A) : en **mode diagnostic seulement**, et seulement quand l'app
/// est active. Toutes les 500 ms, une file utilitaire envoie un battement au fil principal ; **une seule requête en
/// vol**. Les décisions (seuil 250 ms, mesure à froid, veille, dédoublonnage) sont dans `DiagnosticMainThreadProbe`.
///
/// Aucune écriture synchrone ni capture UIKit : la ligne part par `Diagnostics.manualOnly` (écriture asynchrone,
/// mode manuel revérifié à l'écriture). Le fil principal ne fait que lire deux horloges. Pas d'injection de
/// ralentissement dans la livraison (revue R2 E2e, B3) : la recette se fait sur un geste lent réel.
final class DiagnosticMainThreadMonitor: @unchecked Sendable {
    static let shared = DiagnosticMainThreadMonitor()

    private let queue = DispatchQueue(label: "fr.noxygen59.kyokasho.diagnostics.probe", qos: .utility)
    private var timer: DispatchSourceTimer?               // seulement sur `queue`
    private var probe = DiagnosticMainThreadProbe()        // seulement sur `queue`
    /// Change à chaque arrêt ou armement : une réponse d'une génération passée n'est pas mesurée.
    private var generation = 0                             // seulement sur `queue`
    /// Une seule requête physique en vol, **même après un changement de génération** : seule sa réponse libère la
    /// place (contrat E2e, réunion DIAG). Un fil principal bloqué ne reçoit donc jamais plus d'un battement.
    private var inFlight = false                           // seulement sur `queue`
    @MainActor private static var lifecycleInstalled = false

    private init() {}

    /// À appeler au lancement et quand le réglage « Mode diagnostic » change. Fil principal.
    @MainActor static func updateActivation() {
        let enabled = Diagnostics.enabled
        guard enabled || lifecycleInstalled else { return }
        if enabled, !lifecycleInstalled {
            lifecycleInstalled = true
            let center = NotificationCenter.default
            // Arrêt hors avant-plan (Centre de contrôle, sélecteur, fond) : pas de faux délai au retour.
            for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
                _ = center.addObserver(forName: name, object: nil, queue: .main) { _ in shared.configure(running: false) }
            }
            _ = center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { updateActivation() }
            }
        }
        shared.configure(running: enabled && UIApplication.shared.applicationState == .active)
    }

    private func configure(running: Bool) {
        queue.async { [self] in
            generation &+= 1
            guard running, Diagnostics.enabled else {
                timer?.cancel()
                timer = nil
                return
            }
            probe.rearm()
            guard timer == nil else { return }
            let interval = DispatchTimeInterval.milliseconds(DiagnosticMainThreadProbe.intervalMs)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
            timer.setEventHandler { [weak self] in self?.beat() }
            self.timer = timer
            timer.resume()
        }
    }

    /// Sur `queue`. Chaque réveil est noté (trous d'observation) ; un battement part seulement si la place est libre.
    private func beat() {
        let now = DiagnosticMainThreadProbe.Instant.now()
        probe.tick(at: now)
        guard !inFlight, Diagnostics.enabled else { return }
        inFlight = true
        probe.send(at: now)
        let current = generation
        DispatchQueue.main.async { [self] in
            let answered = DiagnosticMainThreadProbe.Instant.now()
            queue.async { [self] in
                inFlight = false                       // toute réponse libère sa place
                guard current == generation, timer != nil, Diagnostics.enabled else { return }
                // Voie réservée au mode manuel, revérifié au moment d'écrire : jamais par la fenêtre E2b (B2).
                if let event = probe.observe(sent: now, answered: answered) { Diagnostics.manualOnly(event) }
            }
        }
    }
}
