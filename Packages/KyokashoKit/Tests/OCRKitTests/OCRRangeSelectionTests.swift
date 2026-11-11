// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import OCRKit
import XCTest

/// RET-020 (#23) : surligner en glissant sur l'OCR.
final class OCRRangeSelectionTests: XCTestCase {
    /// Deux lignes horizontales, une case de 0,1 de large par caractère.
    private func page() -> OCRPage {
        func line(_ text: String, y: Double) -> OCRLine {
            let boxes = (0..<text.count).map { NormBox(x: Double($0) * 0.1, y: y, w: 0.1, h: 0.05) }
            return OCRLine(text: text, box: NormBox(x: 0, y: y, w: Double(text.count) * 0.1, h: 0.05), charBoxes: boxes,
                           measuredCharBoxes: true, vertical: false, confidence: 1)
        }
        return OCRPage(engine: "test", lines: [line("天井を張る", y: 0.1), line("小屋裏", y: 0.2)], durationMs: 0)
    }

    func testAcrossLinesInEitherDirection() {
        let p = page()
        let forward = OCRRangeSelection.segments(in: p, from: (0, 2), to: (1, 1))
        XCTAssertEqual(forward, [.init(line: 0, range: 2..<5), .init(line: 1, range: 0..<2)])
        XCTAssertEqual(OCRRangeSelection.segments(in: p, from: (1, 1), to: (0, 2)), forward)
        XCTAssertEqual(OCRRangeSelection.text(in: p, forward), "を張る\n小屋")
    }

    func testSameLineAndBoxes() {
        let p = page()
        let s = OCRRangeSelection.segments(in: p, from: (0, 3), to: (0, 1))
        XCTAssertEqual(s, [.init(line: 0, range: 1..<4)])
        let box = OCRRangeSelection.boxes(in: p, s)[0]
        XCTAssertEqual(box.x, 0.1, accuracy: 1e-9)
        XCTAssertEqual(box.w, 0.3, accuracy: 1e-9)
        XCTAssertEqual(box.y, 0.1, accuracy: 1e-9)
    }

    func testOutOfRangeIsEmpty() {
        XCTAssertEqual(OCRRangeSelection.segments(in: page(), from: (0, 0), to: (5, 0)), [])
    }
}
