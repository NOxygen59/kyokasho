// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Séquences de la revue de Codex sur la PR #78 : seul le dernier rappel de bascule s'applique.
final class LatestGenerationTests: XCTestCase {
    func testRapidSwitchesKeepOnlyTheLastResult() {
        var generation = LatestGeneration()
        let first = generation.advance()   // japonais → français
        let second = generation.advance()  // français → japonais, avant le retour du premier
        XCTAssertFalse(generation.isCurrent(first))
        XCTAssertTrue(generation.isCurrent(second))
    }

    func testPageReloadInvalidatesPendingSwitch() {
        var generation = LatestGeneration()
        let pendingSwitch = generation.advance()
        generation.advance()               // nouvelle page HTML (changement de page) avant le rappel
        XCTAssertFalse(generation.isCurrent(pendingSwitch))
    }

    func testDeferredScrollChecksTheSameToken() {
        var generation = LatestGeneration()
        let token = generation.advance()
        XCTAssertTrue(generation.isCurrent(token), "rappel JavaScript : encore courant")
        generation.advance()               // bascule pendant les 0,1 s d'attente du décalage
        XCTAssertFalse(generation.isCurrent(token), "bloc différé : ignoré")
    }

    func testStartsWithNoCurrentToken() {
        XCTAssertFalse(LatestGeneration().isCurrent(1))
    }
}
