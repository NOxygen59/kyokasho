// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import DiagnosticKit

/// PLAN-DIAG-001 E2b (DEC-02 B) : détail automatique de 24 h après une session non clôturée, jamais prolongé par une
/// relance, expiré même sans relance, indépendant du réglage manuel.
final class DiagnosticDetailWindowTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_764_000_000)
    private var folder: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        folder = fm.temporaryDirectory.appendingPathComponent("detail-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: folder) }

    /// Horloge réglable pour les tests (sûre entre fils).
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        init(_ value: Date) { self.value = value }
        var now: Date { get { lock.withLock { value } } set { lock.withLock { value = newValue } } }
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [DiagnosticEvent] = []
        func add(_ e: DiagnosticEvent) { lock.withLock { items.append(e) } }
        var count: Int { lock.withLock { items.count } }
    }

    func testWindowIsExactly24hAndHalfOpen() {
        let w = DiagnosticDetailWindow.starting(at: t0)
        XCTAssertTrue(w.isActive(at: t0))
        XCTAssertTrue(w.isActive(at: t0.addingTimeInterval(86_399)))
        XCTAssertFalse(w.isActive(at: t0.addingTimeInterval(86_400)), "échéance exacte")
        XCTAssertFalse(w.isActive(at: t0.addingTimeInterval(-60)), "horloge reculée : pas active")
        XCTAssertFalse(DiagnosticDetailWindow(from: t0, until: t0.addingTimeInterval(200_000)).isWellFormed)
    }

    /// Constat → fenêtre posée ; relances suivantes : reportée telle quelle, jamais prolongée, puis absente à l'échéance.
    func testWindowIsSetOnceAndNeverExtended() {
        let file = DiagnosticSessionFile(folder: folder)
        file.write(DiagnosticSessionState(generation: 1, state: .armed, updatedAt: t0, memoryMB: nil))
        let launch = file.consumeAtLaunch(now: t0.addingTimeInterval(10))
        let window = try! XCTUnwrap(launch.detail)
        XCTAssertEqual(window.from, t0.addingTimeInterval(10))
        // Session suivante propre (armée puis close), avec la fenêtre reportée par l'automate.
        var m = DiagnosticSessionMachine(lastGeneration: launch.lastGeneration, detail: launch.detail)
        file.write(m.handle(.foreground, now: t0.addingTimeInterval(20), memoryMB: nil)!)
        file.write(m.handle(.background, now: t0.addingTimeInterval(30), memoryMB: nil)!)
        let relaunch = file.consumeAtLaunch(now: t0.addingTimeInterval(3_600))
        XCTAssertEqual(relaunch.previous, .none)
        XCTAssertEqual(relaunch.detail, window, "même fenêtre, pas de prolongation")
        XCTAssertNil(file.consumeAtLaunch(now: window.until).detail, "expirée : plus rien")
    }

    /// État illisible, invalide ou consommation ratée : aucune fenêtre ouverte.
    func testNoWindowWithoutAValidConsumption() throws {
        let file = DiagnosticSessionFile(folder: folder)
        XCTAssertNil(file.consumeAtLaunch(now: t0).detail, "absent")
        try Data("{".utf8).write(to: file.url)
        XCTAssertNil(file.consumeAtLaunch(now: t0).detail, "invalide")
        file.write(DiagnosticSessionState(generation: 2, state: .armed, updatedAt: t0, memoryMB: nil))
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let failed = file.consumeAtLaunch(now: t0)
        XCTAssertEqual(failed.previous, .unknown)
        XCTAssertNil(failed.detail, "consommation ratée : pas de fenêtre")
    }

    /// Une fenêtre mal formée (durée modifiée à la main) rend l'état invalide.
    func testTamperedWindowIsInvalid() throws {
        let file = DiagnosticSessionFile(folder: folder)
        let json = #"{"schemaVersion":1,"generation":3,"state":"closed","updatedAt":"2026-11-25T00:00:00Z","detail":{"from":"2026-11-25T00:00:00Z","until":"2026-12-25T00:00:00Z"}}"#
        try Data(json.utf8).write(to: file.url)
        XCTAssertEqual(file.consumeAtLaunch(now: t0).previous, .unknown)
        let extra = #"{"schemaVersion":1,"generation":3,"state":"closed","updatedAt":"2026-11-25T00:00:00Z","detail":{"from":"2026-11-25T00:00:00Z","until":"2026-11-26T00:00:00Z","titre":"x"}}"#
        try Data(extra.utf8).write(to: file.url)
        XCTAssertEqual(file.consumeAtLaunch(now: t0).previous, .unknown, "clé inconnue dans la fenêtre")
    }

    /// Centre : info laissé passer pendant la fenêtre, filtré avant construction ensuite, même sans relance ; le
    /// réglage manuel reste indépendant.
    func testCenterFollowsWindowAndExpiresWithoutRelaunch() {
        let clock = Clock(t0)
        let center = DiagnosticCenter(now: { clock.now })
        let box = Box()
        center.install(sink: { box.add($0) }, salt: 1)
        var built = 0
        center.emit(.info, { built += 1; return DiagnosticEvent(.info, .app, "x") }())
        XCTAssertEqual(built, 0)
        center.setAutoDetail(.starting(at: t0))
        XCTAssertTrue(center.autoDetailActive)
        center.emit(.info, DiagnosticEvent(.info, .app, "pendant"))
        XCTAssertEqual(box.count, 1)
        clock.now = t0.addingTimeInterval(86_400)
        XCTAssertFalse(center.autoDetailActive)
        center.emit(.info, { built += 1; return DiagnosticEvent(.info, .app, "après") }())
        XCTAssertEqual(built, 0, "expirée : filtré avant construction")
        center.setDetailed(true)
        center.emit(.info, DiagnosticEvent(.info, .app, "manuel"))
        XCTAssertEqual(box.count, 2, "le manuel suffit seul")
        clock.now = t0.addingTimeInterval(-3_600)
        center.setDetailed(false)
        center.emit(.info, DiagnosticEvent(.info, .app, "horloge reculée"))
        XCTAssertEqual(box.count, 2, "une horloge reculée n'ouvre pas la fenêtre")
    }

    /// B2 : une fois expirée, reculer l'horloge ne rouvre pas la fenêtre.
    func testExpiredWindowNeverReopens() {
        let clock = Clock(t0)
        let center = DiagnosticCenter(now: { clock.now })
        center.setAutoDetail(.starting(at: t0))
        XCTAssertTrue(center.autoDetailActive)
        clock.now = t0.addingTimeInterval(86_400)
        XCTAssertFalse(center.autoDetailActive)
        clock.now = t0.addingTimeInterval(3_600)
        XCTAssertFalse(center.autoDetailActive, "horloge reculée après l'échéance : fenêtre oubliée")
    }

    /// Nouvelle session non clôturée pendant une fenêtre : nouvelle fenêtre ancrée au second constat.
    func testNewInterruptionDuringWindowStartsANewWindow() {
        let file = DiagnosticSessionFile(folder: folder)
        file.write(DiagnosticSessionState(generation: 1, state: .armed, updatedAt: t0, memoryMB: nil))
        let first = file.consumeAtLaunch(now: t0)
        var m = DiagnosticSessionMachine(lastGeneration: first.lastGeneration, detail: first.detail)
        file.write(m.handle(.foreground, now: t0.addingTimeInterval(60), memoryMB: nil)!)   // puis arrêt brutal
        let second = file.consumeAtLaunch(now: t0.addingTimeInterval(7_200))
        XCTAssertEqual(second.previous, .notClosed(ageSeconds: 7_140, memoryMB: nil, generation: 2))
        XCTAssertEqual(second.detail?.from, t0.addingTimeInterval(7_200))
    }


    /// Le manuel ne masque pas l'échéance : émission en manuel à l'échéance, recul dans la fenêtre, manuel coupé →
    /// filtré (aucun appel direct à `autoDetailActive`).
    func testManualModeDoesNotHideExpiry() {
        let clock = Clock(t0)
        let center = DiagnosticCenter(now: { clock.now })
        let box = Box()
        center.install(sink: { box.add($0) }, salt: 1)
        center.setAutoDetail(.starting(at: t0))
        center.setDetailed(true)
        clock.now = t0.addingTimeInterval(86_400)
        center.emit(.info, DiagnosticEvent(.info, .app, "manuel à l'échéance"))
        XCTAssertEqual(box.count, 1)
        clock.now = t0.addingTimeInterval(3_600)
        center.setDetailed(false)
        center.emit(.info, DiagnosticEvent(.info, .app, "après recul"))
        XCTAssertEqual(box.count, 1, "fenêtre oubliée à l'échéance, même vue en mode manuel")
    }

}
