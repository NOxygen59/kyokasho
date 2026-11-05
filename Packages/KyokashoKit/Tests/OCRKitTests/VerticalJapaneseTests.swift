// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import OCRKit

/// Livres japonais écrits de haut en bas, colonnes de droite à gauche.
final class VerticalJapaneseTests: XCTestCase {
    private func column(_ text: String, x: Double, y: Double = 0.1, h: Double = 0.6) -> OCRLine {
        OCRLine(text: text, box: NormBox(x: x, y: y, w: 0.04, h: h), charBoxes: [], measuredCharBoxes: false, vertical: true, confidence: 1)
    }

    private func page(_ lines: [OCRLine]) -> OCRPage {
        OCRPage(engine: "test", lines: lines, durationMs: 0)
    }

    private func texts(_ blocks: [OCRLayout.Block]) -> [String] {
        blocks.map {
            switch $0 {
            case .heading(_, let text), .paragraph(let text): return text
            case .table(let rows): return "TABLE:" + rows.flatMap { $0 }.joined(separator: "|")
            }
        }
    }

    func testColumnsReadFromRightToLeftAndAreNotATable() {
        let blocks = OCRLayout.blocks(page([column("二列目", x: 0.70), column("一列目", x: 0.76), column("三列目", x: 0.64)]))
        XCTAssertFalse(texts(blocks).contains { $0.hasPrefix("TABLE:") }, "des colonnes voisines ne sont pas un tableau : \(texts(blocks))")
        XCTAssertEqual(texts(blocks).joined(), "一列目二列目三列目")
    }

    func testStackedSectionsAreNotInterleaved() {
        let top = [column("上一", x: 0.76, y: 0.05, h: 0.3), column("上二", x: 0.70, y: 0.05, h: 0.3)]
        let bottom = [column("下一", x: 0.74, y: 0.55, h: 0.3), column("下二", x: 0.68, y: 0.55, h: 0.3)]
        let joined = texts(OCRLayout.blocks(page(top + bottom))).joined()
        XCTAssertEqual(joined, "上一上二下一下二", "colonnes de deux parties mélangées : \(joined)")
    }

    /// Panneau de texte : deux parties superposées d'une page verticale ne se mélangent pas (colonnes triées par x seul).
    func testReadingOrderKeepsSectionsTogether() {
        let lines = [column("下一", x: 0.74, y: 0.55, h: 0.3), column("上二", x: 0.70, y: 0.05, h: 0.3),
                     column("下二", x: 0.68, y: 0.55, h: 0.3), column("上一", x: 0.76, y: 0.05, h: 0.3)]
        XCTAssertEqual(OCRLayout.verticalReadingOrder(page(lines)).map(\.text), ["上一", "上二", "下一", "下二"])
    }

    func testReadingOrderOfOneBlockIsRightToLeft() {
        let lines = [column("三", x: 0.64), column("一", x: 0.76), column("二", x: 0.70)]
        XCTAssertEqual(OCRLayout.verticalReadingOrder(page(lines)).map(\.text), ["一", "二", "三"])
    }
}
