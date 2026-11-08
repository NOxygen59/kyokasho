// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import OCRKit
import ReaderCore
import XCTest

/// Libellé du menu des moteurs du panneau Texte (recette iPad 1.5.3, retour 2.10 : le logo affiché ne correspondait
/// pas au moteur choisi). Le libellé montre le moteur du texte **affiché** et signale quand il diffère du choix.
final class OCREngineIndicatorTests: XCTestCase {
    private func page(_ engine: String, edited: Bool = false) -> OCRPage {
        var line = OCRLine(text: "字", box: NormBox(x: 0, y: 0, w: 1, h: 1), charBoxes: [], measuredCharBoxes: false,
                           vertical: true, confidence: 1)
        line.edited = edited ? true : nil
        return OCRPage(engine: engine, lines: [line], durationMs: 1)
    }

    /// Cas de la recette : NDLOCR choisi dans le menu, mais une correction faite sur Apple Vision passe d'abord (F4).
    func testCorrectionOfAnotherEngineIsShownAndFlagged() {
        let indicator = OCREngineIndicator(page: page(OCREngineID.vision, edited: true), pinned: OCREngineID.ndlocr, setting: .auto)
        XCTAssertEqual(indicator.shown, OCREngineID.vision)
        XCTAssertEqual(indicator.chosen, OCREngineID.ndlocr)
        XCTAssertTrue(indicator.corrected)
        XCTAssertTrue(indicator.differs)
    }

    /// Le moteur choisi est celui affiché : rien à signaler.
    func testSameEngineDoesNotDiffer() {
        let indicator = OCREngineIndicator(page: page(OCREngineID.ndlocr), pinned: OCREngineID.ndlocr, setting: .vision)
        XCTAssertFalse(indicator.differs)
        XCTAssertFalse(indicator.corrected)
    }

    /// Sans choix pour la page, le réglage du document compte ; en Auto, il n'y a pas de choix à comparer.
    func testDocumentSettingIsTheChoiceWithoutPin() {
        XCTAssertEqual(OCREngineIndicator(page: page(OCREngineID.vision), pinned: nil, setting: .ndlocr).chosen, OCREngineID.ndlocr)
        XCTAssertTrue(OCREngineIndicator(page: page(OCREngineID.vision), pinned: nil, setting: .ndlocr).differs)
        XCTAssertNil(OCREngineIndicator(page: page(OCREngineID.vision), pinned: nil, setting: .auto).chosen)
        XCTAssertFalse(OCREngineIndicator(page: page(OCREngineID.vision), pinned: nil, setting: .auto).differs)
        XCTAssertEqual(OCREngineIndicator(page: nil, pinned: nil, setting: .pdfText).chosen, OCREngineID.pdfText)
    }

    /// Page pas encore lue : rien d'affiché, donc pas d'écart signalé.
    func testNoPageNeverDiffers() {
        let indicator = OCREngineIndicator(page: nil, pinned: OCREngineID.ndlocr, setting: .auto)
        XCTAssertNil(indicator.shown)
        XCTAssertFalse(indicator.differs)
    }
}
