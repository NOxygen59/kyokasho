// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// T3 (retours terrain du 10/11/2026) : la connexion Google de claude.ai s'ouvre dans une vraie fenêtre fille.
final class WebPopupPolicyTests: XCTestCase {
    func testScriptWindowBecomesRealWindow() {
        XCTAssertTrue(WebPopupPolicy.opensRealWindow(linkActivated: false, hasSize: false))
        XCTAssertTrue(WebPopupPolicy.opensRealWindow(linkActivated: false, hasSize: true))
    }

    func testSizedLinkBecomesRealWindow() {
        XCTAssertTrue(WebPopupPolicy.opensRealWindow(linkActivated: true, hasSize: true))
    }

    func testPlainBlankLinkStaysInSameView() {
        XCTAssertFalse(WebPopupPolicy.opensRealWindow(linkActivated: true, hasSize: false))
    }
}
