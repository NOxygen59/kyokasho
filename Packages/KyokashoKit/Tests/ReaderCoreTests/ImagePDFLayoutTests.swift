// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import XCTest
@testable import ReaderCore

/// Images vers PDF : forme des pages et réduction des grandes photos.
final class ImagePDFLayoutTests: XCTestCase {
    func testPageKeepsImageShapeWithA4LongSide() {
        XCTAssertEqual(ImagePDFLayout.pageSize(for: CGSize(width: 3000, height: 4000)), CGSize(width: 632, height: 842))
        XCTAssertEqual(ImagePDFLayout.pageSize(for: CGSize(width: 4000, height: 3000)), CGSize(width: 842, height: 632))
        XCTAssertEqual(ImagePDFLayout.pageSize(for: .zero), CGSize(width: 595, height: 842))
    }

    func testLargePhotosAreReducedSmallOnesKept() {
        XCTAssertEqual(ImagePDFLayout.pixelSize(for: CGSize(width: 8064, height: 6048)), CGSize(width: 3508, height: 2631))
        XCTAssertEqual(ImagePDFLayout.pixelSize(for: CGSize(width: 1200, height: 1600)), CGSize(width: 1200, height: 1600))
    }
}
