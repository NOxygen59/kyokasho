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
}
