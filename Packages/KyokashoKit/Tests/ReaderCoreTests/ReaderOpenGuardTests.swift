// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// #93 (KYO-001) : le lecteur qui ne s'ouvrait plus après un menu ou la fenêtre d'export.
final class ReaderOpenGuardTests: XCTestCase {
    func testFirstRequestPresentsAndShowStopsRetries() {
        var guardian = ReaderOpenGuard()
        XCTAssertEqual(guardian.request("a"), .present)
        let serial = guardian.serial
        guardian.didShow()
        XCTAssertEqual(guardian.check(serial: serial), .none)
        XCTAssertFalse(guardian.gaveUp(serial: serial))
    }

    /// Présentation refusée par iOS : le contrôle relance, au plus deux fois, puis abandonne.
    func testRefusedPresentationIsRetriedTwiceThenGivesUp() {
        var guardian = ReaderOpenGuard()
        _ = guardian.request("a")
        let serial = guardian.serial
        XCTAssertEqual(guardian.check(serial: serial), .presentAgain)
        XCTAssertEqual(guardian.check(serial: serial), .presentAgain)
        XCTAssertEqual(guardian.check(serial: serial), .none)
        XCTAssertTrue(guardian.gaveUp(serial: serial))
    }

    /// Le cas de la recette : toucher à nouveau le même document alors que le lecteur n'est jamais apparu.
    func testSameDocumentRequestedAgainWithoutReaderIsPresentedAgain() {
        var guardian = ReaderOpenGuard()
        _ = guardian.request("a")
        XCTAssertEqual(guardian.request("a"), .presentAgain)
        XCTAssertEqual(guardian.retries, 0, "une nouvelle demande redonne tous les essais")
    }

    /// Un contrôle prévu pour une demande plus ancienne ne relance jamais l'ancien document.
    func testOlderCheckNeverActsAfterANewerRequest() {
        var guardian = ReaderOpenGuard()
        _ = guardian.request("a")
        let old = guardian.serial
        XCTAssertEqual(guardian.request("b"), .present)
        XCTAssertEqual(guardian.check(serial: old), .none)
        XCTAssertFalse(guardian.gaveUp(serial: old))
        XCTAssertEqual(guardian.requested, "b")
    }

    /// Lecteur déjà à l'écran : changer de document ne redemande pas la fenêtre.
    func testRequestWhileShownOnlySwitchesDocument() {
        var guardian = ReaderOpenGuard()
        _ = guardian.request("a")
        guardian.didShow()
        XCTAssertEqual(guardian.request("b"), .none)
        XCTAssertEqual(guardian.requested, "b")
    }

    func testCloseResetsEverything() {
        var guardian = ReaderOpenGuard()
        _ = guardian.request("a")
        guardian.didShow()
        guardian.didClose()
        XCTAssertNil(guardian.requested)
        XCTAssertFalse(guardian.shown)
        XCTAssertEqual(guardian.request("a"), .present)
    }
}
