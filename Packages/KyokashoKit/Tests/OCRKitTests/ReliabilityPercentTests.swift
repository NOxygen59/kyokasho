// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import XCTest
@testable import OCRKit

/// RET-044 / Issue #65 : la fiabilité affichée ne doit plus valoir « 0,0 % ».
final class ReliabilityPercentTests: XCTestCase {
    private func report(lines: Int, confirmed: Int, unchecked: Int = 0) -> DocumentAnalysis {
        var report = DocumentAnalysis(documentId: "doc")
        var page = DocumentAnalysis.Page(source: 0, baseEngine: "test")
        page.lines = lines
        page.confirmed = confirmed
        page.unchecked = unchecked
        report.pages[0] = page
        return report
    }

    func testPercentKeepsOneDecimal() {
        XCTAssertEqual(report(lines: 1000, confirmed: 873).reliabilityPercent, 87.3, accuracy: 0.0001)
        XCTAssertEqual(report(lines: 3, confirmed: 2).reliabilityPercent, 66.7, accuracy: 0.0001)
        XCTAssertEqual(report(lines: 10, confirmed: 10).reliabilityPercent, 100, accuracy: 0.0001)
    }

    func testFormattedLikeTheSheetIsNotZero() {
        // Même format que la feuille d'analyse : un Double, jamais un entier passé à %.1f.
        XCTAssertEqual(String(format: "%.1f", report(lines: 1000, confirmed: 873).reliabilityPercent), "87.3")
    }

    func testNothingComparedStaysAtHundred() {
        XCTAssertEqual(report(lines: 4, confirmed: 0, unchecked: 4).reliabilityPercent, 100, accuracy: 0.0001)
    }
}
