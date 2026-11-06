// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import ReaderCore
import XCTest

final class MacWindowFrameTests: XCTestCase {
    func testFrameIsSixteenByTenCenteredAndInsideTheScreen() {
        // Écran large (MacBook) puis écran presque carré : la limite vient de la hauteur, puis de la largeur.
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 100, y: 0, width: 800, height: 1000)] {
            let frame = MacWindowFrame.initial(screen: screen)
            XCTAssertEqual(frame.width / frame.height, 16.0 / 10.0, accuracy: 0.0001)
            XCTAssertTrue(screen.contains(frame))
            XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.0001)
            XCTAssertEqual(frame.midY, screen.midY, accuracy: 0.0001)
        }
    }
}
