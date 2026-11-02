// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import XCTest
@testable import ReaderCore

final class PageRotationTests: XCTestCase {
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
