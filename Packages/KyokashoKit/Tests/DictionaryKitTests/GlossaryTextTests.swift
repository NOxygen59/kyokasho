// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import DictionaryKit
import XCTest

final class GlossaryTextTests: XCTestCase {
    func testPlainStrings() {
        XCTAssertEqual(GlossaryText.plain(#"["to eat","to live on"]"#), "to eat ; to live on")
    }

    func testStructuredContentSkipsRubyAndImages() {
        let json = #"[{"type":"structured-content","content":[{"tag":"ruby","content":["食",{"tag":"rt","content":"た"}]},"べる",{"tag":"img","path":"a.png"},{"tag":"ul","content":[{"tag":"li","content":"manger"},{"tag":"li","content":"vivre de"}]}]}]"#
        XCTAssertEqual(GlossaryText.plain(json), "食べる manger vivre de")
    }

    func testLimit() {
        XCTAssertEqual(GlossaryText.plain(#"["abcdefghij"]"#, limit: 5), "abcd…")
    }

    func testInvalid() {
        XCTAssertEqual(GlossaryText.plain("pas du json"), "")
    }
}
