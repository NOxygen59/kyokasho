// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import DiagnosticKit

/// PLAN-DIAG-001, E2a : session au niveau du processus, constat « non clôturée » au plus une fois, jamais de fausse
/// alerte sur un état illisible.
final class DiagnosticSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_764_000_000)
    private var folder: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        folder = fm.temporaryDirectory.appendingPathComponent("session-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? fm.removeItem(at: folder)
    }

    func testMachineIsIdempotentAndIgnoresInactive() {
        var m = DiagnosticSessionMachine()
        XCTAssertEqual(m.handle(.foreground, now: t0, memoryMB: 100)?.state, .armed)
        XCTAssertNil(m.handle(.foreground, now: t0, memoryMB: 100), "willEnterForeground puis didBecomeActive : une fois")
        XCTAssertNil(m.handle(.inactive, now: t0, memoryMB: nil), "Centre de contrôle, Split View : rien")
        let closed = m.handle(.background, now: t0, memoryMB: nil)
        XCTAssertEqual(closed?.state, .closed)
        XCTAssertEqual(closed?.generation, 1)
        XCTAssertNil(m.handle(.background, now: t0, memoryMB: nil), "fond doublé : rien")
        XCTAssertEqual(m.handle(.foreground, now: t0, memoryMB: nil)?.generation, 2, "vrai réarmement : nouvelle génération")
    }

    func testBackgroundOnlyLaunchArmsNothing() {
        var m = DiagnosticSessionMachine(lastGeneration: 7)
        XCTAssertNil(m.handle(.background, now: t0, memoryMB: nil))
        XCTAssertNil(m.handle(.inactive, now: t0, memoryMB: nil))
        XCTAssertFalse(m.armed)
        XCTAssertEqual(m.handle(.foreground, now: t0, memoryMB: nil)?.generation, 8, "suit la génération précédente")
    }

    func testZeroMemoryIsUnknown() {
        XCTAssertNil(DiagnosticSessionState(generation: 1, state: .armed, updatedAt: t0, memoryMB: 0).memoryMB)
    }

    func testCleanCloseReportsNothing() {
        let file = DiagnosticSessionFile(folder: folder)
        XCTAssertEqual(file.consumeAtLaunch(now: t0).previous, .none, "absent")
        XCTAssertTrue(file.write(DiagnosticSessionState(generation: 3, state: .closed, updatedAt: t0, memoryMB: 50)))
        XCTAssertEqual(file.consumeAtLaunch(now: t0.addingTimeInterval(60)).previous, .none)
    }

    func testArmedIsReportedOnceThenConsumed() {
        let file = DiagnosticSessionFile(folder: folder)
        XCTAssertTrue(file.write(DiagnosticSessionState(generation: 4, state: .armed, updatedAt: t0, memoryMB: 210)))
        let first = file.consumeAtLaunch(now: t0.addingTimeInterval(125))
        XCTAssertEqual(first.previous, .notClosed(ageSeconds: 125, memoryMB: 210, generation: 4))
        XCTAssertEqual(first.lastGeneration, 4)
        XCTAssertEqual(file.consumeAtLaunch(now: t0.addingTimeInterval(200)).previous, .none, "pas de doublon")
    }

    func testClockBackwardsGivesUnknownAge() {
        let file = DiagnosticSessionFile(folder: folder)
        file.write(DiagnosticSessionState(generation: 1, state: .armed, updatedAt: t0, memoryMB: nil))
        XCTAssertEqual(file.consumeAtLaunch(now: t0.addingTimeInterval(-30)).previous,
                       .notClosed(ageSeconds: nil, memoryMB: nil, generation: 1))
    }

    func testInvalidOrUnreadableIsUnknownNeverInterrupted() throws {
        let file = DiagnosticSessionFile(folder: folder)
        for bad in ["{", #"{"schemaVersion":99,"generation":1,"state":"armed","updatedAt":"2026-11-25T00:00:00Z"}"#,
                    #"{"schemaVersion":1,"generation":1,"state":"plantage","updatedAt":"2026-11-25T00:00:00Z"}"#,
                    #"{"schemaVersion":1,"generation":0,"state":"armed","updatedAt":"2026-11-25T00:00:00Z"}"#,
                    String(repeating: " ", count: 5_000)] {
            try Data(bad.utf8).write(to: file.url)
            XCTAssertEqual(file.consumeAtLaunch(now: t0).previous, .unknown, bad.prefix(40).description)
        }
        try fm.removeItem(at: file.url)
        try fm.createDirectory(at: file.url, withIntermediateDirectories: true)   // un dossier à la place du fichier
        XCTAssertEqual(file.consumeAtLaunch(now: t0).previous, .unknown, "illisible n'est pas absent")
    }

    /// Consommation impossible (dossier en lecture seule) : aucune interruption affirmée, état conservé.
    func testFailedConsumeIsUnknown() throws {
        let file = DiagnosticSessionFile(folder: folder)
        XCTAssertTrue(file.write(DiagnosticSessionState(generation: 2, state: .armed, updatedAt: t0, memoryMB: nil)))
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        XCTAssertEqual(file.consumeAtLaunch(now: t0).previous, .unknown)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        XCTAssertEqual(file.consumeAtLaunch(now: t0).previous, .notClosed(ageSeconds: 0, memoryMB: nil, generation: 2),
                       "toujours armé : constat possible au lancement suivant")
    }

    /// Aucune donnée personnelle possible dans le fichier : seulement des champs fermés.
    func testFileHoldsOnlyClosedFields() throws {
        let file = DiagnosticSessionFile(folder: folder)
        file.write(DiagnosticSessionState(generation: 9, state: .armed, updatedAt: t0, memoryMB: 300))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["schemaVersion", "generation", "state", "updatedAt", "memoryMB"])
    }

    /// B2 : une écriture ratée ne change pas l'automate ; la notification suivante refait la transition.
    func testFailedWriteIsRetriedByTheNextNotification() {
        var m = DiagnosticSessionMachine()
        let armed = m.next(.foreground, now: t0, memoryMB: nil)
        XCTAssertEqual(armed?.generation, 1)
        XCTAssertFalse(m.armed, "rien d'adopté avant l'écriture")
        XCTAssertEqual(m.next(.foreground, now: t0, memoryMB: nil)?.generation, 1, "didBecomeActive refait l'armement")
        m.commit(armed!)
        XCTAssertTrue(m.armed)
        let closed = m.next(.background, now: t0, memoryMB: nil)
        XCTAssertEqual(closed?.state, .closed)
        XCTAssertNotNil(m.next(.background, now: t0, memoryMB: nil), "clôture ratée : un second fond réessaie")
        m.commit(closed!)
        XCTAssertNil(m.next(.background, now: t0, memoryMB: nil))
    }

    /// B3 : un fichier trop gros est refusé avant lecture ; une clé inconnue rend l'état invalide.
    func testOversizedOrUnknownKeyIsUnknown() throws {
        let file = DiagnosticSessionFile(folder: folder)
        try Data(count: DiagnosticSessionFile.maxBytes + 1).write(to: file.url)
        XCTAssertEqual(file.read(), .unreadable)
        XCTAssertEqual(file.consumeAtLaunch(now: t0).previous, .unknown)
        try Data(#"{"schemaVersion":1,"generation":1,"state":"armed","updatedAt":"2026-11-25T00:00:00Z","titre":"x"}"#.utf8).write(to: file.url)
        XCTAssertEqual(file.consumeAtLaunch(now: t0).previous, .unknown)
    }


    /// B3 : un lien symbolique n'est pas suivi ; B4 : l'écriture ne recrée jamais un dossier disparu.
    func testSymlinkIsRefusedAndMissingFolderIsNotRecreated() throws {
        let file = DiagnosticSessionFile(folder: folder)
        let target = folder.appendingPathComponent("cible.json")
        try Data(#"{"schemaVersion":1,"generation":1,"state":"armed","updatedAt":"2026-11-25T00:00:00Z"}"#.utf8).write(to: target)
        try fm.createSymbolicLink(at: file.url, withDestinationURL: target)
        XCTAssertEqual(file.read(), .unreadable)
        try fm.removeItem(at: folder)
        XCTAssertFalse(file.write(DiagnosticSessionState(generation: 1, state: .armed, updatedAt: t0, memoryMB: nil)))
        XCTAssertFalse(fm.fileExists(atPath: folder.path), "dossier non recréé (il perdrait son exclusion de sauvegarde)")
    }


    /// B3 (passage 3) : un tube nommé à la place du fichier ne bloque pas la lecture ; il est « illisible ».
    func testNamedPipeIsUnreadableWithoutBlocking() throws {
        let file = DiagnosticSessionFile(folder: folder)
        XCTAssertEqual(mkfifo(file.url.path, 0o600), 0)
        let started = Date()
        XCTAssertEqual(file.read(), .unreadable)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        XCTAssertEqual(file.consumeAtLaunch(now: t0).previous, .unknown)
    }

}
