// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
import ReaderCore
@testable import OCRKit

/// Analyse avant candidate 1.5.5 (DeepSeek #2) : une correction mise de côté avant 1.5.5 porte le texte lu brut
/// (forme chinoise) ; la page relue est normalisée par la table T6. La correction doit quand même revenir.
final class StashedCorrectionsT6Tests: XCTestCase {
    func testCorrectionKeptOnRawChineseFormIsAppliedToNormalizedLine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aside-t6-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let previous = CorrectionAsideStore.shared
        CorrectionAsideStore.shared = CorrectionAsideStore(root: root)
        defer { CorrectionAsideStore.shared = previous }
        try CorrectionAsideStore.shared.keep(pageIndex: 0, engine: "vision",
                                             entries: [KeptCorrection(original: "相对湿度", corrected: "相対湿度（%）")],
                                             documentId: "doc", sourceDocumentId: "ancien")
        let box = NormBox(x: 0, y: 0, w: 1, h: 1)
        let text = JapaneseOCRText.normalize("相对湿度")
        XCTAssertEqual(text, "相対湿度", "prémisse : la table T6 convertit 对")
        var page = OCRPage(engine: "vision", lines: [], durationMs: 1)
        page.lines = [OCRLine(text: text, box: box, charBoxes: CharacterLayout.proportional(text, in: box, vertical: false),
                              measuredCharBoxes: true, vertical: false, confidence: 0.9)]
        let stashed = try XCTUnwrap(StashedCorrections.applied(to: page, documentId: "doc", pageIndex: 0))
        XCTAssertEqual(stashed.page.lines.first?.text, "相対湿度（%）")
        stashed.commit()
        XCTAssertTrue(CorrectionAsideStore.shared.pendingCorrections(documentId: "doc", pageIndex: 0, engine: "vision").isEmpty)
    }
}
