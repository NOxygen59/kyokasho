// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
@testable import ReaderCore

/// Restauration (#51, C1) sur des dossiers synthétiques : la bibliothèque sauvegardée remplace l'actuelle, les modèles
/// de l'appareil sont gardés, les réglages rétablis ; une panne à chaque étape reprend au lancement suivant.
final class LibraryRestoreTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kyokasho-restore-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        LibraryRestore.checkpoint = nil
        try? FileManager.default.removeItem(at: root)
    }

    private func put(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Sauvegarde d'une bibliothèque « source » (2 notes), préparée dans `support` (bibliothèque actuelle différente).
    private func prepare(_ support: URL) throws -> URL {
        let src = root.appendingPathComponent("source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: src.appendingPathComponent("kyokasho.sqlite").path)
        try pool.write { try $0.execute(sql: "CREATE TABLE note (body TEXT); INSERT INTO note VALUES ('sauvée'), ('aussi')") }
        try put("pdf sauvé", src.appendingPathComponent("Kyokasho/Documents/a.pdf"))
        try put("lecture sauvée", src.appendingPathComponent("Analysis/a/ovisocr2-0.md"))
        try put("{\"sauvé\":1}", src.appendingPathComponent("definition-translations.json"))
        let prefs = src.appendingPathComponent("preferences.plist")
        try PropertyListSerialization.data(fromPropertyList: ["theme.id": "sepia"], format: .binary, options: 0).write(to: prefs)
        let zip = root.appendingPathComponent("s-\(UUID().uuidString).kyokasho-sauvegarde")
        try LibraryBackup.write(.init(databases: [("kyokasho/kyokasho.sqlite", pool)],
                                      folders: [("kyokasho", src.appendingPathComponent("Kyokasho")), ("analysis", src.appendingPathComponent("Analysis"))],
                                      files: [("support/definition-translations.json", src.appendingPathComponent("definition-translations.json")),
                                              ("preferences.plist", prefs)],
                                      counts: [:], models: []), to: zip, appVersion: "test")
        // Bibliothèque actuelle de l'appareil : autre document, modèles installés, lecture IA qui doit disparaître.
        try put("pdf actuel", support.appendingPathComponent("Kyokasho/Documents/b.pdf"))
        try put("poids", support.appendingPathComponent("Kyokasho/Models/ovis/poids.bin"))
        try put("lecture actuelle", support.appendingPathComponent("Analysis/b/ovisocr2-0.md"))
        try put("{\"actuel\":1}", support.appendingPathComponent("definition-translations.json"))
        let id = UUID().uuidString
        _ = try LibraryBackup.open(zip, into: LibraryRestore.stagingURL(support: support, id: id))
        _ = try LibraryRestore.writeMarker(support: support, id: id, backupName: zip.lastPathComponent)
        return zip
    }

    private func state(_ support: URL, prefs: [String: Any]?) throws -> [String] {
        let fm = FileManager.default
        /// Fichiers seulement (les dossiers suivent).
        func list(_ url: URL) -> [String] {
            (fm.enumerator(atPath: url.path)?.compactMap { $0 as? String } ?? []).filter { name in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.appendingPathComponent(name).path, isDirectory: &isDir) && !isDir.boolValue
            }.sorted()
        }
        let notes = try DatabaseQueue(path: support.appendingPathComponent("Kyokasho/kyokasho.sqlite").path)
            .read { try String.fetchAll($0, sql: "SELECT body FROM note") }
        return ["kyokasho \(list(support.appendingPathComponent("Kyokasho")))",
                "analysis \(list(support.appendingPathComponent("Analysis")))",
                "traductions \(try String(contentsOf: support.appendingPathComponent("definition-translations.json")))",
                "notes \(notes)", "réglages \(prefs?["theme.id"] as? String ?? "-")",
                "reste \(((try? fm.contentsOfDirectory(atPath: support.path)) ?? []).sorted())"]
    }

    private let expected = [
        "kyokasho [\"Documents/a.pdf\", \"Models/ovis/poids.bin\", \"kyokasho.sqlite\"]",
        "analysis [\"a/ovisocr2-0.md\"]", "traductions {\"sauvé\":1}", "notes [\"sauvée\", \"aussi\"]", "réglages sepia",
        "reste [\"Analysis\", \"Kyokasho\", \"definition-translations.json\"]"]

    func testRestoreReplacesLibraryKeepsModelsAndPreferences() throws {
        let support = root.appendingPathComponent("support")
        _ = try prepare(support)
        var prefs: [String: Any]?
        let outcome = try LibraryRestore.apply(support: support, analysis: support.appendingPathComponent("Analysis")) { prefs = $0 }
        guard case .restored = outcome else { return XCTFail("\(outcome)") }
        XCTAssertNil(try LibraryRestore.pending(support: support))
        XCTAssertEqual(try state(support, prefs: prefs), expected)
        // Sans marqueur : rien à faire.
        XCTAssertEqual(try LibraryRestore.apply(support: support, analysis: support.appendingPathComponent("Analysis")) { _ in }, .nothing)
    }

    func testPowerCutAtEveryStepResumesAtNextLaunch() throws {
        let points = ["aside.kyokasho", "installed.kyokasho", "aside.analysis", "installed.analysis",
                      "aside.support/definition-translations.json", "installed.support/definition-translations.json",
                      "models", "preferences", "marked", "cleaned"]
        for point in points {
            let support = root.appendingPathComponent("support-\(points.firstIndex(of: point)!)")
            _ = try prepare(support)
            LibraryRestore.checkpoint = { if $0 == point { throw CocoaError(.fileWriteUnknown) } }
            // Les réglages déjà rétablis avant la coupure le restent (l'app les écrit tout de suite).
            var prefs: [String: Any]?
            XCTAssertThrowsError(try LibraryRestore.apply(support: support, analysis: support.appendingPathComponent("Analysis")) { prefs = $0 }, point)
            XCTAssertNotNil(try LibraryRestore.pending(support: support), point)
            LibraryRestore.checkpoint = nil
            try LibraryRestore.apply(support: support, analysis: support.appendingPathComponent("Analysis")) { prefs = $0 }
            XCTAssertEqual(try state(support, prefs: prefs), expected, point)
        }
    }

    /// Revue Codex de e777c68 : un marqueur illisible arrête tout, il n'est jamais pris pour « rien à restaurer ».
    func testUnreadableMarkerStopsInsteadOfOpeningAnIncompleteLibrary() throws {
        let support = root.appendingPathComponent("support")
        _ = try prepare(support)
        try Data("{abîmé".utf8).write(to: LibraryRestore.markerURL(support: support))
        XCTAssertThrowsError(try LibraryRestore.pending(support: support))
        XCTAssertThrowsError(try LibraryRestore.apply(support: support, analysis: support.appendingPathComponent("Analysis")) { _ in })
        XCTAssertEqual(try String(contentsOf: support.appendingPathComponent("Kyokasho/Documents/b.pdf")), "pdf actuel")
    }

    /// Nettoyage raté : bibliothèque restaurée utilisable, marqueur gardé ; au lancement suivant, seul le nettoyage est
    /// refait, sans réappliquer les réglages de la sauvegarde.
    func testFailedCleanupKeepsMarkerAndRetriesWithoutReapplyingPreferences() throws {
        let support = root.appendingPathComponent("support")
        _ = try prepare(support)
        LibraryRestore.checkpoint = { if $0 == "cleanup" { throw CocoaError(.fileWriteNoPermission) } }
        var prefs: [String: Any]?
        let first = try LibraryRestore.apply(support: support, analysis: support.appendingPathComponent("Analysis")) { prefs = $0 }
        guard case .cleanupPending = first else { return XCTFail("\(first)") }
        XCTAssertEqual(try state(support, prefs: prefs).prefix(5), expected.prefix(5))
        XCTAssertEqual(try LibraryRestore.pending(support: support)?.installed, true)
        LibraryRestore.checkpoint = nil
        var reapplied = false
        let second = try LibraryRestore.apply(support: support, analysis: support.appendingPathComponent("Analysis")) { _ in reapplied = true }
        guard case .restored = second else { return XCTFail("\(second)") }
        XCTAssertFalse(reapplied)
        XCTAssertEqual(try state(support, prefs: prefs), expected)
    }

    func testCancelLeavesCurrentLibraryUntouched() throws {
        let support = root.appendingPathComponent("support")
        _ = try prepare(support)
        LibraryRestore.cancel(support: support)
        XCTAssertNil(try LibraryRestore.pending(support: support))
        XCTAssertEqual(try String(contentsOf: support.appendingPathComponent("Kyokasho/Documents/b.pdf")), "pdf actuel")
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("RestoreStaging").path + "/x"))
    }

    /// Une bibliothèque sans traductions ni lectures IA doit effacer celles de la bibliothèque remplacée,
    /// y compris si l'app s'arrête après leur mise de côté. Les autres fichiers de support restent intacts.
    func testAbsentOptionalDataDoesNotLeakFromReplacedLibrary() throws {
        for cut in [nil, "aside.support/definition-translations.json"] as [String?] {
            let support = root.appendingPathComponent(UUID().uuidString)
            _ = try prepare(support)
            let marker = try XCTUnwrap(LibraryRestore.pending(support: support))
            let staging = LibraryRestore.stagingURL(support: support, id: marker.id)
            try FileManager.default.removeItem(at: staging.appendingPathComponent("support/definition-translations.json"))
            try FileManager.default.removeItem(at: staging.appendingPathComponent("analysis"))
            _ = try LibraryRestore.writeMarker(support: support, id: marker.id, backupName: marker.backupName)
            try put("hors bibliothèque", support.appendingPathComponent("unrelated.txt"))
            if let cut {
                LibraryRestore.checkpoint = { if $0 == cut { throw CocoaError(.fileWriteUnknown) } }
                XCTAssertThrowsError(try LibraryRestore.apply(support: support, analysis: support.appendingPathComponent("Analysis")) { _ in })
                LibraryRestore.checkpoint = nil
            }
            try LibraryRestore.apply(support: support, analysis: support.appendingPathComponent("Analysis")) { _ in }
            XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("definition-translations.json").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("Analysis").path))
            XCTAssertEqual(try String(contentsOf: support.appendingPathComponent("unrelated.txt")), "hors bibliothèque")
            XCTAssertEqual(try String(contentsOf: support.appendingPathComponent("Kyokasho/Models/ovis/poids.bin")), "poids")
            XCTAssertNil(try LibraryRestore.pending(support: support))
        }
    }
}
