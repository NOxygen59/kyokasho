// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import XCTest
@testable import OCRKit

/// C1.9 (audit du 09/11/2026) : annulation de la lecture automatique ≠ échec OCR.
final class OCRCancellationTests: XCTestCase {
    func testCancellationsAreRecognised() {
        XCTAssertTrue(OCRCancellation.isCancellation(CancellationError(), taskCancelled: false))
        XCTAssertTrue(OCRCancellation.isCancellation(URLError(.cancelled), taskCancelled: false))
        XCTAssertTrue(OCRCancellation.isCancellation(CocoaError(.userCancelled), taskCancelled: false))
        XCTAssertTrue(OCRCancellation.isCancellation(OCRError.pageUnavailable, taskCancelled: true))
    }

    func testRealFailureStaysFailure() {
        XCTAssertFalse(OCRCancellation.isCancellation(OCRError.pageUnavailable, taskCancelled: false))
        XCTAssertFalse(OCRCancellation.isCancellation(URLError(.timedOut), taskCancelled: false))
    }
}
