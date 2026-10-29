// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import OCRKit

/// Suppression d'une traduction (demande de NOxygen59 du 29/10/2026) : seuls les fichiers de cette langue sont visés.
final class AIPageFileTests: XCTestCase {
    func testOnlyFilesOfThatReaderMatch() {
        XCTAssertEqual(AIPageFile.page(of: "en-12.md", reader: "en"), 12)
        XCTAssertEqual(AIPageFile.page(of: "en-0.md", reader: "en"), 0)
        XCTAssertNil(AIPageFile.page(of: "fr-12.md", reader: "en"))
        XCTAssertNil(AIPageFile.page(of: "ovisocr2-12.md", reader: "en"))
        XCTAssertNil(AIPageFile.page(of: "en-12.md.bak", reader: "en"))
        XCTAssertNil(AIPageFile.page(of: "en-.md", reader: "en"))
        XCTAssertNil(AIPageFile.page(of: "en-1a.md", reader: "en"))
        XCTAssertNil(AIPageFile.page(of: "ten-3.md", reader: "en"), "préfixe exact")
        XCTAssertEqual(AIPageFile.name(reader: "en", page: 4), "en-4.md")
        XCTAssertEqual(AIPageFile.translationReaders, ["fr", "en"])
    }
}
