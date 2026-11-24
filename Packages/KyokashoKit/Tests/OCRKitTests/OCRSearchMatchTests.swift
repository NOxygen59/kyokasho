// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import XCTest

/// Surlignage de 2 s du mot d'un résultat de recherche (1.6.4) : boîtes des bons caractères, ligne par ligne.
final class OCRSearchMatchTests: XCTestCase {
    private func line(_ text: String, y: Double = 0.2) -> OCRLine {
        let boxes = text.enumerated().map { NormBox(x: Double($0.offset) * 0.1, y: y, w: 0.1, h: 0.05) }
        return OCRLine(text: text, box: NormBox(x: 0, y: y, w: 1, h: 0.05), charBoxes: boxes,
                       measuredCharBoxes: true, vertical: false, confidence: 1)
    }

    func testFindsTheCharactersOfTheWord() {
        let page = OCRPage(engine: "test", lines: [line("店員：いらっしゃいませ。"), line("こちらは試着室です。")], durationMs: 0)
        let groups = page.matchBoxes(of: "試着室")
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.map(\.x) ?? [], [0.4, 0.5, 0.6], accuracy: 1e-9)
    }

    func testWordCutBetweenTwoLinesGivesOneGroupPerLine() {
        // Même recherche que `OCRService.search` : lignes mises bout à bout.
        let page = OCRPage(engine: "test", lines: [line("こちらは試", y: 0.2), line("着室です。", y: 0.3)], durationMs: 0)
        let groups = page.matchBoxes(of: "試着室")
        XCTAssertEqual(groups.map(\.count), [1, 2])
        XCTAssertEqual(groups[0][0].y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(groups[1].map(\.x), [0.0, 0.1], accuracy: 1e-9)
    }

    func testOnlyTheFirstOccurrenceLikeTheExcerpt() {
        // L'extrait des résultats montre la première occurrence : sans ses boîtes, rien plutôt qu'un autre endroit.
        var broken = line("試着室", y: 0.1)
        broken.charBoxes = []
        let page = OCRPage(engine: "test", lines: [broken, line("ここは試着室", y: 0.4)], durationMs: 0)
        XCTAssertTrue(page.matchBoxes(of: "試着室").isEmpty)
        let twice = OCRPage(engine: "test", lines: [line("試着室と試着室", y: 0.4)], durationMs: 0)
        XCTAssertEqual(twice.matchBoxes(of: "試着室").first?.first?.x ?? -1, 0.0, accuracy: 1e-9)
    }

    func testIgnoresWidthCaseAndSurroundingSpaces() {
        let page = OCRPage(engine: "test", lines: [line("ＰＤＦ page")], durationMs: 0)
        XCTAssertEqual(page.matchBoxes(of: " pdf ").first?.count, 3)
        XCTAssertEqual(page.matchBoxes(of: "PAGE").first?.first?.x ?? -1, 0.4, accuracy: 1e-9)
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
