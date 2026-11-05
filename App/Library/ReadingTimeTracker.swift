// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Compte le temps de lecture active pour l'accueil (RET-037, #52) : lecteur ouvert **et** app au premier plan.
///
/// Le total est gardé dans `UserDefaults` (un nombre de secondes, pas une donnée de la bibliothèque) à chaque arrêt de
/// séance. Il part de zéro : le temps passé avant cette version n'a jamais été enregistré. Chaque séance est aussi
/// notée dans un petit journal (début, durée, document), préalable au futur tableau de bord.
@MainActor
final class ReadingTimeTracker: ObservableObject {
    static let shared = ReadingTimeTracker()
    static let storageKey = "stats.readingSeconds"
    static let sessionsKey = "stats.readingSessions"

    @Published private(set) var clock: ReadingClock
    private(set) var log: ReadingSessionLog
    /// Document à l'écran, `nil` lecteur fermé.
    private var documentId: String?
    /// Document de la séance en cours (gardé jusqu'à son arrêt, même si `documentId` est déjà remis à `nil`).
    private var sessionDocument: String?
    /// Rangement du document à l'écran, puis de la séance en cours (voir `ReadingScope`).
    private var scope: ReadingScope?
    private var sessionScope: ReadingScope?
    private var appActive = true

    private init() {
        clock = ReadingClock(total: UserDefaults.standard.double(forKey: Self.storageKey))
        log = ReadingSessionLog.decode(UserDefaults.standard.data(forKey: Self.sessionsKey))
    }

    func readerOpened(document: LibraryDocument) {
        if documentId != nil && documentId != document.id { readerClosed(documentId: documentId!) }
        documentId = document.id
        scope = ReadingScope(document: document)
        update()
    }

    /// Ignoré si un autre livre a déjà pris l'écran (son `onAppear` peut passer avant l'`onDisappear` du précédent).
    func readerClosed(documentId: String) {
        guard self.documentId == documentId else { return }
        self.documentId = nil
        update()
    }

    /// Temps par espace à cet instant, séance en cours comprise. `documents` : toute la bibliothèque, corbeille comprise.
    func breakdown(documents: [LibraryDocument], at date: Date) -> ReadingBreakdown {
        let current = Dictionary(documents.map { ($0.id, ReadingScope(document: $0)) }, uniquingKeysWith: { first, _ in first })
        return log.breakdown(current: current, activeScope: sessionScope,
                             activeSeconds: clock.elapsed(at: date) - clock.total)
    }

    /// Document supprimé : ses séances restent dans les jours lus, sans lien avec lui.
    func forget(documentId: String) {
        log.forget(documentId: documentId)
        saveLog()
    }

    /// Arrière-plan ou verrouillage : pause ; retour au premier plan : reprise si un livre est ouvert.
    func scenePhaseChanged(_ phase: ScenePhase) {
        appActive = phase == .active
        update()
    }

    private func update() {
        let now = Date()
        if documentId != nil && appActive {
            if clock.startedAt == nil {
                sessionDocument = documentId
                sessionScope = scope
            }
            clock.start(at: now)
        } else if let started = clock.startedAt {
            clock.stop(at: now)
            UserDefaults.standard.set(clock.total, forKey: Self.storageKey)
            log.record(documentId: sessionDocument ?? "", start: started, end: now, scope: sessionScope)
            sessionScope = nil
            saveLog()
        }
    }

    private func saveLog() {
        UserDefaults.standard.set(log.encoded(), forKey: Self.sessionsKey)
    }
}
