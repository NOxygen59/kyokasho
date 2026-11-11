// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Relevé de batterie (#20) : lecture du fichier, résumé par activité, par luminosité et sessions.
final class EnergyLogTests: XCTestCase {
    private func sample(_ minute: Double, _ battery: Double, cpu: Double, _ activity: String,
                        charging: Bool = false, thermal: Int = 0, brightness: Double = 0.5) -> EnergySample {
        EnergySample(date: Date(timeIntervalSince1970: 1_800_000_000 + minute * 60), battery: battery, charging: charging,
                     thermal: thermal, lowPower: false, brightness: brightness, cpuSeconds: cpu, memoryMB: 900,
                     activity: activity)
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

    // MARK: Colonnes ajoutées le 10/11/2026

    func testNewColumnsAreWrittenAfterTheOldOnesAndReadBack() {
        var s = sample(0, 0.42, cpu: 12.5, "Lecture", thermal: 2)
        s.cpuPercent = 37.5
        s.screen = .background
        s.tone = "sepiaNight"
        s.loadedModels = "OvisOCR2 + GLM-OCR"
        s.aiTasks = "lecture"
        s.document = "8f3a1c2e"
        s.appVersion = "1.4.2 (58)"
        let columns = EnergyLog.line(s).split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(columns.count, EnergyLog.columnCount)
        // Rétrocompatibilité : les 9 premières colonnes ne bougent pas de place.
        XCTAssertEqual(Array(columns.prefix(3)), ["2027-01-15T08:00:00Z", "0.420", "0"])
        XCTAssertEqual(columns[9], "37.5")
        XCTAssertEqual(columns[10], "arriere-plan")
        XCTAssertEqual(columns[11], "serious", "état thermique en texte, lisible sans l'app")
        XCTAssertEqual(columns[12], "sepiaNight")

        let back = EnergyLog.parse(EnergyLog.header + "\n" + EnergyLog.line(s))
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].cpuPercent, 37.5)
        XCTAssertEqual(back[0].screen, .background)
        XCTAssertEqual(back[0].tone, "sepiaNight")
        XCTAssertEqual(back[0].loadedModels, "OvisOCR2 + GLM-OCR")
        XCTAssertEqual(back[0].aiTasks, "lecture")
        XCTAssertEqual(back[0].document, "8f3a1c2e")
        XCTAssertEqual(back[0].appVersion, "1.4.2 (58)")
    }

    func testOldNineColumnFileStillReads() {
        let old = "2026-10-01T10:00:00Z,0.610,0,0,0,0.50,120.00,900,Lecture"
        let parsed = EnergyLog.parse(EnergyLog.header + "\n" + old)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].battery, 0.61, accuracy: 0.0001)
        XCTAssertEqual(parsed[0].activity, "Lecture")
        XCTAssertNil(parsed[0].cpuPercent)
        XCTAssertEqual(parsed[0].tone, "")
    }

    func testUnknownBatteryIsNeverWrittenAsMinusOne() {
        // iOS renvoie -1 quand il ne donne pas le niveau : la case reste vide, et rien n'est compté.
        let line = EnergyLog.line(sample(0, -1, cpu: 10, "Lecture"))
        XCTAssertEqual(line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)[1], "")
        let parsed = EnergyLog.parse(EnergyLog.header + "\n" + line)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertLessThan(parsed[0].battery, 0, "inconnue, jamais un niveau")
        XCTAssertTrue(EnergyLog.summary(parsed).isEmpty, "une batterie inconnue ne produit aucun débit")
    }

    func testDocumentIdentifierIsCutToEightCharacters() {
        var s = sample(0, 0.5, cpu: 10, "Lecture")
        s.document = "0123456789abcdef-titre-du-livre"
        let columns = EnergyLog.line(s).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(columns[15], "01234567")
    }

    func testCpuPercentOfTheAppBetweenTwoSamples() {
        let first = sample(0, 0.50, cpu: 100, "Lecture")
        let second = sample(1, 0.49, cpu: 160, "Lecture")
        XCTAssertEqual(try XCTUnwrap(EnergyLog.cpuPercent(previous: first, second)), 100, accuracy: 0.01)
        XCTAssertNil(EnergyLog.cpuPercent(previous: nil, second), "premier relevé : rien à comparer")
        // Relancement de l'app : le temps cumulé repart de zéro.
        XCTAssertNil(EnergyLog.cpuPercent(previous: second, sample(2, 0.48, cpu: 3, "Lecture")))
        // Suspension : l'intervalle ne dit rien du processeur.
        XCTAssertNil(EnergyLog.cpuPercent(previous: first, sample(10, 0.48, cpu: 300, "Lecture")))
    }

    // MARK: Résumé

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

    func testAberrantJumpsAndRisesAreIgnored() {
        // Relevé réel : des sauts de plusieurs dizaines de points et des hausses sans charge faussaient les moyennes.
        let rows = EnergyLog.summary([
            sample(0, 0.60, cpu: 10, "Lecture"),
            sample(1, 0.599, cpu: 20, "Lecture"),  // 0,1 point : compté
            sample(2, 0.30, cpu: 30, "Lecture"),   // 30 points en une minute : ignoré
            sample(3, 0.305, cpu: 40, "Lecture"),  // remonte sans charge : ignoré
            sample(4, 0.304, cpu: 50, "Lecture"),  // 0,1 point : compté
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].seconds, 120, "seules les deux minutes plausibles comptent")
        XCTAssertEqual(rows[0].cpuPercent, 100.0 / 6, accuracy: 0.01, "20 s de calcul sur 120 s")
    }

    func testBrightnessBands() {
        XCTAssertEqual(EnergyLog.BrightnessBand.of(0.60), .low)
        XCTAssertEqual(EnergyLog.BrightnessBand.of(0.61), .mid)
        XCTAssertEqual(EnergyLog.BrightnessBand.of(0.90), .mid)
        XCTAssertEqual(EnergyLog.BrightnessBand.of(0.91), .high)
        XCTAssertNil(EnergyLog.BrightnessBand.of(-1), "iOS ne donne pas la luminosité")

        var samples: [EnergySample] = []
        // 20 min à 40 % de luminosité : 4 points perdus (12 points/heure).
        for m in 0...20 { samples.append(sample(Double(m), 0.80 - 0.002 * Double(m), cpu: 10 * Double(m), "Lecture", brightness: 0.40)) }
        // Puis 10 min à 100 % : 6 points perdus (36 points/heure).
        for m in 21...31 {
            samples.append(sample(Double(m), 0.76 - 0.006 * Double(m - 20), cpu: 1_000 + 10 * Double(m), "Lecture", brightness: 1.0))
        }
        let rows = EnergyLog.brightnessSummary(samples)
        XCTAssertEqual(rows.map(\.band), [.low, .high], "seules les tranches mesurées apparaissent, de la plus sombre à la plus claire")
        // L'intervalle qui suit un changement de luminosité est attribué à la luminosité notée à son début.
        XCTAssertEqual(try XCTUnwrap(rows[0].batteryPerHour), 13.1, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(rows[1].batteryPerHour), 36, accuracy: 0.1)
    }

    func testSessionsSplitOnSuspensionAndIgnoreCharging() {
        var samples: [EnergySample] = []
        // 10 minutes sur batterie : 4 points perdus.
        for m in 0...10 { samples.append(sample(Double(m), 0.90 - 0.004 * Double(m), cpu: 10 * Double(m), "Lecture")) }
        // En charge : ce n'est pas une session sur batterie.
        for m in 20...30 { samples.append(sample(Double(m), 0.90 - 0.001 * Double(m), cpu: 100 * Double(m), "Lecture", charging: true)) }
        // Nouvelle session, 20 minutes, 6 points perdus.
        for m in 40...60 {
            samples.append(sample(Double(m), 0.80 - 0.003 * Double(m - 40), cpu: 1_000 + 10 * Double(m), "Lecture"))
        }
        let sessions = EnergyLog.sessions(samples)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].start, Date(timeIntervalSince1970: 1_800_000_000 + 40 * 60), "la plus récente d'abord")
        XCTAssertEqual(sessions[0].seconds, 1200)
        XCTAssertEqual(sessions[0].lostPoints, 6, accuracy: 0.01)
        XCTAssertEqual(sessions[0].batteryPerHour!, 18, accuracy: 0.01)
        XCTAssertEqual(sessions[0].brightness, 0.5, accuracy: 0.01)
        XCTAssertEqual(sessions[0].activity, "Lecture")
        XCTAssertEqual(sessions[1].lostPoints, 4, accuracy: 0.01)
        XCTAssertEqual(sessions[1].seconds, 600)
    }
}
