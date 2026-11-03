// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import XCTest
@testable import ReaderCore

final class PageRotationTests: XCTestCase {
    /// Découpe d'une page tournée : chaque moitié doit couvrir le bon côté de l'écran, et elles doivent se compléter.
    func testSplitHalvesFollowDisplayedSides() {
        let box = CGRect(x: 10, y: 20, width: 400, height: 600)
        for rotation in [0, 90, 180, 270] {
            let view = PageGeometry.pageToView(box: box, rotation: rotation)
            let left = PresentationLayout.box(for: .left, in: box, rotation: rotation).applying(view)
            let right = PresentationLayout.box(for: .right, in: box, rotation: rotation).applying(view)
            let shownWidth = rotation % 180 == 0 ? box.width : box.height
            XCTAssertEqual(left.minX, 0, accuracy: 0.001, "\(rotation)")
            XCTAssertEqual(left.maxX, shownWidth / 2, accuracy: 0.001, "\(rotation)")
            XCTAssertEqual(right.minX, shownWidth / 2, accuracy: 0.001, "\(rotation)")
            XCTAssertEqual(right.maxX, shownWidth, accuracy: 0.001, "\(rotation)")
        }
    }

    func testRotationNormalizationAndComposition() {
        XCTAssertEqual(PageTransform.normalizedRotation(-90), 270)
        XCTAssertEqual(PageTransform.normalizedRotation(450), 90)
        XCTAssertEqual(PageTransform.effectiveRotation(intrinsic: 270, additional: 180), 90)
        var transform = PageTransform(documentId: "d", pageIndex: 0, rotation: 0)
        transform.rotate(by: -90)
        XCTAssertEqual(transform.rotation, 270)
    }

    func testApplyingRotationsPreservesOtherTransformsAndInvalidatesOnlySelectedOCR() throws {
        let db = try AppDatabase.inMemory()
        let document = LibraryDocument(id: "d", title: "Test", originalFileName: "test.pdf", pageCount: 3,
                                       fileSize: 1, firstPageIndex: 0)
        try db.save(document)
        let crop = NormalizedRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
        try db.save(PageTransform(documentId: "d", pageIndex: 1, rotation: 0, split: true, autoCrop: crop))
        for page in 0..<3 {
            try db.save(OCRResultRecord(documentId: "d", pageIndex: page, engine: "test",
                                        json: Data("{}".utf8), durationMs: 1))
        }

        try db.applyPageRotations(documentId: "d", rotations: [1: 90, 2: 270])

        let transforms = try db.pageTransforms(documentId: "d")
        XCTAssertEqual(transforms[1]?.rotation, 90)
        XCTAssertEqual(transforms[1]?.split, true)
        XCTAssertEqual(transforms[1]?.autoCrop, crop)
        XCTAssertEqual(transforms[2]?.rotation, 270)
        XCTAssertNotNil(try db.ocrResult(documentId: "d", pageIndex: 0, engine: "test"))
        XCTAssertNil(try db.ocrResult(documentId: "d", pageIndex: 1, engine: "test"))
        XCTAssertNil(try db.ocrResult(documentId: "d", pageIndex: 2, engine: "test"))
    }
}
