// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Compte le temps de lecture active pour l'accueil (RET-037, #52) : lecteur ouvert **et** app au premier plan.
///
/// Le journal des séances (début, durée, document, rangement, pages, mots cherchés) est gardé dans `UserDefaults` à chaque
/// arrêt de séance : il nourrit à la fois le compteur de l'accueil et le tableau de bord, qui ne peuvent donc plus diverger.
///
/// **Départ de zéro (décision de NOxygen59, 05/11/2026) :** les chiffres d'avant ne correspondaient plus. Ce journal a ses
/// propres clés ; les anciennes ne sont ni lues ni effacées, et une version antérieure de l'app les retrouve intactes.
@MainActor
final class ReadingTimeTracker: ObservableObject {
    static let shared = ReadingTimeTracker()
    static let sessionsKey = "stats.v2.readingSessions"

    @Published private(set) var clock: ReadingClock
    private(set) var log: ReadingSessionLog
    /// Document à l'écran, `nil` lecteur fermé.
    private var documentId: String?
    /// Document de la séance en cours (gardé jusqu'à son arrêt, même si `documentId` est déjà remis à `nil`).
    private var sessionDocument: String?
    /// Rangement du document à l'écran, puis de la séance en cours (voir `ReadingScope`).
    private var scope: ReadingScope?
    private var sessionScope: ReadingScope?
    private var sessionPages = Set<Int>()
    private var sessionLookups = 0
    private var appActive = true

    private init() {
        let saved = ReadingSessionLog.decode(UserDefaults.standard.data(forKey: Self.sessionsKey))
        log = saved
        clock = ReadingClock(total: saved.totalSeconds)
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

    /// Un livre est-il en cours de lecture ?
    var isReading: Bool { clock.startedAt != nil }

    /// Page affichée dans la séance en cours.
    func pageViewed(_ page: Int) {
        guard clock.startedAt != nil else { return }
        sessionPages.insert(page)
    }

    /// Mot cherché au dictionnaire dans la séance en cours.
    func wordLookedUp() {
        guard clock.startedAt != nil else { return }
        sessionLookups += 1
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
                sessionPages = []
                sessionLookups = 0
            }
            clock.start(at: now)
        } else if let started = clock.startedAt {
            clock.stop(at: now)
            log.record(documentId: sessionDocument ?? "", start: started, end: now, scope: sessionScope,
                       pages: sessionPages.count, lookups: sessionLookups)
            // Le journal fait foi : une séance trop courte pour y entrer ne laisse pas d'écart avec le total affiché.
            clock = ReadingClock(total: log.totalSeconds)
            sessionScope = nil
            saveLog()
        }
    }

    private func saveLog() {
        UserDefaults.standard.set(log.encoded(), forKey: Self.sessionsKey)
    }
}
