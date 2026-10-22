// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import OCRKit
import XCTest

final class OCRReferenceDiffTests: XCTestCase {
    private func page(_ lines: [String]) -> OCRPage {
        OCRPage(engine: "x", lines: lines.map {
            OCRLine(text: $0, box: NormBox(x: 0, y: 0, w: 1, h: 0.1), charBoxes: [], measuredCharBoxes: false, vertical: false, confidence: 1)
        }, durationMs: 0)
    }

    func testProposesOnlyChangedLines() {
        let p = page(["天井を張る場合、", "末来の土地", "小屋裏にスペース"])
        let ref = "# 見出し\n\n天井を張る場合、**未来**の土地\n\n小屋裏にスペース"
        let s = OCRReferenceDiff.suggestions(p, reference: ref)
        XCTAssertEqual(s.map(\.line), [1])
        XCTAssertEqual(s.first?.proposed, "未来の土地")
    }

    func testIgnoresUnrelatedText() {
        let p = page(["天井を張る場合"])
        XCTAssertTrue(OCRReferenceDiff.suggestions(p, reference: "まったく別の文章です").isEmpty)
    }

    func testAlignedLinesKeepOCRBoxes() {
        // OCR : « 末来の土地 » (末 au lieu de 未), une boîte par caractère ; l'IA lit « 未来の土地 ».
        let boxes = (0..<5).map { NormBox(x: Double($0) * 0.1, y: 0, w: 0.1, h: 0.1) }
        let p = OCRPage(engine: "x", lines: [OCRLine(text: "末来の土地", box: NormBox(x: 0, y: 0, w: 0.5, h: 0.1),
                                                        charBoxes: boxes, measuredCharBoxes: true, vertical: false, confidence: 1)],
                        durationMs: 0)
        let aligned = OCRReferenceDiff.alignedLines(p, reference: "# 未来の土地")
        XCTAssertEqual(aligned.first?.text, "未来の土地")
        XCTAssertEqual(aligned.first?.boxes, boxes)
    }

    func testMarkDifferencesFlagsMismatchedCharacters() {
        let p = page(["天井を張る場合、", "末来の 土地"])
        let marked = OCRReferenceDiff.markDifferences(p, reference: "天井を張る場合、未来の土地")
        XCTAssertEqual(marked.lines[1].doubt, [0])
        XCTAssertEqual(OCRReferenceDiff.markDifferences(marked, reference: "天井を張る場合、未来の土地"), marked)
    }

    func testMatchMarksInsertedCharacters() {
        XCTAssertEqual(OCRReferenceDiff.match(Array("天井板"), Array("天板")), [0, nil, 1])
    }

    func testPlainStripsMarkup() {
        XCTAssertEqual(String(OCRReferenceDiff.plain("## 表\n<table><tr><td>天井</td></tr></table> <img src=\"a\" />")), "表天井")
    }

    func testTextBetweenLinesNotMerged() {
        let p = page(["天井を張る", "小屋裏にスペース"])
        let s = OCRReferenceDiff.suggestions(p, reference: "天井を張る\n図1\n小屋裏にスペース")
        XCTAssertTrue(s.isEmpty, "\(s)")
    }
}
