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
}
