// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore
import XCTest

/// Furigana ajoutés d'un manga : choix du document, gardé dans son JSON, qui n'est pas un réglage de lecture à remettre.
final class PageFuriganaOverrideTests: XCTestCase {
    func testDefaultIsHiddenAndChoiceRoundTrips() throws {
        var settings = ReaderSettingsOverride()
        XCTAssertNil(settings.pageFurigana)
        settings.pageFurigana = true
        let decoded = try JSONDecoder().decode(ReaderSettingsOverride.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.pageFurigana, true)
    }

    func testChoiceIsNotAReaderOverride() {
        var settings = ReaderSettingsOverride()
        settings.mangaSpace = true
        settings.pageFurigana = true
        XCTAssertFalse(settings.hasReaderOverrides)
    }
}
