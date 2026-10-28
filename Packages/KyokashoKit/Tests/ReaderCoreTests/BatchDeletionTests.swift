// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Suppression multiple : rien n'est effacé sans deux confirmations dans l'ordre.
final class BatchDeletionTests: XCTestCase {
    func testDeletesOnlyAfterBothConfirmations() {
        var batch = BatchDeletion()
        batch.toggle("a"); batch.toggle("b")
        batch.requestDeletion()
        XCTAssertEqual(batch.step, .firstConfirmation)
        XCTAssertEqual(batch.confirmSecond(existing: ["a", "b"]), [], "pas d'effacement à la première question")
        batch.confirmFirst()
        XCTAssertEqual(batch.step, .secondConfirmation)
        XCTAssertEqual(batch.confirmSecond(existing: ["a", "b", "c"]), ["a", "b"])
        XCTAssertTrue(batch.selected.isEmpty)
        XCTAssertEqual(batch.step, .selecting)
    }

    func testCancelAtAnyStepKeepsSelectionAndDeletesNothing() {
        var batch = BatchDeletion()
        batch.selectAll(["a", "b"])
        batch.requestDeletion(); batch.cancel()
        XCTAssertEqual(batch.selected, ["a", "b"])
        batch.requestDeletion(); batch.confirmFirst(); batch.cancel()
        XCTAssertEqual(batch.step, .selecting)
        XCTAssertEqual(batch.confirmSecond(existing: ["a", "b"]), [])
        XCTAssertEqual(batch.selected, ["a", "b"])
    }

    func testEmptySelectionAsksNothing() {
        var batch = BatchDeletion()
        batch.requestDeletion()
        XCTAssertEqual(batch.step, .selecting)
    }

    func testSelectionIsFrozenDuringConfirmation() {
        var batch = BatchDeletion()
        batch.toggle("a")
        batch.requestDeletion()
        batch.toggle("b"); batch.selectAll(["x"])
        XCTAssertEqual(batch.selected, ["a"])
    }

    func testDocumentsGoneMeanwhileAreSkipped() {
        var batch = BatchDeletion()
        batch.selectAll(["a", "b"])
        batch.requestDeletion(); batch.confirmFirst()
        XCTAssertEqual(batch.confirmSecond(existing: ["b"]), ["b"])
    }
}
