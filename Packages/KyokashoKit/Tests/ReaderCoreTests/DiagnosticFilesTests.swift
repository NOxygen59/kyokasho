// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Bannière permanente des fichiers de diagnostic (demande du 10/11/2026) : décision pure, sans disque.
final class DiagnosticFilesTests: XCTestCase {
    func testNothingIsSaidWhileBothFilesStayUnderTheirThreshold() {
        XCTAssertNil(DiagnosticFiles.warning(journalBytes: 0, energyBytes: 0))
        XCTAssertNil(DiagnosticFiles.warning(journalBytes: DiagnosticFiles.journalWarningBytes, energyBytes: DiagnosticFiles.energyWarningBytes),
                     "les seuils eux-mêmes ne suffisent pas : il faut les dépasser")
    }

    func testAJournalOverOneAndAHalfMegabytesWarns() {
        let warning = try! XCTUnwrap(DiagnosticFiles.warning(journalBytes: 1_800_000, energyBytes: 0))
        XCTAssertEqual(warning.megabytes, 1.8, accuracy: 0.001)
        XCTAssertEqual(warning.journalBytes, 1_800_000)
    }

    func testAnEnergyLogOverOneMegabyteWarns() {
        let warning = try! XCTUnwrap(DiagnosticFiles.warning(journalBytes: 0, energyBytes: 1_200_000))
        XCTAssertEqual(warning.megabytes, 1.2, accuracy: 0.001)
    }

    func testTheDisplayedSizeIsTheTotalRoundedToOneDecimal() {
        // Les deux fichiers comptent : c'est l'espace qu'ils prennent ensemble que l'utilisateur récupère.
        let warning = try! XCTUnwrap(DiagnosticFiles.warning(journalBytes: 1_540_000, energyBytes: 1_070_000))
        XCTAssertEqual(warning.megabytes, 2.6, accuracy: 0.001)
    }

    func testErasingBothFilesRemovesTheBanner() {
        let warning = try! XCTUnwrap(DiagnosticFiles.warning(journalBytes: 1_900_000, energyBytes: 1_100_000))
        XCTAssertNotNil(warning)
        XCTAssertNil(DiagnosticFiles.warning(journalBytes: 0, energyBytes: 0), "après « Effacer », plus rien à dire")
        // Un seul fichier effacé ne suffit pas : l'autre dépasse encore son seuil.
        XCTAssertNotNil(DiagnosticFiles.warning(journalBytes: 0, energyBytes: 1_100_000))
    }

    /// Le format d'une ligne de journal est un contrat (`docs/DEBOGAGE.md`) : heure ISO, niveau, zone, message sur
    /// **une** ligne. Un message multiligne compterait pour plusieurs événements.
    func testJournalLineCarriesTimeLevelAndAreaOnASingleLine() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let line = DiagnosticFiles.journalLine(.erreur, area: "ia", message: "échec\ndeuxième ligne",
                                               at: date, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(line, "2027-01-15T08:00:00.000Z [erreur] [ia] échec deuxième ligne")
        XCTAssertFalse(line.contains("\n"))
    }
}
