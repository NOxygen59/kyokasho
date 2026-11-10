// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
import OCRKit

// P2 n°2 (revue R2) : le choix de langue OCR suit le document remplacé. Le remap ne doit
// jamais écraser une clé d'arrivée déjà présente (donnée de l'arrivée restée en place),
// retirer la clé d'origine après copie, et ne rien faire quand il n'y a pas de choix suivi.
final class OCRTargetLanguageRemapTests: XCTestCase {
    private let oldId = "langue-old-" + UUID().uuidString
    private let newId = "langue-new-" + UUID().uuidString

    override func tearDown() {
        OCRTargetLanguage.forget(oldId)
        OCRTargetLanguage.forget(newId)
        super.tearDown()
    }

    func testRemapMovesTheChoiceAndReplaysAsANoOp() {
        OCRTargetLanguage.set(.automatic, forDocument: oldId)
        OCRTargetLanguage.remap(from: oldId, to: newId)
        XCTAssertEqual(OCRTargetLanguage.forDocument(newId), .automatic)
        XCTAssertEqual(OCRTargetLanguage.forDocument(oldId), .japanese, "ancienne clé retirée : la valeur par défaut revient")

        // Reprise rejouée (second lancement) : plus rien à déplacer, rien d'abîmé.
        OCRTargetLanguage.remap(from: oldId, to: newId)
        XCTAssertEqual(OCRTargetLanguage.forDocument(newId), .automatic)
    }

    func testRemapNeverOverwritesAnExistingTarget() {
        OCRTargetLanguage.set(.japanese, forDocument: oldId)
        OCRTargetLanguage.set(.automatic, forDocument: newId) // l'arrivée a déjà son propre choix
        OCRTargetLanguage.remap(from: oldId, to: newId)
        XCTAssertEqual(OCRTargetLanguage.forDocument(newId), .automatic, "choix de l'arrivée intact")
        XCTAssertEqual(OCRTargetLanguage.forDocument(oldId), .japanese, "clé d'origine consommée comme les autres")
    }

    func testRemapWithoutAChoiceDoesNothing() {
        OCRTargetLanguage.remap(from: oldId, to: newId)
        XCTAssertEqual(OCRTargetLanguage.forDocument(newId), .japanese)
    }
}
