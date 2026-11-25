// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import DiagnosticKit

/// PLAN-DIAG-001 E2e : sonde du fil principal (délais injectés, veille simulée).
final class DiagnosticMainThreadProbeTests: XCTestCase {
    private let ms: UInt64 = 1_000_000

    /// Instant à `t` ms d'éveil, avec `slept` ms de veille cumulée (l'horloge continue avance seule).
    private func at(_ t: UInt64, slept: UInt64 = 0) -> DiagnosticMainThreadProbe.Instant {
        .init(uptimeNs: t * ms, continuousNs: (t + slept) * ms)
    }

    func testFirstMeasureAfterArmingIsIgnored() {
        var probe = DiagnosticMainThreadProbe()
        XCTAssertNil(probe.observe(sent: at(0), answered: at(900)), "mesure à froid")
        XCTAssertNotNil(probe.observe(sent: at(1_000), answered: at(1_400)))
        probe.rearm()
        XCTAssertNil(probe.observe(sent: at(20_000), answered: at(20_900)), "réarmé : à froid de nouveau")
    }

    func testThresholdAndEventContent() {
        var probe = DiagnosticMainThreadProbe()
        _ = probe.observe(sent: at(0), answered: at(1))
        XCTAssertNil(probe.observe(sent: at(100), answered: at(349)), "sous le seuil")
        let event = probe.observe(sent: at(500), answered: at(750))
        XCTAssertEqual(event?.durationMs, 250)
        XCTAssertEqual(event?.level, .info, "DEC-03 A : en mode diagnostic seulement")
        XCTAssertEqual(event?.zone, .performances)
        XCTAssertEqual(event?.step.description, "fil_principal_lent")
        XCTAssertEqual(event?.counts.map(\.name.description), ["seuil_ms"])
        XCTAssertNil(event?.op, "aucun identifiant ni texte")
    }

    func testSleepIsNotReportedAsAStall() {
        var probe = DiagnosticMainThreadProbe()
        _ = probe.observe(sent: at(0), answered: at(1))
        XCTAssertNil(probe.observe(sent: at(100), answered: at(700, slept: 30_000)), "veille traversée")
        XCTAssertNotNil(probe.observe(sent: at(1_000, slept: 30_000), answered: at(1_600, slept: 30_000)),
                        "après la veille, un vrai délai est noté")
    }

    func testCloseLinesAreMergedAndReportedLater() {
        var probe = DiagnosticMainThreadProbe()
        _ = probe.observe(sent: at(0), answered: at(1))
        XCTAssertNotNil(probe.observe(sent: at(1_000), answered: at(1_300)))
        XCTAssertNil(probe.observe(sent: at(2_000), answered: at(2_800)), "moins de 10 s après")
        XCTAssertNil(probe.observe(sent: at(3_000), answered: at(3_400)))
        let next = probe.observe(sent: at(12_000), answered: at(12_260))
        XCTAssertEqual(next?.counts.map(\.name.description), ["seuil_ms", "omis", "omis_max_ms"])
        XCTAssertEqual(next?.counts.map(\.value), [250, 2, 800])
        let after = probe.observe(sent: at(30_000), answered: at(30_300))
        XCTAssertEqual(after?.counts.map(\.name.description), ["seuil_ms"], "compteurs remis à zéro")
    }

    func testObservationHoleIsIgnoredButALiveObserverCounts() {
        var probe = DiagnosticMainThreadProbe()
        _ = probe.observe(sent: at(0), answered: at(1))
        // Fil principal lent, observateur vivant : réveils réguliers pendant l'attente → noté.
        probe.send(at: at(1_000))
        for t in stride(from: UInt64(1_500), through: 3_500, by: 500) { probe.tick(at: at(t)) }
        XCTAssertEqual(probe.observe(sent: at(1_000), answered: at(3_700))?.durationMs, 2_700)
        // Processus entier figé (aucun réveil pendant 3 s) : trou d'observation → rien.
        probe.send(at: at(20_000))
        probe.tick(at: at(20_500))
        XCTAssertNil(probe.observe(sent: at(20_000), answered: at(23_600)), "trou jusqu'à la réponse")
        probe.send(at: at(40_000))
        probe.tick(at: at(43_000))
        XCTAssertNil(probe.observe(sent: at(40_000), answered: at(43_100)), "trou entre deux réveils")
        // Le trou ne déborde pas sur la mesure suivante.
        probe.send(at: at(60_000))
        probe.tick(at: at(60_300))
        XCTAssertNotNil(probe.observe(sent: at(60_000), answered: at(60_400)))
    }

    /// Revue R2 E2e, B1 : réponse horodatée avant un réveil plus récent mais traitée après lui.
    func testAnswerStampedBeforeALaterTickIsStillMeasured() {
        var probe = DiagnosticMainThreadProbe()
        _ = probe.observe(sent: at(0), answered: at(1))
        probe.send(at: at(1_000))
        for t in stride(from: UInt64(1_500), through: 2_000, by: 500) { probe.tick(at: at(t)) }
        probe.tick(at: at(2_500))   // traité avant la réponse lue à 2 400
        XCTAssertEqual(probe.observe(sent: at(1_000), answered: at(2_400))?.durationMs, 1_400)
        probe.send(at: at(3_000))
        XCTAssertNil(probe.observe(sent: at(3_000), answered: at(3_100)), "mesure suivante normale, sous le seuil")
    }

    /// Revue R2 E2e, B1 : vrai trou avant la réponse, puis un réveil plus récent ; la mesure suivante n'en hérite pas.
    func testRealHoleThenLaterTickStillDropsOnlyThatMeasure() {
        var probe = DiagnosticMainThreadProbe()
        _ = probe.observe(sent: at(0), answered: at(1))
        probe.send(at: at(1_000))
        probe.tick(at: at(4_500))   // 3,5 s de silence
        probe.tick(at: at(5_000))
        XCTAssertNil(probe.observe(sent: at(1_000), answered: at(4_400)))
        probe.send(at: at(20_000))
        probe.tick(at: at(20_500))
        XCTAssertNotNil(probe.observe(sent: at(20_000), answered: at(20_600)))
    }

    /// Revue R2 E2e passage 2, B1 : silence devenu trop long **après** la réponse (réveil tardif traité avant elle).
    func testHoleThatStartsAfterTheAnswerDoesNotRejectIt() {
        var probe = DiagnosticMainThreadProbe()
        _ = probe.observe(sent: at(0), answered: at(1))
        probe.send(at: at(1_000))
        probe.tick(at: at(1_500))
        probe.tick(at: at(4_000))   // trou à partir de 3 500, réponse lue à 1 800
        XCTAssertEqual(probe.observe(sent: at(1_000), answered: at(1_800))?.durationMs, 800)
        probe.send(at: at(15_000))
        probe.tick(at: at(15_500))
        XCTAssertNotNil(probe.observe(sent: at(15_000), answered: at(15_600)), "mesure suivante publiable")
    }

    func testThresholdBoundary() {
        var probe = DiagnosticMainThreadProbe()
        _ = probe.observe(sent: at(0), answered: at(1))
        XCTAssertNil(probe.observe(sent: at(100), answered: at(349)))
        XCTAssertNotNil(probe.observe(sent: at(400), answered: at(650)))
    }

    func testClockGoingBackwardsIsIgnored() {
        var probe = DiagnosticMainThreadProbe()
        _ = probe.observe(sent: at(0), answered: at(1))
        XCTAssertNil(probe.observe(sent: at(5_000), answered: at(4_000)))
    }

    func testRealClockReadsBothClocks() {
        let a = DiagnosticMainThreadProbe.Instant.now(), b = DiagnosticMainThreadProbe.Instant.now()
        XCTAssertGreaterThanOrEqual(b.uptimeNs, a.uptimeNs)
        XCTAssertGreaterThanOrEqual(b.continuousNs, a.continuousNs)
    }
}
