// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

final class AIReadingExportTests: XCTestCase {
    func testTextListsOnlyReadPagesWithTheirLabels() {
        let text = AIReadingExport.text(title: "Manuel", reader: "ovisocr2", totalPages: 3,
                                        pages: [.init(label: "1", text: "天井\n"), .init(label: "iii", text: "床")])
        XCTAssertEqual(text, """
        Kyōkasho : lectures ovisocr2
        Document : Manuel
        Pages lues : 2 sur 3

        === Page 1 ===
        天井

        === Page iii ===
        床

        """)
    }

    func testFileIsWrittenWithASafeName() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try AIReadingExport.write("天井", title: "Tome 1/2", reader: "ovisocr2", in: folder)
        XCTAssertEqual(url.lastPathComponent, "Tome 1-2 - lectures ovisocr2.txt")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "天井")
    }
}
