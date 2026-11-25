// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import DiagnosticKit

/// PLAN-DIAG-001 E2d (transitions thermiques) et E2f (MetricKit en option).
final class DiagnosticThermalMetricTests: XCTestCase {
    func testThermalBaselineDedupAndLevels() {
        var t = DiagnosticThermalTracker()
        XCTAssertNil(t.observe(raw: 0), "premier relevé : référence sans signal")
        XCTAssertNil(t.observe(raw: 0), "doublon")
        let fair = t.observe(raw: 1)
        XCTAssertEqual(fair?.level, .info)
        let serious = t.observe(raw: 2)
        XCTAssertEqual(serious?.level, .alerte)
        XCTAssertEqual(serious?.counts.map(\.value), [1, 2])
        XCTAssertEqual(t.observe(raw: 1)?.level, .alerte, "sortie d'un état élevé : alerte")
        let unknown = t.observe(raw: 9)
        XCTAssertEqual(unknown?.counts.map(\.value), [1, -1], "état inconnu gardé comme inconnu")
        XCTAssertEqual(unknown?.level, .info, "inconnu seul : pas d'alerte")
        XCTAssertEqual(DiagnosticThermalLevel(raw: 9), .unknown(9))
    }

    func testMetricSummaryKeepsAbsenceDistinctFromZero() {
        let absent = DiagnosticMetricSummary.metrics(payloads: 1, foreground: .init(memoryLimit: nil, watchdog: nil),
                                                     background: .init(memoryLimit: nil, watchdog: nil))
        XCTAssertEqual(absent.counts.map(\.name.description), ["lots"])
        let both = DiagnosticMetricSummary.metrics(payloads: 1, foreground: .init(memoryLimit: 0, watchdog: nil),
                                                   background: .init(memoryLimit: 2, watchdog: 1))
        XCTAssertEqual(both.counts.map(\.name.description), ["lots", "sorties_pp_limite_memoire", "sorties_fond_limite_memoire",
                                                             "sorties_fond_chien_de_garde"], "arrière-plan compté à part")
        let zero = DiagnosticMetricSummary.diagnostics(payloads: 2, crashes: 0, hangs: nil)
        XCTAssertEqual(zero.counts.map(\.name.description), ["lots", "plantages"])
        XCTAssertEqual(zero.counts.map(\.value), [2, 0])
        let line = DiagnosticLine.event(DiagnosticMetricSummary.subscription(on: true, systemMajor: 16, systemMinor: 6),
                                        at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(line.contains("étape=metrickit_abonnement") && line.contains("ios_majeur=16 ios_mineur=6"), line)
    }

    func testSubscriptionGateRejectsLateCallbacks() {
        var g = DiagnosticSubscriptionGate()
        let first = g.enable()
        XCTAssertNotNil(first)
        XCTAssertNil(g.enable(), "idempotent")
        XCTAssertTrue(g.accepts(first!))
        XCTAssertTrue(g.disable())
        XCTAssertFalse(g.disable(), "idempotent")
        XCTAssertFalse(g.accepts(first!), "rappel tardif après désactivation : rejeté")
        let second = g.enable()
        XCTAssertFalse(g.accepts(first!), "rappel d'un ancien abonnement : rejeté")
        XCTAssertTrue(g.accepts(second!))
    }
}
