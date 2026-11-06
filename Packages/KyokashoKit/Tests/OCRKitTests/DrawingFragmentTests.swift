// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import OCRKit

/// Page de manga : un caractère seul et bien lu reste dans l'OCR ; un bout de dessin douteux part.
final class DrawingFragmentTests: XCTestCase {
    private func line(_ text: String, confidence: Double, ruby: Bool? = nil) -> OCRLine {
        var line = OCRLine(text: text, box: NormBox(x: 0.5, y: 0.5, w: 0.02, h: 0.03), charBoxes: [], measuredCharBoxes: false,
                           vertical: true, confidence: confidence)
        line.hasPrintedRuby = ruby
        return line
    }

    func testConfidentLoneKanjiOrKanaIsKept() {
        for text in ["何", "火", "雨", "あ", "ア"] {
            XCTAssertFalse(VisionOCREngine.isDrawingFragment(line(text, confidence: 0.9)), text)
        }
    }

    func testDoubtfulOrNonJapaneseLoneCharacterIsRemoved() {
        XCTAssertTrue(VisionOCREngine.isDrawingFragment(line("何", confidence: 0.3)))
        XCTAssertTrue(VisionOCREngine.isDrawingFragment(line("/", confidence: 0.9)))
        XCTAssertTrue(VisionOCREngine.isDrawingFragment(line("I", confidence: 0.9)))
    }

    func testNumbersLongerLinesAndRubyLinesAreKept() {
        XCTAssertFalse(VisionOCREngine.isDrawingFragment(line("7", confidence: 0.2)))
        XCTAssertFalse(VisionOCREngine.isDrawingFragment(line("何だ", confidence: 0.2)))
        XCTAssertFalse(VisionOCREngine.isDrawingFragment(line("/", confidence: 0.2, ruby: false)))
    }
}

/// Texte vertical : positions mesurées seulement dans l'ordre et sans case partagée.
final class VerticalReadingOrderTests: XCTestCase {
    private func chars(_ cells: [ClosedRange<Int>]) -> [VerticalTextReader.ReadCharacter] {
        cells.map { VerticalTextReader.ReadCharacter(character: "字", cells: $0) }
    }

    func testIncreasingCellsAreTrusted() {
        XCTAssertTrue(VerticalTextReader.inReadingOrder(chars([0...0, 1...1, 2...3, 4...4])))
    }

    func testRepeatedOrBackwardCellsAreNotTrusted() {
        XCTAssertFalse(VerticalTextReader.inReadingOrder(chars([0...0, 1...1, 1...1])))
        XCTAssertFalse(VerticalTextReader.inReadingOrder(chars([0...0, 2...2, 1...1])))
        XCTAssertFalse(VerticalTextReader.inReadingOrder(chars([0...1, 1...2])))
    }
}
