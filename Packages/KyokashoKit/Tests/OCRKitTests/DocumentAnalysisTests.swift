// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import OCRKit
import XCTest

final class DocumentAnalysisTests: XCTestCase {
    private func page(_ lines: [String]) -> OCRPage {
        OCRPage(engine: "ndlocr", lines: lines.map {
            OCRLine(text: $0, box: NormBox(x: 0, y: 0, w: 1, h: 0.1), charBoxes: [], measuredCharBoxes: false, vertical: false, confidence: 1)
        }, durationMs: 0)
    }

    func testMajorityAndReliability() async {
        let base = page(["天井を張る場合、", "末来の土地", "小屋裏にスペース"])
        let result = await DocumentAnalysis.vote(
            source: 0, base: base,
            readings: ["ovis": "天井を張る場合、\n未来の土地\n小屋裏にスペース", "glm": "天井を張る場合、\n未来の土地\n小屋裏にスベース"],
            tieBreak: { $0.first })
        XCTAssertEqual(result.lines, 3)
        // Ligne 0 : 3 voix ; ligne 2 : OCR + Ovis contre GLM → confirmée ; ligne 1 : Ovis + GLM contre l'OCR.
        XCTAssertEqual(result.confirmed, 2)
        XCTAssertEqual(result.disagreements.map(\.line), [1])
        XCTAssertEqual(result.disagreements.first?.advised, "未来の土地")
        XCTAssertEqual(result.reliability, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testTwoReadersTieUsesDictionary() async {
        let base = page(["末来の土地"])
        let result = await DocumentAnalysis.vote(source: 0, base: base, readings: ["ovis": "未来の土地"], tieBreak: { _ in "未来の土地" })
        XCTAssertEqual(result.confirmed, 0)
        XCTAssertEqual(result.disagreements.first?.advised, "未来の土地")
    }
}
