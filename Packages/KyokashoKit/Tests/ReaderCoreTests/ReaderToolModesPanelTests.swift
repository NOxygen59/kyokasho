// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Recette 1.3.2 (61), M2 : position du panneau d'étude retenue par document.
final class ReaderToolModesPanelTests: XCTestCase {
    private func store() -> ReaderToolModeStore {
        let suite = "kyokasho-panel-" + UUID().uuidString
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return ReaderToolModeStore(defaults: UserDefaults(suiteName: suite)!)
    }

    func testModesSavedBeforePanelFieldStillLoad() throws {
        let suite = "kyokasho-panel-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"drawing":true,"lookup":false,"pencilLookup":true}"#.utf8), forKey: ReaderToolModeStore.key(documentId: "d"))
        let modes = ReaderToolModeStore(defaults: defaults).modes(documentId: "d")
        XCTAssertTrue(modes.drawing)
        XCTAssertTrue(modes.pencilLookup)
        XCTAssertNil(modes.panelMode)
    }

    func testPanelModeIsPerDocument() {
        let store = store()
        store.update(documentId: "a") { $0.panelMode = "floating" }
        store.update(documentId: "a") { $0.drawing = true }
        XCTAssertEqual(store.modes(documentId: "a").panelMode, "floating")
        XCTAssertNil(store.modes(documentId: "b").panelMode)
        store.forget(documentId: "a")
        XCTAssertNil(store.modes(documentId: "a").panelMode)
    }
}
