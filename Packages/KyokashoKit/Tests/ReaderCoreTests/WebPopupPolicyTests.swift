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

    func testSearchUsesBrave() {
        XCTAssertEqual(WebAddress.url(for: "  床の間 意味 ")?.absoluteString,
                       "https://search.brave.com/search?q=%E5%BA%8A%E3%81%AE%E9%96%93%20%E6%84%8F%E5%91%B3")
        XCTAssertEqual(WebAddress.url(for: "claude.ai")?.absoluteString, "https://claude.ai")
        XCTAssertEqual(WebAddress.url(for: "https://jisho.org/x")?.absoluteString, "https://jisho.org/x")
        XCTAssertNil(WebAddress.url(for: "   "))
    }
}
