// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import XCTest

/// Surlignage de 2 s du mot d'un résultat de recherche (1.6.4) : boîtes des bons caractères.
final class OCRSearchMatchTests: XCTestCase {
    private func line(_ text: String) -> OCRLine {
        let boxes = text.enumerated().map { NormBox(x: Double($0.offset) * 0.1, y: 0.2, w: 0.1, h: 0.05) }
        return OCRLine(text: text, box: NormBox(x: 0, y: 0.2, w: 1, h: 0.05), charBoxes: boxes,
                       measuredCharBoxes: true, vertical: false, confidence: 1)
    }

    func testFindsTheCharactersOfTheWord() {
        let page = OCRPage(engine: "test", lines: [line("店員：いらっしゃいませ。"), line("こちらは試着室です。")], durationMs: 0)
        let boxes = page.matchBoxes(of: "試着室")
        XCTAssertEqual(boxes.map(\.x), [0.4, 0.5, 0.6].map { $0 }, accuracy: 1e-9)
    }

    func testIgnoresWidthCaseAndSurroundingSpaces() {
        let page = OCRPage(engine: "test", lines: [line("ＰＤＦ page")], durationMs: 0)
        XCTAssertEqual(page.matchBoxes(of: " pdf ").count, 3)
        XCTAssertEqual(page.matchBoxes(of: "PAGE").first?.x ?? -1, 0.4, accuracy: 1e-9)
    }

    func testNothingWhenAbsentEmptyOrBoxesMissing() {
        var broken = line("試着室")
        broken.charBoxes = []
        let page = OCRPage(engine: "test", lines: [line("店員"), broken], durationMs: 0)
        XCTAssertTrue(page.matchBoxes(of: "試着室").isEmpty)
        XCTAssertTrue(page.matchBoxes(of: "  ").isEmpty)
        XCTAssertTrue(page.matchBoxes(of: "漢字").isEmpty)
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
