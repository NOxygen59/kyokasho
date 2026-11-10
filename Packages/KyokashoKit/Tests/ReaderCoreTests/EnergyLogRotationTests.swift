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

/// BUG-005 (audit Fable du 10/11/2026) : une charge courte ne terminait pas la session sur batterie.
final class EnergyLogSessionBoundaryTests: XCTestCase {
    private func sample(_ minute: Double, _ battery: Double, charging: Bool = false) -> EnergySample {
        EnergySample(date: Date(timeIntervalSince1970: 1_800_000_000 + minute * 60), battery: battery,
                     charging: charging, thermal: 0, lowPower: false, brightness: 0.5, cpuSeconds: minute,
                     memoryMB: 900, activity: "Lecture")
    }

    func testAShortChargeEndsTheSession() {
        // 12 minutes sur batterie, 1 minute de charge (moins que `maxGap`), puis 12 minutes sur batterie.
        var samples = (0...12).map { sample(Double($0), 0.80 - Double($0) * 0.002) }
        samples.append(sample(13, 0.78, charging: true))
        samples += (14...26).map { sample(Double($0), 0.78 - Double($0 - 14) * 0.002) }
        let sessions = EnergyLog.sessions(samples)
        XCTAssertEqual(sessions.count, 2, "la mise en charge sépare deux sessions")
        // Chaque session ne compte que ses minutes sur batterie.
        XCTAssertEqual(sessions.map(\.seconds), [720, 720])
        for session in sessions { XCTAssertEqual(session.lostPoints, 2.4, accuracy: 0.01) }
    }
}
