// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import OCRKit
import XCTest

final class DocumentAnalysisTests: XCTestCase {
    private func page(_ lines: [String]) -> OCRPage {
        OCRPage(engine: "ndlocr", lines: lines.map {
            OCRLine(text: $0, box: NormBox(x: 0, y: 0, w: 1, h: 0.1), charBoxes: [], measuredCharBoxes: false, vertical: false, confidence: 1)
        }, durationMs: 0)
    }

    func testMajorityAndReliability() async {
        let base = page(["天井を張る場合、", "末来の土地", "小屋裏にスペース"])
        let result = await DocumentAnalysis.vote(
            source: 0, base: base,
            readings: ["ovis": "天井を張る場合、\n未来の土地\n小屋裏にスペース", "glm": "天井を張る場合、\n未来の土地\n小屋裏にスベース"],
            tieBreak: { $0.first })
        XCTAssertEqual(result.lines, 3)
        // Ligne 0 : 3 voix ; ligne 2 : OCR + Ovis contre GLM → confirmée ; ligne 1 : Ovis + GLM contre l'OCR.
        XCTAssertEqual(result.confirmed, 2)
        XCTAssertEqual(result.disagreements.map(\.line), [1])
        XCTAssertEqual(result.disagreements.first?.advised, "未来の土地")
        XCTAssertEqual(result.reliability, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testTwoReadersTieUsesDictionary() async {
        let base = page(["末来の土地"])
        let result = await DocumentAnalysis.vote(source: 0, base: base, readings: ["ovis": "未来の土地"], tieBreak: { _ in "未来の土地" })
        XCTAssertEqual(result.confirmed, 0)
        XCTAssertEqual(result.disagreements.first?.advised, "未来の土地")
    }

    /// #41 : la lecture d'Ovis est conseillée d'abord, sauf si deux autres lectures s'accordent contre elle.
    func testPreferredReaderWinsTiesButNotTwoAgainstIt() async {
        let base = page(["末来の土地", "天丼を張る"])
        let result = await DocumentAnalysis.vote(
            source: 0, base: base,
            readings: ["ovis": "未来の土地\n天井を張る", "glm": "末来の上地\n天丼を張る"],
            preferred: "ovis", tieBreak: { _ in "末来の土地" })
        // Ligne 0 : trois lectures différentes → Ovis, pas le dictionnaire.
        XCTAssertEqual(result.disagreements.first { $0.line == 0 }?.advised, "未来の土地")
        // Ligne 1 : OCR + GLM d'accord → confirmée, Ovis seul ne l'emporte pas.
        XCTAssertNil(result.disagreements.first { $0.line == 1 })

        let outvoted = await DocumentAnalysis.vote(
            source: 0, base: page(["末来の土地"]),
            readings: ["ovis": "米来の土地", "glm": "未来の土地", "qwen": "未来の土地"],
            preferred: "ovis", tieBreak: { _ in nil })
        XCTAssertEqual(outvoted.disagreements.first?.advised, "未来の土地")
    }

    /// #41 : texte que seul Ovis voit dans un PDF à texte intégré (images d'illustration).
    func testTextOutsideBase() {
        let base = "天井を張る場合、\n小屋裏にスペース"
        let reading = "# 天井を張る場合、\n小屋裏に スペース\n| 断熱材 | 50mm |\n![図](x)\n- 断熱材\n。"
        XCTAssertEqual(DocumentAnalysis.textOutsideBase(base, reading: reading), ["断熱材   50mm"])
    }

    func testRunsKeepLatestTwenty() {
        var report = DocumentAnalysis(documentId: "d")
        for i in 0..<22 { report.recordRun(.init(date: Date(), engines: ["ovis"], firstPage: i, lastPage: i, reread: false)) }
        XCTAssertEqual(report.runs?.count, 20)
        XCTAssertEqual(report.runs?.first?.firstPage, 2)
    }

    /// Un rapport d'avant #41 (sans `runs` ni `imageText`) se relit.
    func testOldReportDecodes() throws {
        let old = #"{"documentId":"d","date":0,"engines":["ovis"],"pages":{}}"#
        let report = try JSONDecoder().decode(DocumentAnalysis.self, from: Data(old.utf8))
        XCTAssertNil(report.runs)
        XCTAssertNil(report.imageText)
    }
}
