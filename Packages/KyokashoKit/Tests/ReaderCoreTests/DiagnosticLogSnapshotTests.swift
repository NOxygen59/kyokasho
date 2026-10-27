// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

final class DiagnosticLogSnapshotTests: XCTestCase {
    func testSnapshotsDistinguishMissingEmptyUpdatedAndUnreadable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("journal.txt")
        XCTAssertEqual(DiagnosticLogSnapshot.read(from: file), "Aucun journal enregistré.")
        try Data().write(to: file)
        XCTAssertEqual(DiagnosticLogSnapshot.read(from: file), "Journal vide.")
        try Data("Une action synthétique 日本語\n".utf8).write(to: file)
        XCTAssertEqual(DiagnosticLogSnapshot.read(from: file), "Une action synthétique 日本語\n")
        try Data("Deuxième action\n".utf8).write(to: file)
        XCTAssertEqual(DiagnosticLogSnapshot.read(from: file), "Deuxième action\n")
        XCTAssertTrue(DiagnosticLogSnapshot.read(from: folder).hasPrefix("Impossible de lire"))
    }

    func testRotationCuttingUTF8StillDisplaysRemainingLines() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        // Même suffixe d'octets que la rotation de Diagnostics.write : coupe au milieu de 日.
        let rotated = Data(Data("日\nAction synthétique\n".utf8).dropFirst())
        try rotated.write(to: file)
        XCTAssertNil(String(data: rotated, encoding: .utf8))
        XCTAssertTrue(DiagnosticLogSnapshot.read(from: file).contains("Action synthétique"))
    }
}
