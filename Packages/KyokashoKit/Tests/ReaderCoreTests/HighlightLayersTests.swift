// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Recette 1.3.2 (62), L5 : pas de couches de surlignage empilées ; gomme.
final class HighlightLayersTests: XCTestCase {
    private func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> PageRect { PageRect(x: x, y: y, width: w, height: h) }

    func testOverlappingRectsMergeNeighboursDoNot() {
        let merged = HighlightLayers.merged([r(0, 0, 100, 10), r(50, 1, 100, 10), r(0, 11, 100, 10)])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0], r(0, 0, 150, 11))
        XCTAssertFalse(HighlightLayers.overlaps(r(0, 0, 100, 10), r(0, 9.5, 100, 10)))   // lignes qui se touchent
    }

    func testCoveredAndHit() {
        let a = Highlight(documentId: "d", pageIndex: 2, rects: [r(0, 0, 100, 10)], color: .yellow, text: "a")
        let b = Highlight(documentId: "d", pageIndex: 2, rects: [r(0, 40, 100, 10)], color: .green, text: "b")
        let other = Highlight(documentId: "d", pageIndex: 3, rects: [r(0, 0, 100, 10)], color: .yellow, text: "c")
        let covered = HighlightLayers.covered(by: [r(20, 2, 30, 8)], among: [a, b, other], page: 2)
        XCTAssertEqual(covered.map(\.id), [a.id])
        XCTAssertEqual(HighlightLayers.hit(10, 45, in: [a, b, other], page: 2)?.id, b.id)
        XCTAssertNil(HighlightLayers.hit(10, 25, in: [a, b, other], page: 2))
    }
}
