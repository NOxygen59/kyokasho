// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import OCRKit
import ReaderCore
import XCTest

/// Règle unique de l'OCR retenu (plan de reconstruction de l'OCR, étape 1 ; enquête furigana iPad / Mac du 07/11/2026).
final class OCRSelectionPolicyTests: XCTestCase {
    private let none: (String) -> Bool = { _ in false }

    /// Le cas du manuel transféré : Auto, scan, NDLOCR et PP-OCRv5 absents de l'iPad, caches NDLOCR et Vision présents.
    /// Lecture faite par NDLOCR en tête ; Vision seulement pour une page jamais lue.
    func testAutoPrefersAnExistingNDLOCRReadingEvenWhenItsModelIsMissing() {
        XCTAssertEqual(OCRSelectionPolicy.cacheOrder(choice: .auto, pinned: nil, hasTextLayer: false).first, OCREngineID.ndlocr)
        XCTAssertEqual(OCRSelectionPolicy.engineToRead(choice: .auto, pinned: nil, hasTextLayer: false, isInstalled: none),
                       OCREngineID.vision)
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
