// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import DiagnosticKit

/// Revue R2 E1, passage 3 : la condition d'accès DEC-07 et la rotation DEC-06 éprouvées sur de vrais fichiers, dans
/// un dossier temporaire jetable (jamais la bibliothèque réelle).
final class DiagnosticStoreTests: XCTestCase {
    private var folder: URL!
    private var store: DiagnosticStore!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        folder = fm.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        store = DiagnosticStore(folder: folder)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: folder) }

    private func write(_ name: String, _ text: String) throws { try Data(text.utf8).write(to: folder.appendingPathComponent(name)) }
    private func read(_ name: String) -> String? { (try? Data(contentsOf: folder.appendingPathComponent(name))).map { String(decoding: $0, as: UTF8.self) } }
    private var names: Set<String> { Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []) }

    /// Mise à l'écart qui échoue sur un actif : rien n'est écrit, lu ni partagé, et aucun octet ne change.
    func testBlockedStoreNeverWritesRotatesOrShares() throws {
        try write("journal.txt", "SENTINELLE-TITRE")
        try write("energie.csv", "SENTINELLE-MODELE")
        var recorded: [Int] = []
        var ops = store.fileSystemOperations()
        let realMove = ops.move
        ops.move = { from, to in from == "energie.csv" ? false : realMove(from, to) }
        XCTAssertEqual(store.migrate(storedRevision: 0, operations: ops) { recorded.append($0) }, .blocked)
        XCTAssertTrue(recorded.isEmpty, "révision non enregistrée")
        XCTAssertFalse(store.isReady)
        let before = names
        XCTAssertFalse(store.appendJournal("ligne\n", rotationBytes: 1))
        XCTAssertEqual(names, before, "ni création, ni rotation, ni en-tête")
        XCTAssertEqual(read("energie.csv"), "SENTINELLE-MODELE", "ancien relevé intact, octet pour octet")
        XCTAssertEqual(read("journal-avant-diagnostics.txt"), "SENTINELLE-TITRE", "journal isolé malgré l'échec du relevé")
        XCTAssertEqual(store.shareable(), [])
    }

    /// Avant toute migration (état initial), même chose.
    func testStoreIsBlockedBeforeMigration() {
        XCTAssertFalse(store.appendJournal("x\n"))
        XCTAssertTrue(names.isEmpty)
        XCTAssertEqual(store.shareable(), [])
    }

    func testReadyStoreWritesRotatesAndSharesOnlyActives() throws {
        try write("journal.txt", "ANCIEN")
        var recorded: [Int] = []
        XCTAssertEqual(store.migrate(storedRevision: 0) { recorded.append($0) }, .ready)
        XCTAssertEqual(recorded, [DiagnosticFileMigration.revision])
        XCTAssertEqual(read("journal-avant-diagnostics.txt"), "ANCIEN")
        XCTAssertTrue(store.appendJournal(String(repeating: "a", count: 20) + "\n", rotationBytes: 10))
        XCTAssertTrue(store.appendJournal("b\n", rotationBytes: 10), "au-delà de 10 octets : rotation")
        XCTAssertEqual(read("journal.1.txt"), String(repeating: "a", count: 20) + "\n")
        let current = try XCTUnwrap(read("journal.txt"))
        XCTAssertTrue(current.contains("Rotation du journal"))
        XCTAssertTrue(current.hasSuffix("b\n"))
        XCTAssertEqual(Set(store.shareable().map(\.lastPathComponent)), ["journal.txt", "journal.1.txt"],
                       "jamais l'ancien journal mis à l'écart")
    }

    func testEraseTouchesOnlyItsFamilyAndSizesCountIsolated() throws {
        try write("journal.txt", "12345")
        try write("journal-avant-diagnostics.txt", "123")
        try write("journal-avant-diagnostics-2.txt", "12")
        try write("energie.csv", "1234")
        try write("energie-avant-diagnostics.csv", "1")
        try write("autre-fichier.txt", "ÉTRANGER")
        XCTAssertEqual(store.sizes().journal, 10)
        XCTAssertEqual(store.sizes().energy, 5)
        store.erase(.journal)
        XCTAssertEqual(names, ["energie.csv", "energie-avant-diagnostics.csv", "autre-fichier.txt"])
        store.erase(.energy)
        XCTAssertEqual(names, ["autre-fichier.txt"])
        XCTAssertEqual(read("autre-fichier.txt"), "ÉTRANGER")
        XCTAssertFalse(store.isReady, "effacer ne débloque rien")
    }

    /// Illisible n'est pas absent (dossier sans droit de lecture).
    func testUnreadableFolderBlocks() throws {
        let locked = folder.appendingPathComponent("verrouillé", isDirectory: true)
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try write("verrouillé/journal.txt", "x")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let lockedStore = DiagnosticStore(folder: locked)
        XCTAssertEqual(lockedStore.migrate(storedRevision: 0) { _ in XCTFail("pas d'enregistrement") }, .blocked)
        XCTAssertFalse(lockedStore.isReady)
    }

    private func rotateHalf(_ data: Data, _ keep: Int) -> Data { data.suffix(keep) }

    /// Bloqué avec un ancien journal **et** un ancien précédent restés actifs : aucune rotation, aucun relevé créé.
    func testBlockedWithOldActivesNeverRotatesOrCreatesEnergy() throws {
        try write("journal.txt", String(repeating: "T", count: 50))
        try write("journal.1.txt", "SENTINELLE-PRECEDENT")
        var ops = store.fileSystemOperations()
        ops.move = { _, _ in false }
        XCTAssertEqual(store.migrate(storedRevision: 0, operations: ops) { _ in XCTFail() }, .blocked)
        XCTAssertFalse(store.appendJournal("x\n", rotationBytes: 1))
        XCTAssertFalse(store.appendEnergy("1,2,3", header: "entête", limit: 1, rotate: rotateHalf))
        XCTAssertEqual(names, ["journal.txt", "journal.1.txt"], "ni rotation, ni relevé créé")
        XCTAssertEqual(read("journal.1.txt"), "SENTINELLE-PRECEDENT")
        XCTAssertEqual(read("journal.txt"), String(repeating: "T", count: 50))
    }

    func testReadyEnergyWriterCreatesWithHeaderAndRotates() throws {
        XCTAssertEqual(store.migrate(storedRevision: 0) { _ in }, .ready)
        XCTAssertTrue(store.appendEnergy("ligne1", header: "entête", limit: 20, rotate: rotateHalf))
        XCTAssertEqual(read("energie.csv"), "entête\nligne1\n")
        XCTAssertTrue(store.appendEnergy("ligne2-plus-longue", header: "entête", limit: 20, rotate: rotateHalf))
        XCTAssertTrue(store.appendEnergy("ligne3", header: "entête", limit: 20, rotate: rotateHalf))
        let csv = try XCTUnwrap(read("energie.csv"))
        XCTAssertTrue(csv.hasSuffix("ligne3\n"))
        XCTAssertFalse(csv.hasPrefix("entête"), "rotation passée par la fonction fournie")
        XCTAssertEqual(Set(store.shareable().map(\.lastPathComponent)), ["energie.csv"])
    }

    /// Relance réelle : un premier lancement bloqué (précédent issu d'une rotation non isolable), puis une nouvelle
    /// instance sur les mêmes fichiers qui réussit sans rien perdre ni écraser.
    func testRelaunchOnSameFilesResumesWithoutLoss() throws {
        try write("journal.txt", "ANCIEN-ACTIF")
        try write("journal.1.txt", "ANCIEN-PRECEDENT")
        try write("energie.csv", "ANCIEN-CSV")
        var ops = store.fileSystemOperations()
        let real = ops.move
        ops.move = { from, to in from == "journal.1.txt" ? false : real(from, to) }
        XCTAssertEqual(store.migrate(storedRevision: 0, operations: ops) { _ in XCTFail() }, .blocked)
        let relaunched = DiagnosticStore(folder: folder)
        var recorded: [Int] = []
        XCTAssertEqual(relaunched.migrate(storedRevision: 0) { recorded.append($0) }, .ready)
        XCTAssertEqual(recorded, [3])
        XCTAssertEqual(read("journal-avant-diagnostics.txt"), "ANCIEN-ACTIF")
        XCTAssertEqual(read("journal-avant-diagnostics-2.txt"), "ANCIEN-PRECEDENT")
        XCTAssertEqual(read("energie-avant-diagnostics.csv"), "ANCIEN-CSV")
        XCTAssertEqual(names.count, 3)
        XCTAssertEqual(relaunched.shareable(), [])
    }

    /// Un effacement qui échoue (dossier en lecture seule) ne débloque rien et ne perd rien.
    func testFailedEraseKeepsBlockedAndFiles() throws {
        try write("journal.txt", "x")
        var ops = store.fileSystemOperations()
        ops.move = { _, _ in false }
        XCTAssertEqual(store.migrate(storedRevision: 0, operations: ops) { _ in }, .blocked)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        store.erase(.journal)
        XCTAssertEqual(read("journal.txt"), "x")
        XCTAssertFalse(store.isReady)
    }

    func testIsolatedNamesAreBounded() {
        let names = DiagnosticFileMigration.isolatedNames(.journal)
        XCTAssertEqual(names.count, 20)
        XCTAssertEqual(names.first, "journal-avant-diagnostics.txt")
        XCTAssertEqual(names.last, "journal-avant-diagnostics-20.txt")
        XCTAssertEqual(DiagnosticFileMigration.isolatedNames(.energy).last, "energie-avant-diagnostics-20.csv")
    }

}
