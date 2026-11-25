// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import DiagnosticKit

/// PLAN-DIAG-001, E1 : contrat d'événement, récepteur, confidentialité à la source.
final class DiagnosticKitTests: XCTestCase {
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private let date = Date(timeIntervalSince1970: 1_764_000_000)

    /// Collecteur sûr pour les tests (un par test : pas de récepteur global partagé).
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [DiagnosticEvent] = []
        func add(_ e: DiagnosticEvent) { lock.withLock { items.append(e) } }
        var all: [DiagnosticEvent] { lock.withLock { items } }
    }

    func testEventLineHasTheTypedFieldsOnOneLine() {
        let op = DiagnosticOperation(raw: 0xabc), parent = DiagnosticOperation(raw: 0x1)
        let e = DiagnosticEvent(.erreur, .export, "écriture du pdf", outcome: .erreur, cause: .ecriture, op: op, parent: parent,
                                durationMs: 42, memoryMB: 310, counts: [DiagnosticCount("pages", 12)], ref: DiagnosticDocumentRef(text: "k3x9qa"))
        let line = DiagnosticLine.event(e, at: date, timeZone: paris)
        XCTAssertTrue(line.hasSuffix("[erreur] [export] op=00000abc parent=00000001 étape=écriture_du_pdf issue=erreur cause=ecriture t=42ms mem=310Mo doc=k3x9qa pages=12"), line)
        XCTAssertFalse(line.contains("\n"))
    }

    func testLegacyLineKeepsTheOldFormat() {
        let line = DiagnosticLine.legacy(.alerte, area: "lecteur", message: "a\nb\r\nc", at: date, timeZone: paris)
        XCTAssertTrue(line.hasSuffix("[alerte] [lecteur] a b c"), line)
    }

    func testOldAreasMapToClosedZones() {
        XCTAssertEqual(DiagnosticZone.legacy("import"), .importation)
        XCTAssertEqual(DiagnosticZone.legacy("ocr-scroll"), .ocrScroll)
        XCTAssertEqual(DiagnosticZone.legacy("mémoire"), .memoire)
        XCTAssertEqual(DiagnosticZone.memoire.rawValue, "mémoire", "nom lu par le moniteur d'activité")
        XCTAssertEqual(DiagnosticZone.legacy("inconnue-xyz"), .app)
        XCTAssertEqual(Set(DiagnosticZone.allCases.map(\.rawValue)).count, DiagnosticZone.allCases.count)
    }

    func testErrorKeepsOnlyDomainAndCode() {
        let secret = NSError(domain: NSCocoaErrorDomain, code: 513,
                             userInfo: [NSLocalizedDescriptionKey: "« SENTINELLE-TITRE » /dossier/SENTINELLE-CHEMIN.pdf",
                                        NSFilePathErrorKey: "/var/mobile/SENTINELLE-CHEMIN.pdf"])
        let cause = DiagnosticCause.from(secret)
        XCTAssertEqual(cause.text, "NSCocoaErrorDomain#513")
        XCTAssertEqual(DiagnosticCause.from(CancellationError()), .annulee)
        XCTAssertEqual(DiagnosticCause.systeme(domain: "a b\nc/d", code: 1).text, "autre#1")
        XCTAssertEqual(DiagnosticCause.systeme(domain: "SENTINELLE-TITRE", code: 2).text, "autre#2", "domaine choisi à la main")
        XCTAssertEqual(DiagnosticCause.systeme(domain: "Kyokasho.ExportError", code: 3).text, "Kyokasho.ExportError#3")
        XCTAssertEqual(DiagnosticCause.systeme(domain: NSPOSIXErrorDomain, code: 2).text, "NSPOSIXErrorDomain#2")
    }

    func testNothingHappensWithoutSinkAndInfoNeedsDetailedMode() {
        let center = DiagnosticCenter(), box = Box()
        var built = 0
        center.emit(.erreur, { built += 1; return DiagnosticEvent(.erreur, .app, "x") }())
        XCTAssertEqual(built, 0, "sans récepteur, l'événement n'est même pas construit")
        XCTAssertTrue(center.install(sink: { box.add($0) }, salt: 7))
        center.emit(.info, { built += 1; return DiagnosticEvent(.info, .app, "étape") }())
        XCTAssertEqual(built, 0, "info filtré avant construction hors mode diagnostic")
        center.emit(.alerte, DiagnosticEvent(.info, .app, "alerte"))
        center.setDetailed(true)
        center.emit(.info, DiagnosticEvent(.info, .app, "étape"))
        XCTAssertEqual(box.all.map(\.level), [.alerte, .info], "le niveau passé à emit fait foi")
    }

    func testSecondSinkIsRefused() {
        let center = DiagnosticCenter(), first = Box(), second = Box()
        XCTAssertTrue(center.install(sink: { first.add($0) }, salt: 1))
        XCTAssertFalse(center.install(sink: { second.add($0) }, salt: 2))
        center.emit(.erreur, DiagnosticEvent(.erreur, .app, "x"))
        XCTAssertEqual(first.all.count, 1)
        XCTAssertTrue(second.all.isEmpty)
    }

    func testReentrantEmissionIsDroppedAndCounted() {
        let center = DiagnosticCenter(), box = Box()
        center.install(sink: { [center] event in
            box.add(event)
            center.emit(.erreur, DiagnosticEvent(.erreur, .journal, "écho"))
        }, salt: 1)
        center.emit(.erreur, DiagnosticEvent(.erreur, .app, "x"))
        XCTAssertEqual(box.all.count, 1)
        XCTAssertEqual(center.takeReentrantDrops(), 1)
        XCTAssertEqual(center.takeReentrantDrops(), 0)
    }

    func testConcurrentEmissionsAllArrive() {
        let center = DiagnosticCenter(), box = Box()
        center.install(sink: { box.add($0) }, salt: 1)
        DispatchQueue.concurrentPerform(iterations: 500) { i in
            center.emit(.erreur, DiagnosticEvent(.erreur, .app, "x", counts: [DiagnosticCount("i", i)]))
            if i % 50 == 0 { center.setDetailed(i % 100 == 0) }
        }
        XCTAssertEqual(box.all.count, 500)
    }

    func testDocumentRefIsSaltedShortAndStable() {
        let id = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
        let a = DiagnosticRef.short(id, salt: 1), b = DiagnosticRef.short(id, salt: 2)
        XCTAssertEqual(a.count, 6)
        XCTAssertEqual(a, DiagnosticRef.short(id, salt: 1))
        XCTAssertNotEqual(a, b, "le sel change la référence d'une installation à l'autre")
        XCTAssertFalse(id.contains(a), "pas un morceau de l'empreinte")
    }

    func testMonitorLineCarriesOpAndStep() {
        let line = DiagnosticLine.monitor(.info, zone: .cpu, op: DiagnosticOperation(raw: 0x2a), step: "releve_cpu",
                                          measures: "cpu=12%\nfil#1:3%", at: date, timeZone: paris)
        XCTAssertTrue(line.hasSuffix("[info] [cpu] op=0000002a étape=releve_cpu issue=etape cpu=12% fil#1:3%"), line)
    }

    func testJournalPolicy() {
        XCTAssertFalse(DiagnosticJournalPolicy.shouldRotate(currentBytes: 5_000_000))
        XCTAssertTrue(DiagnosticJournalPolicy.shouldRotate(currentBytes: 5_000_001))
        XCTAssertTrue(DiagnosticJournalPolicy.needsQuarantine(storedFormat: 0, journalExists: true))
        XCTAssertFalse(DiagnosticJournalPolicy.needsQuarantine(storedFormat: 0, journalExists: false))
        XCTAssertFalse(DiagnosticJournalPolicy.needsQuarantine(storedFormat: 2, journalExists: true))
    }

    /// Sentinelles : un titre, un texte, un chemin et un nom de modèle factices passés partout où un événement peut
    /// porter une valeur venue de l'app n'apparaissent jamais dans la ligne.
    func testSentinelsNeverReachTheLine() {
        let sentinels = ["SENTINELLE-TITRE", "SENTINELLE-TEXTE", "SENTINELLE-CHEMIN", "SENTINELLE-MODELE"]
        let error = NSError(domain: "Kyokasho.Export", code: 3, userInfo: [NSLocalizedDescriptionKey: sentinels.joined(separator: " ")])
        let ref = DiagnosticDocumentRef(text: DiagnosticRef.short(sentinels[0], salt: 99))
        let e = DiagnosticEvent(.erreur, .export, "export", outcome: .erreur, cause: .from(error), op: .new(), ref: ref)
        let hostile = NSError(domain: sentinels[0], code: 1)
        XCTAssertFalse(DiagnosticCause.from(hostile).text.contains(sentinels[0]))
        let line = DiagnosticLine.event(e, at: date)
        for s in sentinels { XCTAssertFalse(line.contains(s), "\(s) dans « \(line) »") }
    }
}
