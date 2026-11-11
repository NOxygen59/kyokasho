// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import OCRKit
import XCTest

/// Bouton « Copier » du panneau Texte : il copie le texte **affiché** (relecture de 6cc15fc, P2).
final class OCRPanelCopyTests: XCTestCase {
    private let page = OCRPage(engine: OCREngineID.vision, lines: [
        OCRLine(text: "一行目", box: NormBox(x: 0, y: 0, w: 1, h: 0.1), charBoxes: [], measuredCharBoxes: false, vertical: false, confidence: 1),
        OCRLine(text: "二行目", box: NormBox(x: 0, y: 0.2, w: 1, h: 0.1), charBoxes: [], measuredCharBoxes: false, vertical: false, confidence: 1),
    ], durationMs: 1)

    /// Mise en page IA : le Markdown d'OvisOCR2, jamais le texte du moteur OCR.
    func testAILayoutCopiesOvisText() {
        XCTAssertEqual(OCRPanelCopy.text(mode: .aiLayout, page: page, ovis: "# 見出し", translation: nil, showTranslation: false), "# 見出し")
    }

    /// Traduction affichée : c'est elle qui est copiée ; sans traduction, le japonais.
    func testAILayoutCopiesTheShownTranslation() {
        XCTAssertEqual(OCRPanelCopy.text(mode: .aiLayout, page: page, ovis: "日本語", translation: "Français", showTranslation: true), "Français")
        XCTAssertEqual(OCRPanelCopy.text(mode: .aiLayout, page: page, ovis: "日本語", translation: nil, showTranslation: true), "日本語")
        // Traduction présente mais non affichée : le japonais (revue DeepSeek de 39d31d3).
        XCTAssertEqual(OCRPanelCopy.text(mode: .aiLayout, page: page, ovis: "日本語", translation: "Français", showTranslation: false), "日本語")
    }

    /// Mise en page IA sans lecture OvisOCR2 : rien à copier (le texte OCR n'est pas affiché).
    func testAILayoutWithoutOvisCopiesNothing() {
        XCTAssertNil(OCRPanelCopy.text(mode: .aiLayout, page: page, ovis: nil, translation: nil, showTranslation: false))
    }

    func testRawAndFormattedModes() {
        XCTAssertEqual(OCRPanelCopy.text(mode: .raw, page: page, ovis: "x", translation: nil, showTranslation: false), "一行目\n二行目")
        XCTAssertEqual(OCRPanelCopy.text(mode: .formatted, page: page, ovis: "x", translation: nil, showTranslation: false), OCRLayout.markdown(page))
        XCTAssertNil(OCRPanelCopy.text(mode: .raw, page: nil, ovis: nil, translation: nil, showTranslation: false))
    }
}
