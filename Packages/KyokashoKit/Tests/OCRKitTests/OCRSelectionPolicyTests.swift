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

    /// Le cas du manuel transféré : Auto, scan, NDLOCR et PP-OCRv5 absents de l'iPad, lectures NDLOCR et Vision présentes.
    /// La lecture NDLOCR est retenue ; Vision seulement pour une page jamais lue.
    func testAutoPrefersAnExistingNDLOCRReadingEvenWhenItsModelIsMissing() {
        let order = OCRSelectionPolicy.cacheOrder(choice: .auto, pinned: nil, hasTextLayer: false)
        let present = [page(OCREngineID.vision), page(OCREngineID.ndlocr)]
        let found = order.compactMap { engine in present.first { $0.engine == engine } }
        XCTAssertEqual(OCRSelectionPolicy.retained(among: found, prioritizingCorrections: true)?.engine, OCREngineID.ndlocr)
        XCTAssertEqual(OCRSelectionPolicy.engineToRead(choice: .auto, pinned: nil, hasTextLayer: false, isInstalled: none),
                       OCREngineID.vision)
    }

    /// D7 (revue Codex de d87e048, R3) : en Auto sans choix pour la page, la version corrigée à la main passe d'abord.
    func testAutoRetainsTheCorrectedReadingFirst() {
        let found = [page(OCREngineID.ndlocr), page(OCREngineID.vision, edited: true)]
        XCTAssertTrue(OCRSelectionPolicy.prioritizesCorrections(choice: .auto, pinned: nil))
        XCTAssertEqual(OCRSelectionPolicy.retained(among: found, prioritizingCorrections: true)?.engine, OCREngineID.vision)
        // Plusieurs versions corrigées : ordre de la politique. Aucune n'est supprimée ni déplacée.
        let both = [page(OCREngineID.ndlocr, edited: true), page(OCREngineID.vision, edited: true)]
        XCTAssertEqual(OCRSelectionPolicy.retained(among: both, prioritizingCorrections: true)?.engine, OCREngineID.ndlocr)
        XCTAssertNil(OCRSelectionPolicy.retained(among: [], prioritizingCorrections: true))
    }

    /// Choix explicite (réglage ou page) : l'intention de l'utilisateur prime, la priorité des corrections ne s'applique pas.
    func testExplicitChoiceIgnoresCorrectionPriority() {
        XCTAssertFalse(OCRSelectionPolicy.prioritizesCorrections(choice: .auto, pinned: OCREngineID.ndlocr))
        XCTAssertFalse(OCRSelectionPolicy.prioritizesCorrections(choice: .ndlocr, pinned: nil))
        let found = [page(OCREngineID.ndlocr), page(OCREngineID.vision, edited: true)]
        XCTAssertEqual(OCRSelectionPolicy.retained(among: found, prioritizingCorrections: false)?.engine, OCREngineID.ndlocr)
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
