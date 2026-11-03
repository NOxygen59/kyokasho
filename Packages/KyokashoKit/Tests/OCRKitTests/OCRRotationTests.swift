// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import ReaderCore
import XCTest
@testable import OCRKit

final class OCRRotationTests: XCTestCase {
    func testRotatingBoxesClockwise() {
        let box = NormBox(x: 0.1, y: 0.2, w: 0.3, h: 0.1)
        let line = OCRLine(text: "字", box: box, charBoxes: [box], measuredCharBoxes: true,
                           vertical: false, confidence: 1)
        let source = OCRPage(engine: OCREngineID.pdfText, lines: [line], durationMs: 1)

        let clockwise = source.rotatedClockwise(90).lines[0]
        XCTAssertEqual(clockwise.box.x, 0.7, accuracy: 0.000_001)
        XCTAssertEqual(clockwise.box.y, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(clockwise.box.w, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(clockwise.box.h, 0.3, accuracy: 0.000_001)
        XCTAssertTrue(clockwise.vertical)

        let restored = source.rotatedClockwise(90).rotatedClockwise(270).lines[0]
        XCTAssertEqual(restored.box.x, box.x, accuracy: 0.000_001)
        XCTAssertEqual(restored.box.y, box.y, accuracy: 0.000_001)
        XCTAssertEqual(restored.box.w, box.w, accuracy: 0.000_001)
        XCTAssertEqual(restored.box.h, box.h, accuracy: 0.000_001)
        XCTAssertFalse(restored.vertical)
    }

    /// Une boîte OCR (repère de l'image tournée) doit tomber au même endroit une fois affichée, quelle que soit
    /// la rotation : c'est ce que les zones et les furigana supposent avec une rotation effective.
    func testFrameWithEffectiveRotationPlacesBoxWhereItIsDisplayed() {
        let box = CGRect(x: 10, y: 20, width: 600, height: 800)
        let ocrBox = NormBox(x: 0.1, y: 0.2, w: 0.3, h: 0.1)
        for intrinsic in [0, 90, 180, 270] {
            for additional in [0, 90, 180, 270] {
                let rotation = PageTransform.effectiveRotation(intrinsic: intrinsic, additional: additional)
                let onPage = PageFrame(box: box, rotation: rotation).pageRect(ocrBox)
                let shown = onPage.applying(PageGeometry.pageToView(box: box, rotation: rotation))
                let width = rotation % 180 == 0 ? box.width : box.height
                let height = rotation % 180 == 0 ? box.height : box.width
                XCTAssertEqual(shown.minX / width, ocrBox.x, accuracy: 0.000_001, "\(intrinsic)+\(additional)")
                XCTAssertEqual(shown.minY / height, ocrBox.y, accuracy: 0.000_001, "\(intrinsic)+\(additional)")
                XCTAssertEqual(shown.width / width, ocrBox.w, accuracy: 0.000_001, "\(intrinsic)+\(additional)")
                XCTAssertEqual(shown.height / height, ocrBox.h, accuracy: 0.000_001, "\(intrinsic)+\(additional)")
            }
        }
    }

    private func page(edited: Bool, version: Int = OCRPage.currentVersion) -> OCRPage {
        let box = NormBox(x: 0.1, y: 0.2, w: 0.3, h: 0.1)
        var line = OCRLine(text: "字", box: box, charBoxes: [box], measuredCharBoxes: true, vertical: false, confidence: 1)
        line.edited = edited ? true : nil
        return OCRPage(engine: OCREngineID.vision, lines: [line], durationMs: 1, version: version)
    }

    /// Recette 72 / revue B2 : une correction manuelle ne se recalcule pas, elle doit suivre la page.
    func testManualEditsSurviveRotationAndComeBackExactly() throws {
        let db = try AppDatabase.inMemory()
        try db.save(LibraryDocument(id: "d", title: "T", originalFileName: "t.pdf", pageCount: 2, fileSize: 1, firstPageIndex: 0))
        let encoder = JSONEncoder()
        let original = page(edited: true)
        try db.save(OCRResultRecord(documentId: "d", pageIndex: 0, engine: "edited", json: encoder.encode(original), durationMs: 1))
        try db.save(OCRResultRecord(documentId: "d", pageIndex: 0, engine: "plain", json: encoder.encode(page(edited: false)), durationMs: 1))

        try db.applyPageRotations(documentId: "d", rotations: [0: 90], keepingOCR: OCRPage.jsonKeepingManualEdits)
        XCTAssertNil(try db.ocrResult(documentId: "d", pageIndex: 0, engine: "plain"))
        let turned = try JSONDecoder().decode(OCRPage.self, from: XCTUnwrap(db.ocrResult(documentId: "d", pageIndex: 0, engine: "edited")).json)
        XCTAssertEqual(turned.lines[0].text, "字")
        XCTAssertEqual(turned.lines[0].edited, true)
        XCTAssertEqual(turned.lines[0].box.x, 0.7, accuracy: 0.000_001)

        try db.applyPageRotations(documentId: "d", rotations: [0: 0], keepingOCR: OCRPage.jsonKeepingManualEdits)
        let back = try JSONDecoder().decode(OCRPage.self, from: XCTUnwrap(db.ocrResult(documentId: "d", pageIndex: 0, engine: "edited")).json)
        XCTAssertEqual(back.lines[0].box.x, original.lines[0].box.x, accuracy: 0.000_001)
        XCTAssertEqual(back.lines[0].box.y, original.lines[0].box.y, accuracy: 0.000_001)
        XCTAssertEqual(back.lines[0].vertical, original.lines[0].vertical)
    }

    /// Revue M2 : un ancien résultat v5 corrigé à la main reste lisible sur une page déjà tournée.
    func testOldEditedResultIsKeptOnRotatedPageButPlainOneIsRedone() throws {
        XCTAssertNil(page(edited: false, version: 5).readable(atAdditionalRotation: 90))
        XCTAssertNotNil(page(edited: false, version: 5).readable(atAdditionalRotation: 0))
        XCTAssertNil(page(edited: true, version: 4).readable(atAdditionalRotation: 90))
        let kept = try XCTUnwrap(page(edited: true, version: 5).readable(atAdditionalRotation: 90))
        XCTAssertEqual(kept.version, OCRPage.currentVersion)
        XCTAssertEqual(kept.lines[0].box.x, 0.7, accuracy: 0.000_001)
    }

    /// Recette 74 : par défaut, une rotation ne perd aucun OCR, corrigé ou non.
    func testDefaultRotationKeepsEveryResultAndComesBackExactly() throws {
        let plain = page(edited: false)
        let json = try JSONEncoder().encode(plain)
        let turned = try XCTUnwrap(OCRPage.jsonFollowingRotation(json, fromRotation: 0, toRotation: 180))
        XCTAssertEqual(try JSONDecoder().decode(OCRPage.self, from: turned).lines[0].box.x, 0.6, accuracy: 0.000_001)
        let back = try XCTUnwrap(OCRPage.jsonFollowingRotation(turned, fromRotation: 180, toRotation: 0))
        XCTAssertEqual(try JSONDecoder().decode(OCRPage.self, from: back).lines[0].box.x, 0.1, accuracy: 0.000_001)
    }

    /// Revue Codex de la 74 : une correction trop ancienne pour être convertie ne doit pas être effacée.
    func testRotationNeverErasesEditsItCannotConvert() throws {
        let old = try JSONEncoder().encode(page(edited: true, version: 4))
        XCTAssertEqual(OCRPage.jsonKeepingManualEdits(old, fromRotation: 0, toRotation: 90), old)
        let unreadable = Data("{\"format\":\"inconnu\"}".utf8)
        XCTAssertEqual(OCRPage.jsonKeepingManualEdits(unreadable, fromRotation: 0, toRotation: 90), unreadable)
        let plain = try JSONEncoder().encode(page(edited: false, version: 4))
        XCTAssertNil(OCRPage.jsonKeepingManualEdits(plain, fromRotation: 0, toRotation: 90))
    }

    /// Le rendu pour l'OCR doit réellement tourner : un repère noir en haut à gauche de la page d'origine doit
    /// se retrouver dans le coin attendu de l'image, à chaque orientation.
    func testRendererPutsMarkInExpectedCornerForEachRotation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var media = CGRect(x: 0, y: 0, width: 200, height: 300)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &media, nil))
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 260, width: 40, height: 40))
        ctx.endPDFPage()
        ctx.closePDF()

        // Coin (gauche ?, haut ?) attendu après rotation horaire.
        let expected: [Int: (left: Bool, top: Bool)] = [
            0: (true, true), 90: (false, true), 180: (false, false), 270: (true, false),
        ]
        for (rotation, corner) in expected {
            let image = try PageRenderer.render(url: url, pageIndex: 0, longSide: 300, additionalRotation: rotation)
            XCTAssertEqual(image.width, rotation % 180 == 0 ? 200 : 300)
            let w = image.width, h = image.height
            let pixels = try XCTUnwrap(image.dataProvider?.data as Data?)
            let x = corner.left ? 10 : w - 10, y = corner.top ? 10 : h - 10
            XCTAssertLessThan(pixels[y * image.bytesPerRow + x], 50, "rotation \(rotation)")
            XCTAssertGreaterThan(pixels[(h - 1 - y) * image.bytesPerRow + (w - 1 - x)], 200, "rotation \(rotation)")
        }
    }
}
