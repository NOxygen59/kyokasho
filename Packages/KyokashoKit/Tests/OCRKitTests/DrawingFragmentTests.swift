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

/// Contre-revue du chantier 1.5.0 : les bouts de dessin restent dans l'OCR, seul le dessin des zones les écarte ;
/// des boîtes en double ne passent plus pour des mesures.
final class OCRRawAndDuplicateTests: XCTestCase {
    private func line(_ text: String, vertical: Bool, confidence: Double, boxes: [NormBox] = [], measured: Bool = false) -> OCRLine {
        OCRLine(text: text, box: NormBox(x: 0.5, y: 0.2, w: 0.02, h: 0.3), charBoxes: boxes, measuredCharBoxes: measured,
                vertical: vertical, confidence: confidence)
    }

    func testFragmentsLeaveOnlyTheDrawnZones() {
        let page = OCRPage(engine: "vision", lines: [line("何だと", vertical: true, confidence: 0.9),
                                                     line("ここ", vertical: true, confidence: 0.9),
                                                     line("/", vertical: true, confidence: 0.9)], durationMs: 0)
        XCTAssertEqual(page.lines.count, 3)
        XCTAssertEqual(page.withoutDrawingFragments().lines.map(\.text), ["何だと", "ここ"])
    }

    func testPartialDuplicateBoxesAreNotMeasured() {
        let a = NormBox(x: 0.5, y: 0.2, w: 0.02, h: 0.03), b = NormBox(x: 0.5, y: 0.25, w: 0.02, h: 0.03)
        XCTAssertFalse(CharacterLayout.validate([a, a, b], count: 3, vertical: true))
        XCTAssertTrue(CharacterLayout.validate([a, b], count: 2, vertical: true))
        let old = line("何だ字", vertical: true, confidence: 0.9, boxes: [a, a, b], measured: true).downgradingDuplicateBoxes()
        XCTAssertFalse(old.measuredCharBoxes)
        XCTAssertEqual(old.text, "何だ字")
        XCTAssertEqual(old.charBoxes.count, 3)
    }

    func testSharedOriginsAreNotMeasured() {
        let a = NormBox(x: 0.5, y: 0.2, w: 0.02, h: 0.03), wide = NormBox(x: 0.5, y: 0.2, w: 0.04, h: 0.03)
        XCTAssertFalse(CharacterLayout.validate([a, wide], count: 2, vertical: true))
    }

    func testUndoingACorrectionDowngradesOldDuplicateBoxes() {
        let a = NormBox(x: 0.5, y: 0.2, w: 0.02, h: 0.03), b = NormBox(x: 0.5, y: 0.25, w: 0.02, h: 0.03)
        var line = line("何だ字", vertical: true, confidence: 0.9, boxes: [a, a, b], measured: true)
        line.originalText = "何だ字"
        line.originalCharBoxes = [a, a, b]
        line.originalMeasuredCharBoxes = true
        line.text = "何だ子"
        let undone = line.revertingCorrection
        XCTAssertEqual(undone.text, "何だ字")
        XCTAssertFalse(undone.measuredCharBoxes)
        XCTAssertFalse(CharacterLayout.hasDuplicates(undone.charBoxes))
    }
}
