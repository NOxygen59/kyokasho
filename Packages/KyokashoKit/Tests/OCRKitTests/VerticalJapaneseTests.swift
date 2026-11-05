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

    /// Revue Codex de 2b55bd9 : une large gouttière ne doit pas dépendre de l'ordre du moteur.
    func testWideGutterStaysRightToLeftWhateverTheEngineOrder() {
        let right = column("右", x: 0.80), left = column("左", x: 0.20)
        XCTAssertEqual(OCRLayout.verticalReadingOrder(page([left, right])).map(\.text), ["右", "左"])
        XCTAssertEqual(OCRLayout.verticalReadingOrder(page([right, left])).map(\.text), ["右", "左"])
    }

    func testHorizontalTitleComesFirst() {
        let title = OCRLine(text: "題", box: NormBox(x: 0.2, y: 0.02, w: 0.5, h: 0.05), charBoxes: [], measuredCharBoxes: false, vertical: false, confidence: 1)
        let order = OCRLayout.verticalReadingOrder(page([column("二", x: 0.70, y: 0.2), title, column("一", x: 0.76, y: 0.2)]))
        XCTAssertEqual(order.map(\.text), ["題", "一", "二"])
    }

    func testThousandLinesStayFast() {
        let lines = (0..<1000).map { column("字", x: 0.99 - Double($0 % 50) * 0.02, y: Double($0 / 50) * 0.05, h: 0.04) }
        let start = Date()
        XCTAssertEqual(OCRLayout.verticalReadingOrder(page(lines)).count, 1000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    /// Contre-revue Codex de f8a3fa9 : le balayage forme les mêmes blocs que la comparaison de toutes les paires.
    func testSweepGroupsLikeComparingEveryPair() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<40 {
            let lines = (0..<60).map { index -> OCRLine in
                let vertical = Bool.random(using: &generator)
                let a = Double.random(in: 0...0.9, using: &generator), b = Double.random(in: 0...0.9, using: &generator)
                let thin = Double.random(in: 0.01...0.05, using: &generator), long = Double.random(in: 0.05...0.4, using: &generator)
                return OCRLine(text: "\(index)", box: NormBox(x: a, y: b, w: vertical ? thin : long, h: vertical ? long : thin),
                               charBoxes: [], measuredCharBoxes: false, vertical: vertical, confidence: 1)
            }
            var groups = lines.indices.map { [$0] }
            for i in lines.indices { for j in lines.indices where i < j && OCRLayout.sameBlock(lines[i], lines[j]) {
                let a = groups.firstIndex { $0.contains(i) }!, b = groups.firstIndex { $0.contains(j) }!
                if a != b { groups[a] += groups[b]; groups.remove(at: b) }
            } }
            let reference = Set(groups.map { Set($0.map { lines[$0].text }) })
            let sweep = Set(OCRLayout.readingGroups(lines).values.map { Set($0.map(\.text)) })
            XCTAssertEqual(sweep, reference)
        }
    }
}
