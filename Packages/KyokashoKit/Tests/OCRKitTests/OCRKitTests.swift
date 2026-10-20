// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import AppKit
import CoreText
import XCTest
@testable import OCRKit
import ReaderCore

/// PDF de test avec du **vrai texte** (police japonaise du Mac), jamais versionné.
func makeTextPDF(lines: [String], size: CGFloat = 28) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw OCRError.renderFailed }
    ctx.beginPDFPage(nil)
    let font = CTFontCreateWithName("HiraginoSans-W3" as CFString, size, nil)
    for (i, line) in lines.enumerated() {
        let attr = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: NSColor.black])
        let ct = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: 60, y: 760 - CGFloat(i) * size * 2)
        CTLineDraw(ct, ctx)
    }
    ctx.endPDFPage()
    ctx.closePDF()
    return url
}

final class CharacterLayoutTests: XCTestCase {
    func testWidthWeights() {
        XCTAssertEqual(CharacterLayout.widthWeight("照"), 1)
        XCTAssertEqual(CharacterLayout.widthWeight("か"), 1)
        XCTAssertEqual(CharacterLayout.widthWeight("カ"), 1)
        XCTAssertEqual(CharacterLayout.widthWeight("。"), 1)
        XCTAssertEqual(CharacterLayout.widthWeight("Ａ"), 1)
        XCTAssertEqual(CharacterLayout.widthWeight("A"), 0.5)
        XCTAssertEqual(CharacterLayout.widthWeight("7"), 0.5)
        XCTAssertEqual(CharacterLayout.widthWeight("ｶ"), 0.5)
    }

    func testProportionalHorizontal() {
        let box = NormBox(x: 0.1, y: 0.2, w: 0.3, h: 0.05)
        let boxes = CharacterLayout.proportional("照明A", in: box, vertical: false)
        XCTAssertEqual(boxes.count, 3)
        XCTAssertEqual(boxes[0].w, 0.12, accuracy: 1e-9) // 1 / 2.5 de 0,3
        XCTAssertEqual(boxes[2].w, 0.06, accuracy: 1e-9)
        XCTAssertEqual(boxes[2].x + boxes[2].w, 0.4, accuracy: 1e-9)
        XCTAssertTrue(boxes.allSatisfy { $0.y == 0.2 && $0.h == 0.05 })
    }

    func testProportionalVertical() {
        let boxes = CharacterLayout.proportional("縦書き", in: NormBox(x: 0.8, y: 0.1, w: 0.04, h: 0.3), vertical: true)
        for (box, expected) in zip(boxes, [0.1, 0.2, 0.3]) { XCTAssertEqual(box.y, expected, accuracy: 1e-9) }
        XCTAssertTrue(boxes.allSatisfy { $0.x == 0.8 && abs($0.h - 0.1) < 1e-9 })
    }

    func testValidate() {
        let a = NormBox(x: 0.1, y: 0.1, w: 0.02, h: 0.05)
        let b = NormBox(x: 0.12, y: 0.1, w: 0.02, h: 0.05)
        XCTAssertTrue(CharacterLayout.validate([a, b], count: 2, vertical: false))
        XCTAssertFalse(CharacterLayout.validate([a, a], count: 2, vertical: false), "boîte de mot répétée")
        XCTAssertFalse(CharacterLayout.validate([b, a], count: 2, vertical: false), "ordre inversé")
        XCTAssertFalse(CharacterLayout.validate([a, nil], count: 2, vertical: false))
        XCTAssertFalse(CharacterLayout.validate([a], count: 2, vertical: false))
    }

    func testVerticalDetection() {
        // Image 1000×1500 (aspect 0,667) : boîte 0,04 × 0,4 → 27 px de large pour 600 de haut.
        XCTAssertTrue(CharacterLayout.isVertical(NormBox(x: 0, y: 0, w: 0.04, h: 0.4), imageAspect: 0.667, characters: 8))
        XCTAssertFalse(CharacterLayout.isVertical(NormBox(x: 0, y: 0, w: 0.5, h: 0.03), imageAspect: 0.667, characters: 8))
    }

    func testVisionBoxConversion() {
        let b = NormBox.fromVision(CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.1))
        XCTAssertEqual(b.y, 0.2, accuracy: 1e-9)
    }

    func testCharacterHitTest() {
        let line = OCRLine(text: "照明", box: NormBox(x: 0.1, y: 0.1, w: 0.2, h: 0.05),
                           charBoxes: CharacterLayout.proportional("照明", in: NormBox(x: 0.1, y: 0.1, w: 0.2, h: 0.05), vertical: false),
                           measuredCharBoxes: false, vertical: false, confidence: 1)
        let page = OCRPage(engine: "t", lines: [line], durationMs: 0)
        XCTAssertEqual(page.character(at: CGPoint(x: 0.15, y: 0.12))?.index, 0)
        XCTAssertEqual(page.character(at: CGPoint(x: 0.25, y: 0.12))?.index, 1)
        XCTAssertNil(page.character(at: CGPoint(x: 0.9, y: 0.9)))
    }
}

final class CERTests: XCTestCase {
    func testCER() {
        XCTAssertEqual(CharacterErrorRate.cer(reference: "照明計画", hypothesis: "照明計画"), 0)
        XCTAssertEqual(CharacterErrorRate.cer(reference: "照明計画", hypothesis: "照明計面"), 0.25)
        XCTAssertEqual(CharacterErrorRate.cer(reference: "照明 計画\n", hypothesis: "照明計画"), 0, "espaces ignorés")
        XCTAssertEqual(CharacterErrorRate.cer(reference: "abc", hypothesis: ""), 1)
        XCTAssertEqual(CharacterErrorRate.cer(reference: "", hypothesis: ""), 0)
        XCTAssertEqual(CharacterErrorRate.levenshtein(Array("kitten"), Array("sitting")), 3)
    }
}

final class EngineTests: XCTestCase {
    func testPDFTextEngine() async throws {
        let url = try makeTextPDF(lines: ["照明計画を考える。", "Design 2026"])
        XCTAssertTrue(PDFTextEngine.hasTextLayer(url: url, pageIndex: 0))
        let page = try await PDFTextEngine().recognize(.pdfPage(url: url, index: 0))
        XCTAssertEqual(page.lines.map(\.text), ["照明計画を考える。", "Design 2026"])
        let first = try XCTUnwrap(page.lines.first)
        XCTAssertEqual(first.charBoxes.count, first.text.count)
        // Première ligne en haut de la page (y ≈ 1 - 760/842 ≈ 0,07 côté haut).
        XCTAssertLessThan(first.box.y, 0.15)
        XCTAssertLessThan(first.charBoxes[0].x, first.charBoxes[1].x)
    }

    func testPDFTextEngineRejectsImagePage() async throws {
        // Page sans texte (rectangles seulement).
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        ctx.beginPDFPage(nil); ctx.fill(CGRect(x: 10, y: 10, width: 50, height: 50)); ctx.endPDFPage(); ctx.closePDF()
        XCTAssertFalse(PDFTextEngine.hasTextLayer(url: url, pageIndex: 0))
        do {
            _ = try await PDFTextEngine().recognize(.pdfPage(url: url, index: 0))
            XCTFail("aurait dû échouer")
        } catch {
            XCTAssertEqual(error as? OCRError, .noTextLayer)
        }
        XCTAssertEqual(OCRService.resolve(.auto, url: url, pageIndex: 0), OCREngineID.vision)
    }

    func testVisionReadsJapanese() async throws {
        let url = try makeTextPDF(lines: ["照明計画を考える。", "空間の印象"], size: 34)
        XCTAssertEqual(OCRService.resolve(.auto, url: url, pageIndex: 0), OCREngineID.pdfText)
        let page = try await VisionOCREngine().recognize(.pdfPage(url: url, index: 0))
        let reference = "照明計画を考える。空間の印象"
        let cer = CharacterErrorRate.cer(reference: reference, hypothesis: page.text)
        XCTAssertLessThan(cer, 0.15, "Vision : « \(page.text) »")
        for line in page.lines { XCTAssertEqual(line.charBoxes.count, line.text.count) }
    }

    /// Les boîtes de Vision (image rendue) doivent tomber au même endroit que le texte du PDF.
    func testVisionBoxesMatchPDFText() async throws {
        let url = try makeTextPDF(lines: ["照明計画を考える。", "空間の印象"], size: 34)
        let pdf = try await PDFTextEngine().recognize(.pdfPage(url: url, index: 0))
        let vision = try await VisionOCREngine().recognize(.pdfPage(url: url, index: 0))
        let a = try XCTUnwrap(pdf.lines.first?.box)
        let b = try XCTUnwrap(vision.lines.first?.box)
        XCTAssertEqual(a.x, b.x, accuracy: 0.03)
        XCTAssertEqual(a.midY, b.midY, accuracy: 0.03)
        XCTAssertEqual(a.w, b.w, accuracy: 0.08)
    }

    func testRendererSize() throws {
        let url = try makeTextPDF(lines: ["A"])
        let image = try PageRenderer.render(url: url, pageIndex: 0, longSide: 1000)
        XCTAssertEqual(image.height, 1000)
        XCTAssertEqual(image.width, 707)
    }
}

final class ServiceTests: XCTestCase {
    func testCacheAndEngines() async throws {
        let db = try AppDatabase.inMemory()
        do {
            try db.save(LibraryDocument(id: "d", title: "D", originalFileName: "d.pdf", pageCount: 1, fileSize: 1))
        } catch { XCTFail("save document: \(error)"); return }
        let url = try makeTextPDF(lines: ["照明計画を考える。"])
        let service = OCRService(database: db)
        let empty = await service.cached(documentId: "d", pageIndex: 0, engine: OCREngineID.pdfText)
        XCTAssertNil(empty)
        let first: OCRPage
        do { first = try await service.page(documentId: "d", url: url, pageIndex: 0, engine: OCREngineID.pdfText) }
        catch { XCTFail("page pdfText: \(error)"); return }
        XCTAssertEqual(first.text, "照明計画を考える。")
        let cached = await service.cached(documentId: "d", pageIndex: 0, engine: OCREngineID.pdfText)
        XCTAssertEqual(cached, first)
        XCTAssertEqual(try db.ocrEngines(documentId: "d", pageIndex: 0), [OCREngineID.pdfText])
        XCTAssertEqual(try db.ocrCacheStats().pages, 1)
        // Un autre moteur ne remplace pas le premier.
        _ = try await service.page(documentId: "d", url: url, pageIndex: 0, engine: OCREngineID.vision)
        XCTAssertEqual(Set(try db.ocrEngines(documentId: "d", pageIndex: 0)), [OCREngineID.pdfText, OCREngineID.vision])
        // Ancien format (sans version) : ignoré, donc refait.
        try db.save(OCRResultRecord(documentId: "d", pageIndex: 0, engine: "old",
                                    json: Data(#"{"engine":"old","lines":[],"durationMs":1}"#.utf8), durationMs: 1))
        let stale = await service.cached(documentId: "d", pageIndex: 0, engine: "old")
        XCTAssertNil(stale)
        try db.clearOCRCache(documentId: "d")
        XCTAssertEqual(try db.ocrCacheStats().pages, 0)
    }

    func testBenchStorage() throws {
        let db = try AppDatabase.inMemory()
        let sample = BenchSample(title: "Slide 1", imageFile: "a.png", referenceText: "照明")
        try db.save(sample)
        try db.save(BenchRun(sampleId: sample.id, engine: "vision", cer: 0.5, durationMs: 100, text: "照", createdAt: Date(timeIntervalSince1970: 1)))
        try db.save(BenchRun(sampleId: sample.id, engine: "vision", cer: 0.0, durationMs: 90, text: "照明", createdAt: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(try db.latestBenchRuns().map(\.cer), [0.0])
        try db.deleteBenchSample(id: sample.id)
        XCTAssertEqual(try db.benchRuns(sampleId: sample.id).count, 0, "cascade")
    }

    func testSettingsDecodeOCR() throws {
        let s = try JSONDecoder().decode(ReaderSettings.self, from: Data(#"{"ocrEngine":"vision"}"#.utf8))
        XCTAssertEqual(s.ocrEngine, .vision)
        var o = ReaderSettingsOverride()
        o.ocrEngine = .pdfText
        XCTAssertEqual(ReaderSettings.default.applying(o).ocrEngine, .pdfText)
        let app = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"textReader":{"fontSize":99}}"#.utf8))
        XCTAssertEqual(app.textReader.fontSize, 48, "borné")
    }
}
