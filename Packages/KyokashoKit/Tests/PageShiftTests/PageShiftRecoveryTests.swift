// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import CoreGraphics
import PDFKit
import OCRKit
import ReaderCore
import ReviewKit
import XCTest

@MainActor
final class PageShiftRecoveryTests: XCTestCase {
    func withFixture(_ test: (AppModel, LibraryDocument, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("page-shift-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let saved = PageShift.support
        PageShift.support = root
        DocumentAnalysisService.folder = root.appendingPathComponent("Analysis")
        defer {
            PageShift.support = saved
            try? FileManager.default.removeItem(at: root)
        }
        let model = try AppModel(root: root)
        let doc = LibraryDocument(id: "test-document", title: "Synthétique", originalFileName: "test.pdf", pageCount: 2, fileSize: 1)
        try model.database.save(doc)
        try FileManager.default.createDirectory(at: model.storage.root, withIntermediateDirectories: true)
        try writePDF(model.storage.url(for: doc.id), pages: 4)
        try FileManager.default.createDirectory(at: DocumentAnalysisService.folder.appendingPathComponent(doc.id), withIntermediateDirectories: true)
        try test(model, doc, root)
    }

    func writePDF(_ url: URL, pages: Int) throws {
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for index in 0..<pages {
            context.beginPDFPage(nil)
            context.fill(CGRect(x: 20 + index, y: 20, width: 10, height: 10))
            context.endPDFPage()
        }
        context.closePDF()
    }

    func marker(_ root: URL, stage: String) throws {
        let data = Data("""
        {"documentId":"test-document","offset":2,"oldCount":2,"oldSize":1,"newCount":4,"newSize":9,"stage":"\(stage)"}
        """.utf8)
        try data.write(to: root.appendingPathComponent("page-shift.json"))
    }

    func testLegacyCardsStageDoesNotDiscardAmbiguousRecovery() async throws {
        try withFixture { model, _, root in
            try marker(root, stage: "cards")
            PageShift.reconcile(model)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("page-shift.json").path),
                          "Un ancien journal ambigu doit rester disponible pour réparation.")
            XCTAssertNotNil(model.storageRecoveryError)
        }
    }

    func testLegacyReportStageDoesNotSilentlyAcceptUnshiftedReport() async throws {
        try withFixture { model, doc, root in
            var report = DocumentAnalysis(documentId: doc.id)
            report.pages[0] = .init(source: 0, baseEngine: "test")
            let url = DocumentAnalysisService.folder.appendingPathComponent(doc.id + ".json")
            try JSONEncoder().encode(report).write(to: url)
            try marker(root, stage: "report")
            PageShift.reconcile(model)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("page-shift.json").path))
            XCTAssertNotNil(model.storageRecoveryError,
                            "Le journal ne dit pas si le rapport a été décalé avant l'arrêt : ne pas conclure au succès.")
        }
    }

    func testLegacyFilesStageDoesNotShiftAlreadyInstalledFilesAgain() async throws {
        try withFixture { model, doc, root in
            let folder = DocumentAnalysisService.folder.appendingPathComponent(doc.id)
            let original = folder.appendingPathComponent("ovisocr2-2.md")
            try Data("page originale 0".utf8).write(to: original)
            try marker(root, stage: "files")
            PageShift.reconcile(model)
            XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "Une reprise ne doit pas ajouter encore 2 aux noms déjà décalés.")
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("ovisocr2-4.md").path))
        }
    }
}
