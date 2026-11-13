// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
import ZIPFoundation
@testable import ReaderCore

/// Sauvegarde complète (#51, C1) sur une bibliothèque synthétique : aller-retour, refus des sauvegardes altérées et
/// des liens symboliques, base copiée par l'API SQLite alors qu'elle est ouverte en WAL.
final class LibraryBackupTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kyokasho-backup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func write(_ text: String, _ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    /// Base sur disque en WAL (comme l'app), avec une écriture pas encore reportée dans le fichier principal.
    private func liveDatabase() throws -> DatabasePool {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("live"), withIntermediateDirectories: true)
        let pool = try DatabasePool(path: root.appendingPathComponent("live/kyokasho.sqlite").path)
        try pool.write { db in
            try db.execute(sql: "CREATE TABLE note (id INTEGER PRIMARY KEY, body TEXT)")
            try db.execute(sql: "INSERT INTO note (body) VALUES ('教科書'), ('deuxième')")
        }
        return pool
    }

    private func source(_ pool: DatabasePool) throws -> LibraryBackup.Source {
        _ = try write("pdf", "live/Documents/a.pdf")
        _ = try write("lecture", "live/Analysis/a/ovisocr2-0.md")
        _ = try write("ignoré", "live/Analysis/.DS_Store")
        let lexicon = try write("{}", "live/lexique.json")
        return LibraryBackup.Source(databases: [("kyokasho/kyokasho.sqlite", pool)],
                                    folders: [("documents", root.appendingPathComponent("live/Documents")),
                                              ("analysis", root.appendingPathComponent("live/Analysis")),
                                              ("absent", root.appendingPathComponent("live/Nothing"))],
                                    files: [("kyokasho/lexique.json", lexicon)],
                                    counts: ["documents": 1, "notes": 2], models: ["OvisOCR2"])
    }

    func testRoundTripKeepsDatabaseFilesAndManifest() throws {
        let pool = try liveDatabase()
        let zip = root.appendingPathComponent("s.kyokasho-sauvegarde")
        try LibraryBackup.write(try source(pool), to: zip, appVersion: "test")
        let out = root.appendingPathComponent("open")
        let manifest = try LibraryBackup.open(zip, into: out)
        XCTAssertEqual(Set(manifest.files.keys), ["kyokasho/kyokasho.sqlite", "kyokasho/lexique.json",
                                                   "documents/a.pdf", "analysis/a/ovisocr2-0.md"])
        XCTAssertEqual(manifest.counts, ["documents": 1, "notes": 2])
        XCTAssertEqual(manifest.models, ["OvisOCR2"])
        let copy = try DatabaseQueue(path: out.appendingPathComponent("kyokasho/kyokasho.sqlite").path)
        XCTAssertEqual(try copy.read { try String.fetchAll($0, sql: "SELECT body FROM note ORDER BY id") }, ["教科書", "deuxième"])
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("analysis/a/ovisocr2-0.md")), "lecture")
    }

    func testTamperedOrForeignBackupsAreRefused() throws {
        let zip = root.appendingPathComponent("s.kyokasho-sauvegarde")
        try LibraryBackup.write(try source(try liveDatabase()), to: zip, appVersion: "test")
        // Fichier ajouté hors fiche.
        try Archive(url: zip, accessMode: .update).addEntry(with: "documents/b.pdf", type: .file, uncompressedSize: Int64(1)) { (_: Int64, _: Int) in Data("x".utf8) }
        XCTAssertThrowsError(try LibraryBackup.open(zip, into: root.appendingPathComponent("a")))
        // Chemin qui sort du dossier.
        let evil = root.appendingPathComponent("evil.kyokasho-sauvegarde")
        try LibraryBackup.write(try source(try DatabasePool(path: root.appendingPathComponent("e.sqlite").path)), to: evil, appVersion: "test")
        try Archive(url: evil, accessMode: .update).addEntry(with: "../evil.md", type: .file, uncompressedSize: Int64(1)) { (_: Int64, _: Int) in Data("x".utf8) }
        XCTAssertThrowsError(try LibraryBackup.open(evil, into: root.appendingPathComponent("b")))
        // Pas un zip.
        let text = try write("pas un zip", "faux.kyokasho-sauvegarde")
        XCTAssertThrowsError(try LibraryBackup.open(text, into: root.appendingPathComponent("c")))
    }

    func testAlteredFileOrDatabaseIsRefused() throws {
        for target in ["documents/a.pdf", "kyokasho/kyokasho.sqlite"] {
            let zip = root.appendingPathComponent("\(UUID().uuidString).kyokasho-sauvegarde")
            try LibraryBackup.write(try source(try liveDatabase()), to: zip, appVersion: "test")
            let archive = try Archive(url: zip, accessMode: .update)
            try archive.remove(try XCTUnwrap(archive[target]))
            try archive.addEntry(with: target, type: .file, uncompressedSize: Int64(7)) { (_: Int64, _: Int) in Data("altéré".utf8).prefix(7) }
            XCTAssertThrowsError(try LibraryBackup.open(zip, into: root.appendingPathComponent(UUID().uuidString)), target)
            try? FileManager.default.removeItem(at: root.appendingPathComponent("live"))
        }
    }

    func testSymbolicLinksStopTheBackup() throws {
        let pool = try liveDatabase()
        var s = try source(pool)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("live/Documents/lien.pdf"),
                                                   withDestinationURL: root.appendingPathComponent("live/lexique.json"))
        XCTAssertThrowsError(try LibraryBackup.write(s, to: root.appendingPathComponent("x.kyokasho-sauvegarde"), appVersion: "test"))
        s.folders = []
        s.files = [("kyokasho/../x", root.appendingPathComponent("live/lexique.json"))]
        XCTAssertThrowsError(try LibraryBackup.write(s, to: root.appendingPathComponent("y.kyokasho-sauvegarde"), appVersion: "test"))
    }

    /// Bases brutes et dossier exclu (modèles) jamais copiés depuis les dossiers.
    func testFoldersSkipRawDatabasesAndExcludedPaths() throws {
        var s = try source(try liveDatabase())
        _ = try write("brut", "live/Documents/copie.sqlite")
        _ = try write("wal", "live/Documents/copie.sqlite-wal")
        _ = try write("poids", "live/Documents/Models/ovis/poids.bin")
        s.excluded = ["documents/Models"]
        let zip = root.appendingPathComponent("s.kyokasho-sauvegarde")
        try LibraryBackup.write(s, to: zip, appVersion: "test")
        let manifest = try LibraryBackup.open(zip, into: root.appendingPathComponent("o"))
        XCTAssertFalse(manifest.files.keys.contains { $0.contains("copie.sqlite") || $0.contains("Models") }, "\(manifest.files.keys)")
    }

    /// Rotation des 10 : seules les sauvegardes de Kyōkasho sont effacées, jamais un autre fichier du dossier.
    func testRotationKeepsNewestAndNeverTouchesOtherFiles() throws {
        let folder = root.appendingPathComponent("dossier")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let s = try source(try liveDatabase())
        var names: [String] = []
        for day in 1...12 {
            let name = LibraryBackup.fileName(at: Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400))
            try LibraryBackup.write(s, to: folder.appendingPathComponent(name), appVersion: "test")
            names.append(name)
        }
        try Data("à garder".utf8).write(to: folder.appendingPathComponent("Kyokasho-faux.kyokasho-sauvegarde"))
        try Data("à garder".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        let removed = try LibraryBackup.rotate(in: folder, keep: 10)
        XCTAssertEqual(Set(removed.map(\.lastPathComponent)), Set(names.prefix(2)))
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        XCTAssertEqual(left, Set(names.suffix(10)).union(["Kyokasho-faux.kyokasho-sauvegarde", "notes.txt"]))
    }

    func testSafePaths() {
        XCTAssertTrue(LibraryBackup.safePath("analysis/a/fr-1.md"))
        for bad in ["", "/a", "a/../b", "a//b", "./a", ".cache/x", "a\\b"] { XCTAssertFalse(LibraryBackup.safePath(bad), bad) }
    }

    /// Recette 1.5.6 (4.2) : l'avancement monte sans retour en arrière et finit sur le total exact des fichiers écrits.
    func testProgressIsMonotonicAndEndsOnTheTotal() throws {
        let zip = root.appendingPathComponent("progress.kyokasho-sauvegarde")
        var calls: [(Int, Int)] = []
        try LibraryBackup.write(try source(try liveDatabase()), to: zip, appVersion: "test") { calls.append(($0, $1)) }
        let last = try XCTUnwrap(calls.last)
        XCTAssertEqual(last.0, last.1)
        XCTAssertEqual(calls.map(\.0), calls.map(\.0).sorted())
        XCTAssertTrue(calls.allSatisfy { $0.1 == last.1 })
        XCTAssertLessThanOrEqual(calls.count, 101)
        // Total = fichiers de l'archive hors manifeste.
        let manifest = try LibraryBackup.open(zip, into: root.appendingPathComponent("progress-check"))
        XCTAssertEqual(last.1, manifest.files.count)
    }
}
