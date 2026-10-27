// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import XCTest
@testable import ReaderCore

/// Issue #13 : une bulle compacte près du mot, jamais hors de la fenêtre OCR.
final class ContextBubbleLayoutTests: XCTestCase {
    private let panel = CGSize(width: 500, height: 900)

    private func assertInside(_ frame: CGRect, _ container: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(frame.minX, ContextBubbleLayout.margin - 0.001, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, ContextBubbleLayout.margin - 0.001, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, container.width - ContextBubbleLayout.margin + 0.001, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, container.height - ContextBubbleLayout.margin + 0.001, file: file, line: line)
    }

    func testCompactSizeNeverExceedsTheLimits() {
        XCTAssertEqual(ContextBubbleLayout.size(in: panel), CGSize(width: 360, height: 300))
        let narrow = ContextBubbleLayout.size(in: CGSize(width: 300, height: 260))
        XCTAssertEqual(narrow.width, 240, accuracy: 0.001, "80 % d'une zone étroite")
        XCTAssertEqual(narrow.height, 208, accuracy: 0.001)
    }

    func testPlacedBelowTheWordWhenThereIsRoom() {
        let word = CGRect(x: 100, y: 120, width: 40, height: 24)
        let frame = ContextBubbleLayout.frame(word: word, in: panel)
        XCTAssertEqual(frame.minY, word.maxY + ContextBubbleLayout.gap, accuracy: 0.001)
        assertInside(frame, panel)
    }

    func testPlacedAboveTheWordNearTheBottom() {
        let word = CGRect(x: 200, y: 800, width: 40, height: 24)
        let frame = ContextBubbleLayout.frame(word: word, in: panel)
        XCTAssertEqual(frame.maxY, word.minY - ContextBubbleLayout.gap, accuracy: 0.001)
        assertInside(frame, panel)
    }

    func testStaysInsideNearEdgesAndInSmallZones() {
        for word in [CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 490, y: 450, width: 10, height: 10)] {
            assertInside(ContextBubbleLayout.frame(word: word, in: panel), panel)
        }
        let small = CGSize(width: 260, height: 240)
        assertInside(ContextBubbleLayout.frame(word: CGRect(x: 120, y: 110, width: 20, height: 20), in: small), small)
    }

    func testHorizontallyCenteredOnTheWordWhenPossible() {
        let word = CGRect(x: 230, y: 100, width: 40, height: 20)
        XCTAssertEqual(ContextBubbleLayout.frame(word: word, in: panel).midX, word.midX, accuracy: 0.001)
    }
}
