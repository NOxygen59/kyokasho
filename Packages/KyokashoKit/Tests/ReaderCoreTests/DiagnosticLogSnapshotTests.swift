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

    // MARK: Fin du journal (RET-045, #67)

    private func tempFile(_ data: Data) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        return file
    }

    func testTailOfShortLogShowsEveryLine() throws {
        let file = try tempFile(Data("un\ndeux\ntrois\n".utf8))
        XCTAssertEqual(DiagnosticLogSnapshot.readTail(from: file), .init(lines: ["un", "deux", "trois"], omittedBytes: 0))
    }

    func testTailOfLongLogReadsOnlyTheEndAndDropsTheCutLine() throws {
        // Journal synthétique d'environ 2 Mo, comme la limite de Diagnostics.
        let text = (0..<40_000).map { "ligne \($0) action synthétique 日本語" }.joined(separator: "\n") + "\n"
        let file = try tempFile(Data(text.utf8))
        let tail = DiagnosticLogSnapshot.readTail(from: file, maxBytes: 10_000, maxLines: 1_000)
        XCTAssertEqual(tail.lines.last, "ligne 39999 action synthétique 日本語")
        XCTAssertLessThan(tail.lines.count, 300)
        XCTAssertTrue(tail.lines.allSatisfy { $0.hasPrefix("ligne ") && $0.hasSuffix("日本語") }, "aucune ligne coupée")
        let shown = tail.lines.reduce(0) { $0 + $1.utf8.count + 1 }
        XCTAssertEqual(tail.omittedBytes + shown, text.utf8.count)
    }

    func testTailKeepsAtMostMaxLines() throws {
        let file = try tempFile(Data((1...50).map(String.init).joined(separator: "\n").utf8))
        let tail = DiagnosticLogSnapshot.readTail(from: file, maxLines: 10)
        XCTAssertEqual(tail.lines, (41...50).map(String.init))
        XCTAssertGreaterThan(tail.omittedBytes, 0)
    }

    func testTailReportsMissingEmptyAndUnreadableLogs() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(DiagnosticLogSnapshot.readTail(from: missing).lines, ["Aucun journal enregistré."])
        XCTAssertEqual(DiagnosticLogSnapshot.readTail(from: try tempFile(Data())).lines, ["Journal vide."])
        let folder = FileManager.default.temporaryDirectory
        XCTAssertTrue(DiagnosticLogSnapshot.readTail(from: folder).lines.first?.hasPrefix("Impossible de lire") ?? false)
    }
}
