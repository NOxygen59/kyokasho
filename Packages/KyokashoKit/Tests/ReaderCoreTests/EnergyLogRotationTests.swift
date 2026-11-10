// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// BUG-004 (audit Fable du 10/11/2026) : la rotation du relevé gardait les derniers octets du fichier sans regarder
/// où tombait la coupe. Entre les deux octets d'un « è », le fichier n'était plus de l'UTF-8 valide et le résumé de
/// batterie restait vide (« pas encore assez de mesures ») pour tout le relevé.
final class EnergyLogRotationTests: XCTestCase {
    private func line(_ minute: Double) -> String {
        EnergyLog.line(EnergySample(date: Date(timeIntervalSince1970: 1_800_000_000 + minute * 60), battery: 0.5,
                                    charging: false, thermal: 0, lowPower: false, brightness: 0.5, cpuSeconds: minute,
                                    memoryMB: 900, activity: "Bibliothèque ou réglages"))
    }

    func testRotationStartsOnALineWhateverTheCut() throws {
        let lines = (0..<6).map { line(Double($0)) }
        let data = Data((EnergyLog.header + "\n" + lines.joined(separator: "\n") + "\n").utf8)
        // Toutes les coupes possibles, dont celles qui tombent au milieu d'un caractère de deux octets.
        for kept in 1..<data.count {
            let rotated = EnergyLog.rotated(data, keeping: kept)
            let text = try XCTUnwrap(String(data: rotated, encoding: .utf8), "coupe à \(kept) octets : UTF-8 invalide")
            XCTAssertTrue(text.hasPrefix(EnergyLog.header + "\n"))
            let samples = EnergyLog.parse(rotated)
            // Seules des lignes entières restent : chacune se relit.
            XCTAssertEqual(samples.count, text.split(separator: "\n").count - 1, "coupe à \(kept) octets")
            XCTAssertLessThanOrEqual(samples.count, lines.count)
        }
        XCTAssertEqual(EnergyLog.parse(EnergyLog.rotated(data, keeping: data.count)).count, lines.count)
    }

    func testAFileAlreadyCutInsideACharacterStillReads() {
        // Fichier laissé par une ancienne version : la première ligne commence par le second octet d'un « è ».
        var data = Data([0xA8])
        data.append(Data(("que ou réglages\n" + line(1) + "\n" + line(2) + "\n").utf8))
        XCTAssertNil(String(data: data, encoding: .utf8), "le cas d'essai doit être de l'UTF-8 invalide")
        XCTAssertEqual(EnergyLog.parse(data).count, 2)
    }
}
