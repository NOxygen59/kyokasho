// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import DiagnosticKit

/// Réunion DIAG du 25/11 (contrat E1, points 1 et 8) : la mise à l'écart DEC-07 ne fait jamais d'effacement ni
/// d'écrasement, et un échec laisse tout bloqué.
final class DiagnosticFileMigrationTests: XCTestCase {
    /// Dossier simulé : contenu par nom, déplacements ratés à la demande, noms illisibles.
    private final class Disk {
        var files: [String: String]
        var failingMoves: Set<String> = []
        var unreadable: Set<String> = []
        init(_ files: [String: String]) { self.files = files }

        var operations: DiagnosticFileMigration.Operations {
            .init(presence: { [unowned self] name in
                if self.unreadable.contains(name) { return .unknown }
                return self.files[name] == nil ? .absent : .present
            }, move: { [unowned self] from, to in
                guard !self.failingMoves.contains(from), self.files[to] == nil, let data = self.files[from] else { return false }
                self.files[to] = data
                self.files[from] = nil
                return true
            })
        }
    }

    func testFreshInstallIsReady() {
        let disk = Disk([:])
        XCTAssertEqual(DiagnosticFileMigration.run(storedRevision: 0, operations: disk.operations), .ready)
        XCTAssertTrue(disk.files.isEmpty)
    }

    func testOldFilesAreIsolatedWithoutLoss() {
        let disk = Disk(["journal.txt": "SENTINELLE-TITRE", "journal.1.txt": "SENTINELLE-CHEMIN", "energie.csv": "SENTINELLE-MODELE"])
        XCTAssertEqual(DiagnosticFileMigration.run(storedRevision: 0, operations: disk.operations), .ready)
        XCTAssertEqual(disk.files, ["journal-avant-diagnostics.txt": "SENTINELLE-TITRE",
                                    "journal-avant-diagnostics-2.txt": "SENTINELLE-CHEMIN",
                                    "energie-avant-diagnostics.csv": "SENTINELLE-MODELE"])
    }

    func testEachFailedMoveBlocksAndTouchesNothingElse() {
        for failing in ["journal.txt", "journal.1.txt", "energie.csv"] {
            let disk = Disk(["journal.txt": "a", "journal.1.txt": "b", "energie.csv": "c"])
            disk.failingMoves = [failing]
            XCTAssertEqual(DiagnosticFileMigration.run(storedRevision: 0, operations: disk.operations), .blocked, failing)
            XCTAssertNotNil(disk.files[failing], "\(failing) reste en place, rien n'est effacé")
            XCTAssertEqual(disk.files.count, 3, "aucun fichier perdu ni dupliqué (\(failing))")
        }
    }

    func testUnreadableIsNotAbsence() {
        let disk = Disk(["energie.csv": "c"])
        disk.unreadable = ["journal.txt"]
        XCTAssertEqual(DiagnosticFileMigration.run(storedRevision: 0, operations: disk.operations), .blocked)
        XCTAssertEqual(disk.files, ["energie-avant-diagnostics.csv": "c"], "les autres actifs sont quand même isolés")
    }

    func testOccupiedTargetsAreNeverOverwritten() {
        let disk = Disk(["journal.txt": "nouveau", "journal-avant-diagnostics.txt": "ISOLÉ-1", "journal-avant-diagnostics-2.txt": "ISOLÉ-2"])
        XCTAssertEqual(DiagnosticFileMigration.run(storedRevision: 0, operations: disk.operations), .ready)
        XCTAssertEqual(disk.files["journal-avant-diagnostics.txt"], "ISOLÉ-1")
        XCTAssertEqual(disk.files["journal-avant-diagnostics-2.txt"], "ISOLÉ-2")
        XCTAssertEqual(disk.files["journal-avant-diagnostics-3.txt"], "nouveau")
    }

    func testAllIsolatedNamesTakenBlocks() {
        var files = ["journal.txt": "x"]
        for name in DiagnosticFileMigration.isolatedNames(.journal) { files[name] = "pris" }
        let disk = Disk(files)
        XCTAssertEqual(DiagnosticFileMigration.run(storedRevision: 0, operations: disk.operations), .blocked)
        XCTAssertEqual(disk.files["journal.txt"], "x")
    }

    /// Arrêt entre deux déplacements : la relance reprend sans retraiter ce qui est déjà isolé.
    func testResumeAfterPartialRun() {
        let disk = Disk(["journal.txt": "a", "energie.csv": "c"])
        disk.failingMoves = ["energie.csv"]
        XCTAssertEqual(DiagnosticFileMigration.run(storedRevision: 0, operations: disk.operations), .blocked)
        disk.failingMoves = []
        XCTAssertEqual(DiagnosticFileMigration.run(storedRevision: 0, operations: disk.operations), .ready)
        XCTAssertEqual(disk.files, ["journal-avant-diagnostics.txt": "a", "energie-avant-diagnostics.csv": "c"])
    }

    /// L'ancien « 2 » (version intermédiaire f067d83) ne vaut pas migration ; seule la révision 3 la saute.
    func testRevisions() {
        let disk = Disk(["energie.csv": "vieux"])
        XCTAssertEqual(DiagnosticFileMigration.run(storedRevision: 2, operations: disk.operations), .ready)
        XCTAssertEqual(disk.files, ["energie-avant-diagnostics.csv": "vieux"])
        let later = Disk(["journal.txt": "neuf"])
        XCTAssertEqual(DiagnosticFileMigration.run(storedRevision: DiagnosticFileMigration.revision, operations: later.operations), .ready)
        XCTAssertEqual(later.files, ["journal.txt": "neuf"], "migration déjà faite : rien n'est déplacé")
        XCTAssertEqual(DiagnosticFileMigration.run(storedRevision: 99, operations: later.operations), .blocked)
    }
}
