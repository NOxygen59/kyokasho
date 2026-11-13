// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import XCTest
@testable import ReaderCore

/// C1.4 (audit du 09/11/2026) : cache égalisé mal formé.
final class EqualizedBoxesTests: XCTestCase {
    func testValidCache() {
        XCTAssertEqual(EqualizedBoxes.rects([[0, 0, 10, 20], [1, 2, 3, 4]]),
                       [CGRect(x: 0, y: 0, width: 10, height: 20), CGRect(x: 1, y: 2, width: 3, height: 4)])
        XCTAssertEqual(EqualizedBoxes.rects([]), [])
    }

    func testMalformedLineIsRejectedWithoutCrash() {
        XCTAssertNil(EqualizedBoxes.rects([[0, 0, 10, 20], [1, 2, 3]]))
        XCTAssertNil(EqualizedBoxes.rects([[0, 0, 10, 20, 5]]))
    }

    /// PLAN-DATA03-001 E1 : hauteur la plus fréquente, égalité → la plus grande ; seuil de 3 % ; aller-retour exact
    /// entre page d'origine et page égalisée (cas de l'enquête D-03 : A4 réduite à la hauteur d'un A5, puis l'inverse).
    func testEqualizationRulesAndRoundTrip() {
        XCTAssertEqual(PageEqualization.commonHeight([842, 595, 842]), 842)
        XCTAssertEqual(PageEqualization.commonHeight([842, 595, 595, 842]), 842, "égalité : la plus grande")
        XCTAssertEqual(PageEqualization.commonHeight([595, 842, 842, 595]), 842, "indépendant de l'ordre")
        XCTAssertNil(PageEqualization.commonHeight([]))
        XCTAssertNil(PageEqualization.factor(height: 830, common: 842), "écart de 1,4 % : page gardée telle quelle")
        XCTAssertEqual(try XCTUnwrap(PageEqualization.factor(height: 595, common: 842)), 842.0 / 595.0, accuracy: 1e-9)
        XCTAssertEqual(PageEqualization.displayedHeight(box: CGRect(x: 0, y: 0, width: 595, height: 842), rotation: 90), 595)

        let box = CGRect(x: 10, y: 20, width: 595, height: 842)
        let f: CGFloat = 595.0 / 842.0
        let source = CGPoint(x: 300, y: 700)
        let shown = PageEqualization.toEqualized(source, sourceBox: box, factor: f)
        XCTAssertEqual(shown.y, (700 - 20) * f, accuracy: 1e-9)
        let back = PageEqualization.toSource(shown, sourceBox: box, factor: f)
        XCTAssertEqual(back.x, source.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, source.y, accuracy: 1e-9)
    }

    /// PLAN-DATA03-001 E3 : la hauteur ayant servi à un PDF déjà préparé est retrouvée (page redessinée), et la
    /// référence d'un document n'est fixée qu'une fois.
    func testReferenceHeightIsRecoveredAndFixedOnce() throws {
        let a4 = CGRect(x: 0, y: 0, width: 595, height: 842), a5 = CGRect(x: 0, y: 0, width: 420, height: 595)
        let a5Scaled = CGRect(x: 0, y: 0, width: (420 * 842.0 / 595).rounded(), height: 842)
        XCTAssertEqual(PageEqualization.referenceHeight(displayed: [(a4, 0), (a5Scaled, 0), (a4, 0)], sourceBoxes: [a4, a5, a4]), 842)
        XCTAssertNil(PageEqualization.referenceHeight(displayed: [(a4, 0), (a4, 0)], sourceBoxes: [a4, a4]), "rien de redessiné")

        let db = try AppDatabase.inMemory()
        XCTAssertNil(try db.equalizationReference(documentId: "d"))
        try db.fixEqualizationReference(842, documentId: "d")
        try db.fixEqualizationReference(595, documentId: "d")
        XCTAssertEqual(try db.equalizationReference(documentId: "d"), 842, "jamais remplacée")
        try db.fixEqualizationReference(.nan, documentId: "e")
        XCTAssertNil(try db.equalizationReference(documentId: "e"))
    }
}
