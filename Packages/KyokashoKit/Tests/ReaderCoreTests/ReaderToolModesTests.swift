// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Issue #15 : chaque document garde ses propres modes d'outil.
final class ReaderToolModesTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "reader-modes-" + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testModesAreIndependentPerDocument() {
        let store = ReaderToolModeStore(defaults: defaults)
        store.update(documentId: "livre-a") { $0.drawing = true }
        store.update(documentId: "livre-b") { $0.lookup = true }
        XCTAssertEqual(store.modes(documentId: "livre-a"), ReaderToolModes(drawing: true))
        XCTAssertEqual(store.modes(documentId: "livre-b"), ReaderToolModes(lookup: true))
        XCTAssertEqual(store.modes(documentId: "livre-c"), ReaderToolModes(), "nouveau livre : tout désactivé")
    }

    func testModesSurviveANewStoreLikeAnAppRestart() {
        ReaderToolModeStore(defaults: defaults).update(documentId: "livre") { $0.pencilLookup = true; $0.lookup = true }
        XCTAssertEqual(ReaderToolModeStore(defaults: defaults).modes(documentId: "livre"),
                       ReaderToolModes(lookup: true, pencilLookup: true))
    }

    func testTurningAModeOffIsRememberedAndForgetRemovesOnlyThatDocument() {
        let store = ReaderToolModeStore(defaults: defaults)
        store.update(documentId: "livre") { $0.drawing = true }
        store.update(documentId: "livre") { $0.drawing = false }
        XCTAssertEqual(store.modes(documentId: "livre"), ReaderToolModes())
        store.update(documentId: "autre") { $0.drawing = true }
        store.forget(documentId: "livre")
        XCTAssertNil(defaults.object(forKey: ReaderToolModeStore.key(documentId: "livre")))
        XCTAssertEqual(store.modes(documentId: "autre"), ReaderToolModes(drawing: true))
    }

    func testUnreadableValueMeansAllModesOff() {
        defaults.set(Data("abîmé".utf8), forKey: ReaderToolModeStore.key(documentId: "livre"))
        XCTAssertEqual(ReaderToolModeStore(defaults: defaults).modes(documentId: "livre"), ReaderToolModes())
    }
}
