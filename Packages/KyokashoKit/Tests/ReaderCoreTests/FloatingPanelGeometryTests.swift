// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

final class FloatingPanelGeometryTests: XCTestCase {
    private let area = CGSize(width: 1200, height: 900)
    private let minimum = CGSize(width: 372, height: 320)
    private let start = CGRect(x: 120, y: 80, width: 520, height: 640)

    func testMoveAppliesOneTranslationAndContinuesWithoutReleaseJump() {
        let translated = FloatingPanelGeometry.moved(start, by: CGSize(width: 20, height: 15), area: area, minimum: minimum)
        XCTAssertEqual(translated, CGRect(x: 140, y: 95, width: 520, height: 640))
        let reopened = FloatingPanelGeometry.constrained(translated, area: area, minimum: minimum)
        XCTAssertEqual(reopened, translated)
        XCTAssertEqual(FloatingPanelGeometry.moved(reopened, by: CGSize(width: -5, height: -5), area: area, minimum: minimum).origin,
                       CGPoint(x: 135, y: 90))
    }

    func testResizeKeepsOriginAndStopsAtEdge() {
        let resized = FloatingPanelGeometry.resized(start, by: CGSize(width: 30, height: 20), area: area, minimum: minimum)
        XCTAssertEqual(resized, CGRect(x: 120, y: 80, width: 550, height: 660))
        let edge = FloatingPanelGeometry.resized(start, by: CGSize(width: 2000, height: 2000), area: area, minimum: minimum)
        XCTAssertEqual(edge, CGRect(x: 120, y: 80, width: 1080, height: 820))
        XCTAssertEqual(FloatingPanelGeometry.constrained(edge, area: area, minimum: minimum), edge)
    }

    func testRotationUsesVisibleOriginAndSizeForFirstSmallGesture() {
        let smaller = CGSize(width: 700, height: 500)
        let outside = CGRect(x: 950, y: 600, width: 900, height: 640)
        let visible = FloatingPanelGeometry.constrained(outside, area: smaller, minimum: minimum)
        XCTAssertEqual(visible, CGRect(x: 0, y: 0, width: 700, height: 500))
        let resized = FloatingPanelGeometry.resized(outside, by: CGSize(width: -10, height: -10), area: smaller, minimum: minimum)
        XCTAssertEqual(resized, CGRect(x: 0, y: 0, width: 690, height: 490), "pas de zone morte due aux 900 points persistés")
        let offscreen = CGRect(x: 900, y: 500, width: 400, height: 320)
        let moved = FloatingPanelGeometry.moved(offscreen, by: CGSize(width: -10, height: -10), area: smaller, minimum: minimum)
        XCTAssertEqual(moved.origin, CGPoint(x: 290, y: 170))
    }

    func testSmallAndZeroAreasNeverProduceNegativeGeometry() {
        for small in [CGSize(width: 200, height: 180), .zero] {
            let normalized = FloatingPanelGeometry.constrained(start, area: small, minimum: minimum)
            XCTAssertEqual(normalized.origin, .zero)
            XCTAssertEqual(normalized.size, small)
            XCTAssertEqual(FloatingPanelGeometry.resized(normalized, by: CGSize(width: -100, height: -100), area: small, minimum: minimum), normalized)
        }
    }

    func testAllEdgesAndMinimumRemainReachable() {
        for delta in [CGSize(width: -10000, height: -10000), CGSize(width: 10000, height: 10000)] {
            let moved = FloatingPanelGeometry.moved(start, by: delta, area: area, minimum: minimum)
            XCTAssertGreaterThanOrEqual(moved.minX, 0)
            XCTAssertGreaterThanOrEqual(moved.minY, 0)
            XCTAssertLessThanOrEqual(moved.maxX, area.width)
            XCTAssertLessThanOrEqual(moved.maxY, area.height)
        }
        XCTAssertEqual(FloatingPanelGeometry.resized(start, by: CGSize(width: -10000, height: -10000), area: area, minimum: minimum).size, minimum)
    }
}
