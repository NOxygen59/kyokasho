// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import DiagnosticKit

/// PLAN-DIAG-001 E2c : travaux suivis (types fermés et `op`), projection bornée et révisée, rapportée au constat.
final class DiagnosticOngoingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_764_000_000)
    private var folder: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        folder = fm.temporaryDirectory.appendingPathComponent("ongoing-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: folder) }

    func testRegistryKeepsOrderRevisionsAndBounds() {
        var r = DiagnosticOngoingRegistry()
        let a = UUID(), b = UUID()
        let s1 = r.begin(a, kind: .sauvegarde, op: DiagnosticOperation(raw: 11))
        let s2 = r.begin(b, kind: .importPDF, op: DiagnosticOperation(raw: 22))
        XCTAssertEqual(s2.entries.map(\.op), [11, 22])
        XCTAssertGreaterThan(s2.revision, s1.revision)
        XCTAssertNil(r.end(UUID()), "travail non suivi")
        let s3 = r.end(a)
        XCTAssertEqual(s3?.entries.map(\.op), [22], "fin (annulée ou non) : retiré")
        for i in 0..<10 { _ = r.begin(UUID(), kind: .importCBZ, op: DiagnosticOperation(raw: UInt32(100 + i))) }
        XCTAssertEqual(r.snapshot.entries.count, DiagnosticOngoing.limit)
        XCTAssertTrue(r.snapshot.truncated, "tronquée : connaissance limitée")
    }

    func testMachineIgnoresStaleProjectionAndOnlyWritesWhenArmed() {
        var m = DiagnosticSessionMachine()
        let fresh = DiagnosticOngoing(entries: [.init(kind: .sauvegarde, op: 5)], revision: 3)
        XCTAssertNil(m.next(ongoing: fresh, now: t0, memoryMB: nil), "pas armée : rien à écrire")
        m.commit(ongoing: fresh)
        let armed = m.handle(.foreground, now: t0, memoryMB: nil)
        XCTAssertEqual(armed?.ongoing, [.init(kind: .sauvegarde, op: 5)], "réarmement : projection reportée")
        let stale = DiagnosticOngoing(entries: [], revision: 2)
        XCTAssertNil(m.next(ongoing: stale, now: t0, memoryMB: nil), "publication réordonnée ignorée")
        let closed = m.handle(.background, now: t0, memoryMB: nil)
        XCTAssertNil(closed?.ongoing, "session close : aucun travail écrit")
    }

    func testInterruptedSessionReportsOriginalOps() {
        let file = DiagnosticSessionFile(folder: folder)
        let ongoing = DiagnosticOngoing(entries: [.init(kind: .importCBZ, op: 0xabc), .init(kind: .sauvegarde, op: 0xdef)],
                                        truncated: true, revision: 9)
        XCTAssertTrue(file.write(DiagnosticSessionState(generation: 4, state: .armed, updatedAt: t0, memoryMB: 300, ongoing: ongoing)))
        let launch = file.consumeAtLaunch(now: t0.addingTimeInterval(30))
        XCTAssertEqual(launch.ongoing.map(\.op), [0xabc, 0xdef])
        XCTAssertTrue(launch.ongoingTruncated)
        XCTAssertEqual(file.consumeAtLaunch(now: t0.addingTimeInterval(60)).ongoing, [], "consommé : plus rien")
    }

    func testInvalidOngoingIsUnknown() throws {
        let file = DiagnosticSessionFile(folder: folder)
        let base = #""schemaVersion":1,"generation":1,"state":"armed","updatedAt":"2026-11-25T00:00:00Z""#
        for ongoing in [#"[{"kind":"plantage","op":1}]"#, #"[{"kind":"sauvegarde","op":0}]"#,
                        #"[{"kind":"sauvegarde","op":1,"titre":"x"}]"#,
                        "[" + Array(repeating: #"{"kind":"sauvegarde","op":1}"#, count: 9).joined(separator: ",") + "]"] {
            try Data("{\(base),\"ongoing\":\(ongoing)}".utf8).write(to: file.url)
            XCTAssertEqual(file.consumeAtLaunch(now: t0).previous, .unknown, ongoing)
        }
    }

    func testStateHoldsOnlyClosedOngoingFields() throws {
        let file = DiagnosticSessionFile(folder: folder)
        file.write(DiagnosticSessionState(generation: 2, state: .armed, updatedAt: t0, memoryMB: nil,
                                          ongoing: DiagnosticOngoing(entries: [.init(kind: .conversionCBZ, op: 7)], revision: 1)))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
        let entries = try XCTUnwrap(json["ongoing"] as? [[String: Any]])
        XCTAssertEqual(Set(entries[0].keys), ["kind", "op"])
        XCTAssertEqual(entries[0]["kind"] as? String, "conversion_cbz")
    }
}
