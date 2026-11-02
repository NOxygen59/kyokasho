// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import OCRKit

final class OCRRotationTests: XCTestCase {
    func testRotatingBoxesClockwise() {
        let box = NormBox(x: 0.1, y: 0.2, w: 0.3, h: 0.1)
        let line = OCRLine(text: "字", box: box, charBoxes: [box], measuredCharBoxes: true,
                           vertical: false, confidence: 1)
        let source = OCRPage(engine: OCREngineID.pdfText, lines: [line], durationMs: 1)

        let clockwise = source.rotatedClockwise(90).lines[0]
        XCTAssertEqual(clockwise.box.x, 0.7, accuracy: 0.000_001)
        XCTAssertEqual(clockwise.box.y, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(clockwise.box.w, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(clockwise.box.h, 0.3, accuracy: 0.000_001)
        XCTAssertTrue(clockwise.vertical)

        let restored = source.rotatedClockwise(90).rotatedClockwise(270).lines[0]
        XCTAssertEqual(restored.box.x, box.x, accuracy: 0.000_001)
        XCTAssertEqual(restored.box.y, box.y, accuracy: 0.000_001)
        XCTAssertEqual(restored.box.w, box.w, accuracy: 0.000_001)
        XCTAssertEqual(restored.box.h, box.h, accuracy: 0.000_001)
        XCTAssertFalse(restored.vertical)
    }
}
