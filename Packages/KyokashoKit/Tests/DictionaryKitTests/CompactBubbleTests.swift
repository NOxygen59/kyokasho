// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import DictionaryKit

/// RET-047 (#71) : la bulle compacte masque les sources et garde le mot et les définitions.
final class CompactBubbleTests: XCTestCase {
    func testCompactStyleGoesInHead() {
        let page = "<html><head><style>x</style></head><body><p>def</p></body></html>"
        let out = GlossaryRenderer.compact(page)
        let style = out.range(of: GlossaryRenderer.compactCSS)!
        XCTAssertLessThan(style.upperBound, out.range(of: "</head>")!.lowerBound)
        XCTAssertTrue(out.contains("<p>def</p>"))
    }

    func testCompactHidesSourcesOnly() {
        let css = GlossaryRenderer.compactCSS
        for hidden in [".freqs", ".pitches", ".ipa", ".dict-title", ".tags"] {
            XCTAssertTrue(css.contains("html \(hidden)"), hidden)
        }
        XCTAssertFalse(css.contains("ol.gloss"))
        XCTAssertFalse(css.contains(".fr-tr{display:none"))
    }

    func testPageWithoutHeadIsUnchanged() {
        XCTAssertEqual(GlossaryRenderer.compact("<p>x</p>"), "<p>x</p>")
    }
}
