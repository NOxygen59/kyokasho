// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import OCRKit
import XCTest

final class AILayoutTests: XCTestCase {
    func testStructure() {
        let md = """
        ## 3 ) 木製引き戸
        ### ① 格子戸
        格子戸は木組みの格子に
        ガラスをはめ込むものが**一般的**である。

        <img src="images/bbox_92_223_191_334.jpg" />
        連子(繁)格子戸
        - 障子
        - 襖
        <table><tr><th colspan="2">種類</th></tr><tr><td>障子</td><td rowspan=2>和室</td></tr></table>
        """
        let blocks = AILayout.blocks(md)
        XCTAssertEqual(blocks, [
            .heading(level: 2, text: "3 ) 木製引き戸"),
            .heading(level: 3, text: "① 格子戸"),
            .paragraph("格子戸は木組みの格子にガラスをはめ込むものが一般的である。"),
            .figure(left: 92, top: 223, right: 191, bottom: 334),
            .paragraph("連子(繁)格子戸"),
            .list(["障子", "襖"]),
            .table([[AILayout.Cell(text: "種類", colspan: 2, header: true)],
                    [AILayout.Cell(text: "障子"), AILayout.Cell(text: "和室", rowspan: 2)]]),
        ])
    }

    func testNoForeignMarkupSurvives() {
        let blocks = AILayout.blocks("<script>alert(1)</script>天井<b>と</b>&amp;壁\n<a href=\"x\">床</a>")
        XCTAssertEqual(blocks, [.paragraph("alert(1)天井と&壁床")])
    }
}
