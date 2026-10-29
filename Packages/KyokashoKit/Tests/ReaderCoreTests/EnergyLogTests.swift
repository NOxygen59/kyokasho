// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Relevé de batterie (#20) : lecture du fichier et résumé par activité.
final class EnergyLogTests: XCTestCase {
    private func sample(_ minute: Double, _ battery: Double, cpu: Double, _ activity: String,
                        charging: Bool = false, thermal: Int = 0) -> EnergySample {
        EnergySample(date: Date(timeIntervalSince1970: 1_800_000_000 + minute * 60), battery: battery, charging: charging,
                     thermal: thermal, lowPower: false, brightness: 0.5, cpuSeconds: cpu, memoryMB: 900, activity: activity)
    }

    func testLinesRoundTripAndCommasCannotBreakColumns() {
        let s = sample(0, 0.42, cpu: 12.5, "IA : OvisOCR2, Qwen3-VL", thermal: 2)
        let text = EnergyLog.header + "\n" + EnergyLog.line(s) + "\nligne tronquée,1\n"
        let parsed = EnergyLog.parse(text)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].activity, "IA : OvisOCR2  Qwen3-VL")
        XCTAssertEqual(parsed[0].battery, 0.42, accuracy: 0.0001)
        XCTAssertEqual(parsed[0].thermal, 2)
        XCTAssertEqual(parsed[0].date, s.date)
    }

    func testSummaryGivesBatteryPerHourPerActivity() {
        var samples: [EnergySample] = []
        // 20 min de lecture : 2 points perdus, 6 s de calcul ; puis 20 min d'IA : 10 points, 1 200 s de calcul.
        for m in 0...20 { samples.append(sample(Double(m), 0.80 - 0.001 * Double(m), cpu: 0.3 * Double(m), "Lecture")) }
        for m in 1...20 {
            samples.append(sample(Double(20 + m), 0.78 - 0.005 * Double(m), cpu: 6 + 60 * Double(m), "IA : OvisOCR2", thermal: m > 15 ? 2 : 1))
        }
        samples[20].activity = "IA : OvisOCR2" // l'IA démarre à la minute 20
        let rows = EnergyLog.summary(samples)
        let reading = try! XCTUnwrap(rows.first { $0.activity == "Lecture" })
        let ai = try! XCTUnwrap(rows.first { $0.activity == "IA : OvisOCR2" })
        XCTAssertEqual(reading.seconds, 1200)
        XCTAssertEqual(reading.batteryPerHour!, 6, accuracy: 0.01)
        XCTAssertEqual(reading.cpuPercent, 0.5, accuracy: 0.01)
        XCTAssertEqual(ai.batteryPerHour!, 30, accuracy: 0.01)
        XCTAssertEqual(ai.cpuPercent, 100, accuracy: 0.01)
        XCTAssertEqual(ai.maxThermal, 2)
    }

    func testChargingSuspensionsRelaunchesAndShortPeriodsAreNotCounted() {
        let rows = EnergyLog.summary([
            sample(0, 0.50, cpu: 10, "Lecture"),
            sample(1, 0.51, cpu: 11, "Lecture", charging: true), // branché
            sample(2, 0.52, cpu: 12, "Lecture"),
            sample(30, 0.40, cpu: 13, "Lecture"),                // app suspendue 28 min
            sample(31, 0.40, cpu: 1, "Lecture"),                 // relancée : le calcul repart de zéro
            sample(32, 0.39, cpu: 2, "Lecture"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].seconds, 60)
        XCTAssertNil(rows[0].batteryPerHour, "moins de 10 minutes : pas de débit affiché")
    }
}
