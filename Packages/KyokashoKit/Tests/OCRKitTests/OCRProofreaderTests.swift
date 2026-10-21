// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import OCRKit
import XCTest

final class OCRProofreaderTests: XCTestCase {
    /// Petit dictionnaire : plus long mot connu à chaque position, sinon un caractère inconnu.
    private let words: Set<String> = ["未来", "天井", "を", "張る", "場合", "土地", "の"]
    private func segment(_ text: String) -> [OCRProofreader.Segment] {
        let chars = Array(text)
        var out: [OCRProofreader.Segment] = []
        var i = 0
        while i < chars.count {
            var found = 0
            for len in stride(from: min(4, chars.count - i), through: 1, by: -1) where words.contains(String(chars[i..<(i + len)])) {
                found = len
                break
            }
            out.append(found > 0 ? (found, true) : (1, false))
            i += max(found, 1)
        }
        return out
    }

    private func line(_ text: String, confidence: Double = 0.95) -> OCRLine {
        OCRLine(text: text, box: NormBox(x: 0, y: 0, w: 1, h: 0.1), charBoxes: Array(repeating: NormBox(x: 0, y: 0, w: 0.1, h: 0.1), count: text.count),
                measuredCharBoxes: false, vertical: false, confidence: confidence)
    }

    func testFixesLookalike() async {
        let fixed = await OCRProofreader.proofread(line("末来の土地"), segment: segment)
        XCTAssertEqual(fixed.text, "未来の土地")
        XCTAssertEqual(fixed.doubt, [])
    }

    func testKeepsUnknownWhenNoFix() async {
        let fixed = await OCRProofreader.proofread(line("天井を張る鬱"), segment: segment)
        XCTAssertEqual(fixed.text, "天井を張る鬱")
        XCTAssertEqual(fixed.doubt, [5])
        XCTAssertEqual(OCRProofreader.doubtful(OCRPage(engine: "x", lines: [fixed], durationMs: 0)), [0])
    }

    func testEditedLineUntouched() async {
        var l = line("末来")
        l.edited = true
        let out = await OCRProofreader.proofread(l, segment: segment)
        XCTAssertEqual(out.text, "末来")
    }

    func testLowConfidenceIsDoubtful() async {
        let ok = await OCRProofreader.proofread(line("天井", confidence: 0.5), segment: segment)
        XCTAssertEqual(OCRProofreader.doubtful(OCRPage(engine: "x", lines: [ok], durationMs: 0)), [0])
    }

    func testNoDictionaryLeavesPageUnproofread() async {
        let page = await OCRProofreader.proofread(OCRPage(engine: "x", lines: [line("末来")], durationMs: 0)) { _ in [] }
        XCTAssertNotEqual(page.proofread, true)
        XCTAssertNil(page.lines[0].doubt)
        XCTAssertEqual(page.lines[0].text, "末来")
    }
}
