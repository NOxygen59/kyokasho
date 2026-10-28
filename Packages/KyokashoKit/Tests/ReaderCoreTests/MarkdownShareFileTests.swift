// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Recette 1.3.2 (61) : le bouton « Markdown » partage un vrai fichier écrit d'avance.
final class MarkdownShareFileTests: XCTestCase {
    func testFileNameIsSafe() {
        XCTAssertEqual(MarkdownShareFile.fileName(for: "Manuel 1/2 : kanji"), "Manuel 1-2 - kanji.md")
        XCTAssertEqual(MarkdownShareFile.fileName(for: "   "), "Notes.md")
    }

    func testWritesExportedTextAsUTF8File() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let text = MarkdownExporter.export(title: "日本語 synthétique",
                                           comments: [PageComment(documentId: "d", pageIndex: 0, body: "Note 漢字")])
        let url = try MarkdownShareFile.write(text, title: "日本語 synthétique", in: folder)
        XCTAssertEqual(url.lastPathComponent, "日本語 synthétique.md")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text)
        XCTAssertTrue(text.contains("Note 漢字"))
    }
}
