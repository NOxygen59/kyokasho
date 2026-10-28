// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
import ReaderCore
@testable import OCRKit

/// Adaptateur du rapport en mémoire ; les méthodes apply/dismiss viennent du vrai fichier App lié.
/// SQLite, OCRService et les modèles OCR sont réels. Aucun UIKit ni modèle IA n'est démarré.
@MainActor
final class DocumentAnalysisService {
    var reportValue: DocumentAnalysis
    var lastError: String?
    var reportWrites = 0
    init(_ report: DocumentAnalysis) { reportValue = report }
    func report(for id: String) -> DocumentAnalysis? { reportValue.documentId == id ? reportValue : nil }
    func setCorrectionError(_ message: String?) { lastError = message }

    func update(_ id: String, _ change: (inout DocumentAnalysis) -> Void) {
        guard reportValue.documentId == id else { return }
        change(&reportValue)
        reportWrites += 1
    }
}

@MainActor
final class AnalysisCorrectionTests: XCTestCase {
    private func fixture() throws -> (DocumentAnalysisService, OCRService, AppDatabase, String) {
        let id = UUID().uuidString
        let db = try AppDatabase.inMemory()
        try db.save(LibraryDocument(id: id, title: "Synthétique", originalFileName: "test.pdf", pageCount: 1, fileSize: 1))
        var report = DocumentAnalysis(documentId: id)
        var page = DocumentAnalysis.Page(source: 0, baseEngine: OCREngineID.vision)
        page.lines = 1
        page.disagreements = [.init(line: 0, base: "末来", readings: ["test": "未来"], advised: "未来")]
        report.pages[0] = page
        return (DocumentAnalysisService(report), OCRService(database: db), db, id)
    }

    private func page(_ text: String, edited: Bool = false) -> OCRPage {
        var line = OCRLine(text: text, box: NormBox(x: 0, y: 0, w: 1, h: 0.1), charBoxes: [],
                           measuredCharBoxes: false, vertical: false, confidence: 0.3)
        line.edited = edited
        line.doubt = edited ? [] : [0]
        return OCRPage(engine: OCREngineID.vision, lines: [line], durationMs: 0)
    }

    func testKeepOriginalWithoutCacheExplainsAndKeepsDisagreementOpen() async throws {
        let (analysis, ocr, db, id) = try fixture()
        await analysis.dismiss(source: 0, line: 0, documentId: id, service: ocr)
        XCTAssertTrue(analysis.lastError?.contains("indisponible") == true)
        XCTAssertEqual(analysis.reportValue.pages[0]?.disagreements[0].settled, false)
        XCTAssertEqual(analysis.reportValue.pages[0]?.confirmed, 0)
        XCTAssertEqual(analysis.reportWrites, 0)
        XCTAssertEqual(try db.ocrCacheStats().results, 0)
    }

    func testKeepOriginalAfterManualChangeExplainsAndPreservesCurrentLine() async throws {
        let (analysis, ocr, _, id) = try fixture()
        let current = page("未来の土地", edited: true)
        try await ocr.store(current, documentId: id, pageIndex: 0)
        await analysis.dismiss(source: 0, line: 0, documentId: id, service: ocr)
        XCTAssertTrue(analysis.lastError?.contains("changé") == true)
        XCTAssertEqual(analysis.reportValue.pages[0]?.disagreements[0].settled, false)
        XCTAssertEqual(analysis.reportWrites, 0)
        let saved = await ocr.cached(documentId: id, pageIndex: 0, engine: current.engine)
        XCTAssertEqual(saved, current)
    }

    func testKeepOriginalPersistsAcceptanceThenClosesDisagreement() async throws {
        let (analysis, ocr, _, id) = try fixture()
        try await ocr.store(page("末来"), documentId: id, pageIndex: 0)
        await analysis.dismiss(source: 0, line: 0, documentId: id, service: ocr)
        XCTAssertNil(analysis.lastError)
        XCTAssertEqual(analysis.reportValue.pages[0]?.disagreements[0].settled, true)
        XCTAssertEqual(analysis.reportValue.pages[0]?.confirmed, 1)
        let saved = await ocr.cached(documentId: id, pageIndex: 0, engine: OCREngineID.vision)
        XCTAssertEqual(saved?.lines[0].text, "末来")
        XCTAssertEqual(saved?.lines[0].edited, true)
        XCTAssertEqual(saved?.lines[0].doubt, [])
    }

    /// #41 : « Annuler le dernier choix » remet la ligne d'avant et rouvre le désaccord.
    func testUndoRestoresLineAndReopensDisagreement() async throws {
        let (analysis, ocr, _, id) = try fixture()
        let original = page("末来")
        try await ocr.store(original, documentId: id, pageIndex: 0)
        let applied = await analysis.apply([(source: 0, line: 0, text: "未来")], documentId: id, service: ocr)
        XCTAssertEqual(applied.count, 1)
        await analysis.undo(applied, documentId: id, service: ocr)
        XCTAssertNil(analysis.lastError)
        XCTAssertEqual(analysis.reportValue.pages[0]?.disagreements[0].settled, false)
        XCTAssertEqual(analysis.reportValue.pages[0]?.confirmed, 0)
        let saved = await ocr.cached(documentId: id, pageIndex: 0, engine: OCREngineID.vision)
        XCTAssertEqual(saved, original)
    }

    /// Ligne retouchée après le choix : l'annulation ne l'écrase pas.
    func testUndoKeepsLaterManualChange() async throws {
        let (analysis, ocr, _, id) = try fixture()
        try await ocr.store(page("末来"), documentId: id, pageIndex: 0)
        let applied = await analysis.apply([(source: 0, line: 0, text: "未来")], documentId: id, service: ocr)
        let later = page("未来の土地", edited: true)
        try await ocr.store(later, documentId: id, pageIndex: 0)
        await analysis.undo(applied, documentId: id, service: ocr)
        XCTAssertTrue(analysis.lastError?.contains("changé") == true)
        XCTAssertEqual(analysis.reportValue.pages[0]?.disagreements[0].settled, true)
        let saved = await ocr.cached(documentId: id, pageIndex: 0, engine: OCREngineID.vision)
        XCTAssertEqual(saved, later)
    }
}
