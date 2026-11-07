// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import OCRKit
import ReaderCore
import XCTest

/// Règle unique de l'OCR retenu (plan de reconstruction de l'OCR, étape 1 ; enquête furigana iPad / Mac du 07/11/2026).
final class OCRSelectionPolicyTests: XCTestCase {
    private let none: (String) -> Bool = { _ in false }

    private func page(_ engine: String, edited: Bool = false) -> OCRPage {
        var line = OCRLine(text: "字", box: NormBox(x: 0, y: 0, w: 1, h: 1), charBoxes: [], measuredCharBoxes: false,
                           vertical: true, confidence: 1)
        line.edited = edited ? true : nil
        return OCRPage(engine: engine, lines: [line], durationMs: 1)
    }

    /// Lectures présentes, rangées dans l'ordre de recherche de la règle.
    private func found(_ pages: [OCRPage], choice: OCREngineChoice, pinned: String?, hasTextLayer: Bool = false) -> [OCRPage] {
        OCRSelectionPolicy.lookupOrder(choice: choice, pinned: pinned, hasTextLayer: hasTextLayer)
            .compactMap { engine in pages.first { $0.engine == engine } }
    }

    private func retained(_ pages: [OCRPage], choice: OCREngineChoice, pinned: String? = nil) -> String? {
        let order = OCRSelectionPolicy.cacheOrder(choice: choice, pinned: pinned, hasTextLayer: false)
        return OCRSelectionPolicy.retained(among: found(pages, choice: choice, pinned: pinned), choiceOrder: order)?.engine
    }

    /// Le cas du manuel transféré : Auto, scan, NDLOCR et PP-OCRv5 absents de l'iPad, lectures NDLOCR et Vision présentes.
    /// La lecture NDLOCR est retenue ; Vision seulement pour une page jamais lue.
    func testAutoPrefersAnExistingNDLOCRReadingEvenWhenItsModelIsMissing() {
        XCTAssertEqual(retained([page(OCREngineID.vision), page(OCREngineID.ndlocr)], choice: .auto), OCREngineID.ndlocr)
        XCTAssertEqual(OCRSelectionPolicy.engineToRead(choice: .auto, pinned: nil, hasTextLayer: false, isInstalled: none),
                       OCREngineID.vision)
    }

    /// D7 (revue Codex de d87e048, R3) : la version corrigée à la main passe d'abord.
    func testAutoRetainsTheCorrectedReadingFirst() {
        XCTAssertEqual(retained([page(OCREngineID.ndlocr), page(OCREngineID.vision, edited: true)], choice: .auto), OCREngineID.vision)
        // Plusieurs versions corrigées : ordre de la politique. Aucune n'est supprimée ni déplacée.
        XCTAssertEqual(retained([page(OCREngineID.ndlocr, edited: true), page(OCREngineID.vision, edited: true)], choice: .auto),
                       OCREngineID.ndlocr)
        XCTAssertNil(OCRSelectionPolicy.retained(among: [], choiceOrder: [OCREngineID.ndlocr]))
    }

    /// Décision F4 de NOxygen59 (07/11/2026) : la correction passe d'abord **toujours**, même face au moteur réglé ou
    /// choisi dans le menu du panneau. Parmi plusieurs versions corrigées, le moteur choisi passe d'abord.
    func testCorrectionWinsOverExplicitAndPinnedChoices() {
        let pages = [page(OCREngineID.ndlocr), page(OCREngineID.vision, edited: true)]
        XCTAssertEqual(retained(pages, choice: .ndlocr), OCREngineID.vision)
        XCTAssertEqual(retained(pages, choice: .auto, pinned: OCREngineID.ndlocr), OCREngineID.vision)
        let both = [page(OCREngineID.ndlocr, edited: true), page(OCREngineID.vision, edited: true)]
        XCTAssertEqual(retained(both, choice: .auto, pinned: OCREngineID.vision), OCREngineID.vision)
        XCTAssertTrue(OCRSelectionPolicy.isCorrected(page(OCREngineID.vision, edited: true)))
        XCTAssertFalse(OCRSelectionPolicy.isCorrected(page(OCREngineID.vision)))
    }

    /// Sans correction, un choix explicite reste seul : la lecture d'un autre moteur n'est pas prise à sa place.
    func testWithoutCorrectionExplicitChoiceStaysAlone() {
        XCTAssertNil(retained([page(OCREngineID.vision)], choice: .ndlocr))
        XCTAssertNil(retained([page(OCREngineID.vision)], choice: .auto, pinned: OCREngineID.ndlocr))
        XCTAssertEqual(retained([page(OCREngineID.vision), page(OCREngineID.ndlocr)], choice: .vision), OCREngineID.vision)
        // L'ordre de recherche commence par le choix, puis le reste sans doublon.
        XCTAssertEqual(OCRSelectionPolicy.lookupOrder(choice: .vision, pinned: OCREngineID.glmocr, hasTextLayer: false),
                       ["glmocr", "vision", "ndlocr", "ppocr5"])
    }

    func testAutoOrderIsTextLayerThenNDLOCRPPOCRGLMVision() {
        XCTAssertEqual(OCRSelectionPolicy.cacheOrder(choice: .auto, pinned: nil, hasTextLayer: true),
                       ["pdfText", "ndlocr", "ppocr5", "glmocr", "vision"])
        XCTAssertEqual(OCRSelectionPolicy.cacheOrder(choice: .auto, pinned: nil, hasTextLayer: false),
                       ["ndlocr", "ppocr5", "glmocr", "vision"])
    }

    func testAutoReadsWithTheFirstInstalledJapaneseModel() {
        XCTAssertEqual(OCRSelectionPolicy.engineToRead(choice: .auto, pinned: nil, hasTextLayer: false,
                                                       isInstalled: { $0 == OCREngineID.ppocr5 }), OCREngineID.ppocr5)
        XCTAssertEqual(OCRSelectionPolicy.engineToRead(choice: .auto, pinned: nil, hasTextLayer: false,
                                                       isInstalled: { _ in true }), OCREngineID.ndlocr)
        XCTAssertEqual(OCRSelectionPolicy.engineToRead(choice: .auto, pinned: nil, hasTextLayer: true,
                                                       isInstalled: { _ in true }), OCREngineID.pdfText)
    }

    /// Un moteur réglé, ou choisi pour la page, est seul : Vision choisi explicitement l'emporte sur un cache NDLOCR.
    func testExplicitChoiceAndPageChoiceWin() {
        XCTAssertEqual(OCRSelectionPolicy.cacheOrder(choice: .vision, pinned: nil, hasTextLayer: false), [OCREngineID.vision])
        XCTAssertEqual(OCRSelectionPolicy.cacheOrder(choice: .auto, pinned: OCREngineID.vision, hasTextLayer: true),
                       [OCREngineID.vision])
        XCTAssertEqual(OCRSelectionPolicy.cacheOrder(choice: .vision, pinned: OCREngineID.ndlocr, hasTextLayer: false),
                       [OCREngineID.ndlocr])
        XCTAssertEqual(OCRSelectionPolicy.engineToRead(choice: .ndlocr, pinned: nil, hasTextLayer: true, isInstalled: none),
                       OCREngineID.ndlocr)
        XCTAssertEqual(OCRSelectionPolicy.engineToRead(choice: .auto, pinned: OCREngineID.glmocr, hasTextLayer: true,
                                                       isInstalled: none), OCREngineID.glmocr)
    }
}
