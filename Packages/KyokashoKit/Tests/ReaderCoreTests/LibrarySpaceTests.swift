// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import XCTest

final class LibrarySpaceTests: XCTestCase {
    func testPersistedIdentifiersAndInvalidSelection() {
        XCTAssertEqual(LibrarySpace.study.paletteKey, "appearance.ipadLibrary.palette.study")
        XCTAssertEqual(LibrarySpace.manga.paletteKey, "appearance.ipadLibrary.palette.manga")
        XCTAssertEqual(LibrarySpace.paletteID("paper", available: ["paper"]), "paper")
        XCTAssertNil(LibrarySpace.paletteID("retired", available: ["paper"]))
        XCTAssertNil(LibrarySpace.paletteID(nil, available: ["paper"]))
    }

    func testDocumentSpaceTakesPriorityAndReturnRestoresLibrary() {
        let overrides: [LibrarySpace: String] = [.study: "paper", .manga: "night"]
        let available: Set<String> = ["paper", "night"]
        let comic = LibraryDocument(id: "comic", title: "Manga", originalFileName: "manga.cbz", pageCount: 1, fileSize: 1)
        let book = LibraryDocument(id: "book", title: "Livre", originalFileName: "book.pdf", pageCount: 1, fileSize: 1)
        XCTAssertEqual(LibrarySpace(document: comic), .manga)
        XCTAssertEqual(LibrarySpace(document: book), .study)
        XCTAssertEqual(LibrarySpace.effectivePaletteID(general: "general", overrides: overrides, library: .study,
                                                       document: LibrarySpace(document: comic), available: available, enabled: true), "night")
        XCTAssertEqual(LibrarySpace.effectivePaletteID(general: "general", overrides: overrides, library: .manga,
                                                       document: LibrarySpace(document: book), available: available, enabled: true), "paper")
        XCTAssertEqual(LibrarySpace.effectivePaletteID(general: "general", overrides: overrides, library: .study,
                                                       document: nil, available: available, enabled: true), "paper")
    }

    func testFallbackForMissingInvalidOrDisabledOverrides() {
        for overrides: [LibrarySpace: String] in [[:], [.manga: "retired"]] {
            XCTAssertEqual(LibrarySpace.effectivePaletteID(general: "general", overrides: overrides, library: .study,
                                                           document: .manga, available: ["night"], enabled: true), "general")
        }
        XCTAssertEqual(LibrarySpace.effectivePaletteID(general: "general", overrides: [.manga: "night"], library: .study,
                                                       document: .manga, available: ["night"], enabled: false), "general")
    }
}
