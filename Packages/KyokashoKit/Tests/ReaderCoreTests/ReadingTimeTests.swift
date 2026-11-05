// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-037 (#52) : temps de lecture active.
final class ReadingTimeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testSessionAddsElapsedTimeOnce() {
        var clock = ReadingClock(total: 60)
        clock.start(at: t0)
        clock.start(at: t0.addingTimeInterval(100))        // deuxième départ ignoré
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(30)), 90)
        clock.stop(at: t0.addingTimeInterval(120))
        clock.stop(at: t0.addingTimeInterval(500))         // arrêt sans séance : rien
        XCTAssertEqual(clock.total, 180)
        XCTAssertNil(clock.startedAt)
    }

    func testMissedStopIsCapped() {
        var clock = ReadingClock()
        clock.start(at: t0)
        clock.stop(at: t0.addingTimeInterval(3 * 86_400))   // app tuée en arrière-plan puis rouverte des jours après
        XCTAssertEqual(clock.total, ReadingClock.maxSession)
    }

    func testClockGoingBackwardsAddsNothing() {
        var clock = ReadingClock(total: 10)
        clock.start(at: t0)
        clock.stop(at: t0.addingTimeInterval(-50))
        XCTAssertEqual(clock.total, 10)
    }

    func testFormat() {
        XCTAssertEqual(ReadingClock.format(0), "0 min")
        XCTAssertEqual(ReadingClock.format(35 * 60 + 20), "35 min")
        XCTAssertEqual(ReadingClock.format(4 * 3600 + 7 * 60), "4 h 07")
        XCTAssertEqual(ReadingClock.format(2 * 86_400 + 5 * 3600), "2 j 5 h")
        XCTAssertEqual(ReadingClock.format(3 * 86_400), "3 j")
        XCTAssertEqual(ReadingClock.format(33 * 86_400), "1 mois 3 j")
    }
}

/// Journal des séances (préalable au tableau de bord du temps de lecture).
final class ReadingSessionLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testRecordsSessionsAndSkipsShortOnes() {
        var log = ReadingSessionLog()
        log.record(documentId: "a", start: t0, end: t0.addingTimeInterval(4))        // trop courte
        log.record(documentId: "a", start: t0, end: t0.addingTimeInterval(-30))      // horloge reculée
        log.record(documentId: "a", start: t0, end: t0.addingTimeInterval(125.9))
        log.record(documentId: "b", start: t0, end: t0.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(log.sessions, [
            ReadingSession(start: t0, seconds: 125, documentId: "a"),
            ReadingSession(start: t0, seconds: Int(ReadingClock.maxSession), documentId: "b"),
        ])
    }

    func testOldestSessionsDropBeyondLimit() {
        var log = ReadingSessionLog()
        for i in 0..<(ReadingSessionLog.maxEntries + 3) {
            log.record(documentId: "\(i)", start: t0, end: t0.addingTimeInterval(60))
        }
        XCTAssertEqual(log.sessions.count, ReadingSessionLog.maxEntries)
        XCTAssertEqual(log.sessions.first?.documentId, "3")
    }

    func testForgetKeepsTimeButDropsDocumentLink() {
        var log = ReadingSessionLog()
        log.record(documentId: "a", start: t0, end: t0.addingTimeInterval(60))
        log.record(documentId: "b", start: t0, end: t0.addingTimeInterval(90))
        log.forget(documentId: "a")
        XCTAssertEqual(log.sessions.map(\.documentId), ["", "b"])
        XCTAssertEqual(log.sessions.map(\.seconds), [60, 90])
    }

    func testRoundTripAndUnreadableData() {
        var log = ReadingSessionLog()
        log.record(documentId: "a", start: t0, end: t0.addingTimeInterval(60))
        XCTAssertEqual(ReadingSessionLog.decode(log.encoded()), log)
        XCTAssertEqual(ReadingSessionLog.decode(nil), ReadingSessionLog())
        XCTAssertEqual(ReadingSessionLog.decode(Data("pas du JSON".utf8)), ReadingSessionLog())
    }

    // MARK: Temps par espace (revue Codex de 291c02f)

    func testActiveMangaSessionCountsInMangaNotStudy() {
        var log = ReadingSessionLog()
        log.record(documentId: "manuel", start: t0, end: t0.addingTimeInterval(100), scope: .textbook)
        let time = log.breakdown(current: [:], activeScope: .manga, activeSeconds: 60)
        XCTAssertEqual(time.manga, 60)
        XCTAssertEqual(time.textbook, 100)
        XCTAssertEqual(time.study(total: 160), 100)
    }

    /// Corbeille, restauration ou effacement : le temps reste dans la case où il a été lu.
    func testScopeSurvivesTrashRestoreAndDeletion() {
        var log = ReadingSessionLog()
        log.record(documentId: "manga", start: t0, end: t0.addingTimeInterval(100), scope: .manga)
        XCTAssertEqual(log.breakdown(current: ["manga": .manga]).manga, 100)
        XCTAssertEqual(log.breakdown(current: [:]).manga, 100, "à la corbeille, absent de la liste")
        log.forget(documentId: "manga")
        XCTAssertEqual(log.breakdown(current: [:]).manga, 100, "effacé")
        XCTAssertEqual(log.breakdown(current: [:]).study(total: 100), 0)
    }

    func testMovingDocumentKeepsPastTimeWhereItWasRead() {
        var log = ReadingSessionLog()
        log.record(documentId: "doc", start: t0, end: t0.addingTimeInterval(100), scope: .book)
        let time = log.breakdown(current: ["doc": .manga])
        XCTAssertEqual(time.book, 100)
        XCTAssertEqual(time.manga, 0)
    }

    /// Journal écrit par une version précédente : sans rangement, l'état actuel du document décide (corbeille comprise).
    func testOldSessionsUseCurrentDocumentAndStayReadable() throws {
        let old = #"[{"s":1800000000,"d":100,"id":"manga"},{"s":1800000000,"d":50,"id":"disparu"}]"#.data(using: .utf8)
        let log = ReadingSessionLog.decode(old)
        XCTAssertEqual(log.sessions.count, 2)
        let time = log.breakdown(current: ["manga": .manga])
        XCTAssertEqual(time.manga, 100)
        XCTAssertEqual(time.study(total: 150), 50)
    }

    func testScopeRoundTrips() {
        var log = ReadingSessionLog()
        log.record(documentId: "a", start: t0, end: t0.addingTimeInterval(30), scope: .manga)
        XCTAssertEqual(ReadingSessionLog.decode(log.encoded()).sessions.first?.scope, .manga)
    }

    func testScopeFollowsSpaceThenCategory() {
        var document = LibraryDocument(id: "a", title: "a", originalFileName: "a.pdf", pageCount: 1, fileSize: 1, category: .textbook)
        XCTAssertEqual(ReadingScope(document: document), .textbook)
        document.settingsOverride.mangaSpace = true
        XCTAssertEqual(ReadingScope(document: document), .manga)
    }
}
