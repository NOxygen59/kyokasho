// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Compte le temps de lecture active pour l'accueil (RET-037, #52) : lecteur ouvert **et** app au premier plan.
///
/// Le total est gardé dans `UserDefaults` (un nombre de secondes, pas une donnée de la bibliothèque) à chaque arrêt de
/// séance. Il part de zéro : le temps passé avant cette version n'a jamais été enregistré.
@MainActor
final class ReadingTimeTracker: ObservableObject {
    static let shared = ReadingTimeTracker()
    static let storageKey = "stats.readingSeconds"

    @Published private(set) var clock: ReadingClock
    private var readerOpen = false
    private var appActive = true

    private init() {
        clock = ReadingClock(total: UserDefaults.standard.double(forKey: Self.storageKey))
    }

    func readerOpened() { readerOpen = true; update() }
    func readerClosed() { readerOpen = false; update() }

    /// Arrière-plan ou verrouillage : pause ; retour au premier plan : reprise si un livre est ouvert.
    func scenePhaseChanged(_ phase: ScenePhase) {
        appActive = phase == .active
        update()
    }

    private func update() {
        let now = Date()
        if readerOpen && appActive {
            clock.start(at: now)
        } else if clock.startedAt != nil {
            clock.stop(at: now)
            UserDefaults.standard.set(clock.total, forKey: Self.storageKey)
        }
    }
}
