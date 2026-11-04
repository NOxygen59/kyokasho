// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest

/// Revue Codex de e777c68 : la restauration doit s'appliquer avant l'ouverture de la moindre base, quel que soit
/// l'ordre de création par SwiftUI, et un échec doit bloquer tout l'écran. Le lancement de l'app ne tourne pas dans
/// les tests Mac (cible iOS) : ces gardes vérifient l'ordre dans le code source, la logique est testée par
/// `LibraryRestoreTests`. Une vérification réelle reste à faire sur l'iPad.
final class LibraryRestoreLaunchTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/" + path).standardizedFileURL
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Dans `AppModel.init`, l'appel vient avant l'ouverture de la base de l'app (et donc avant cartes et dictionnaires,
    /// créés plus loin dans le même init).
    func testRestoreRunsBeforeAnyDatabaseIsOpened() throws {
        let model = try source("AppModel.swift")
        let initStart = try XCTUnwrap(model.range(of: "    init() {"))
        let apply = try XCTUnwrap(model.range(of: "LibraryBackupService.applyPendingRestoreOnce()", range: initStart.upperBound..<model.endIndex))
        let open = try XCTUnwrap(model.range(of: "AppDatabase.open(at:", range: initStart.upperBound..<model.endIndex))
        let review = try XCTUnwrap(model.range(of: "ReviewModel(appDatabase:", range: initStart.upperBound..<model.endIndex))
        let dictionary = try XCTUnwrap(model.range(of: "DictionaryModel(appDatabase:", range: initStart.upperBound..<model.endIndex))
        XCTAssertLessThan(apply.lowerBound, open.lowerBound)
        XCTAssertLessThan(apply.lowerBound, review.lowerBound)
        XCTAssertLessThan(apply.lowerBound, dictionary.lowerBound)
        XCTAssertTrue(try source("KyokashoApp.swift").contains("LibraryBackupService.applyPendingRestoreOnce()"))
    }

    /// Échec : aucune base sur disque (app, cartes, dictionnaires) et l'écran de reprise sans bouton qui le lèverait.
    func testFailedRestoreBlocksTheWholeApp() throws {
        XCTAssertTrue(try source("AppModel.swift").contains("guard !LibraryBackupService.restoreBlocked"))
        XCTAssertTrue(try source("AppModel.swift").contains("if LibraryBackupService.restoreBlocked { storageRecoveryError = LibraryBackupService.restoreMessage }"))
        XCTAssertTrue(try source("Review/ReviewModel.swift").contains("!LibraryBackupService.restoreBlocked"))
        XCTAssertTrue(try source("Dictionary/DictionaryModel.swift").contains("LibraryBackupService.restoreBlocked ? nil"))
        XCTAssertTrue(try source("KyokashoApp.swift").contains("if !LibraryBackupService.restoreBlocked { Button(\"Réessayer la reprise\")"))
    }

    /// Les réglages propres à l'iPad ne sont pas pris dans la sauvegarde.
    func testDevicePreferencesAreKept() throws {
        let service = try source("Library/LibraryBackupService.swift")
        for prefix in ["\"backup.\"", "\"google\"", "\"github.\"", "\"diagnostics.\"", "\"energy.\"", "\"update.\""] {
            XCTAssertTrue(service.contains(prefix), prefix)
        }
    }

    /// La base et les PDF doivent décrire le même état : ni import ni suppression ne peut croiser la copie.
    func testBackupAndLibraryMutationsExcludeEachOther() throws {
        let model = try source("AppModel.swift")
        let importStart = try XCTUnwrap(model.range(of: "    func importFiles("))
        let deleteStart = try XCTUnwrap(model.range(of: "    func delete("))
        XCTAssertNotNil(model.range(of: "guard !LibraryBackupService.inProgress",
                                    range: importStart.lowerBound..<deleteStart.lowerBound))
        XCTAssertNotNil(model.range(of: "guard !LibraryBackupService.inProgress",
                                    range: deleteStart.lowerBound..<model.endIndex))

        let service = try source("Library/LibraryBackupService.swift")
        XCTAssertTrue(service.contains("guard !model.libraryMutationInProgress"))
        XCTAssertTrue(model.contains("var libraryMutationInProgress: Bool { importProgress != nil || !deletingIds.isEmpty || pageRotationInProgress }"))
        XCTAssertTrue(model.contains("if LibraryBackupService.inProgress { return String(localized: \"Une sauvegarde est en cours."))
    }
}
