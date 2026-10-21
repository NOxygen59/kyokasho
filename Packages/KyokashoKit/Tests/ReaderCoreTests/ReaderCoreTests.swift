// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation
import XCTest
@testable import ReaderCore

/// Fabrique un petit PDF de test (jamais de vrai PDF dans le dépôt).
func makePDF(pages: Int, size: CGSize = CGSize(width: 595, height: 842), marker: String = "") throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
    var box = CGRect(origin: .zero, size: size)
    let info = [kCGPDFContextTitle as String: "Titre métadonnées" + marker] as CFDictionary
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, info) else { throw ImportError.notAPDF }
    for i in 0..<pages {
        ctx.beginPDFPage(nil)
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 100 + i, y: 100, width: 200, height: 300))
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return url
}

final class SettingsTests: XCTestCase {
    func testDecodingMissingKeysUsesDefaults() throws {
        let json = #"{"layout":"double","preloadCount":99}"#
        let s = try JSONDecoder().decode(ReaderSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.layout, .double)
        XCTAssertEqual(s.preloadCount, 10, "borné à 10")
        XCTAssertEqual(s.direction, ReaderSettings.default.direction)
        XCTAssertEqual(s.doubleTapZoom, true)
    }

    func testOverrideApplies() {
        var o = ReaderSettingsOverride()
        XCTAssertTrue(o.isEmpty)
        o.direction = .rightToLeft
        o.layout = .double
        let s = ReaderSettings.default.applying(o)
        XCTAssertEqual(s.direction, .rightToLeft)
        XCTAssertEqual(s.layout, .double)
        XCTAssertEqual(s.scrollMode, ReaderSettings.default.scrollMode)
        XCTAssertFalse(o.isEmpty)
    }

    func testDocumentOverrideRoundTrip() {
        var doc = LibraryDocument(id: "a", title: "t", originalFileName: "t.pdf", pageCount: 1, fileSize: 1)
        XCTAssertNil(doc.settingsJSON)
        var o = ReaderSettingsOverride()
        o.background = .white
        doc.settingsOverride = o
        XCTAssertEqual(doc.settingsOverride.background, .white)
        doc.settingsOverride = ReaderSettingsOverride()
        XCTAssertNil(doc.settingsJSON, "un réglage vide ne stocke rien")
    }
}

final class TapZoneTests: XCTestCase {
    func testLeftToRight() {
        let s = ReaderSettings.default
        XCTAssertEqual(TapZones.action(atFraction: 0.1, settings: s), .previous)
        XCTAssertEqual(TapZones.action(atFraction: 0.5, settings: s), .toggleBars)
        XCTAssertEqual(TapZones.action(atFraction: 0.9, settings: s), .next)
    }

    func testRightToLeftAndInvert() {
        var s = ReaderSettings.default
        s.direction = .rightToLeft
        XCTAssertEqual(TapZones.action(atFraction: 0.1, settings: s), .next)
        XCTAssertEqual(TapZones.action(atFraction: 0.9, settings: s), .previous)
        s.invertTapZones = true
        XCTAssertEqual(TapZones.action(atFraction: 0.1, settings: s), .previous)
        s.tapZonesEnabled = false
        XCTAssertEqual(TapZones.action(atFraction: 0.1, settings: s), .toggleBars)
    }
}

final class PresentationTests: XCTestCase {
    func testSplitOrder() {
        let ltr = PresentationLayout.pages(pageCount: 3, splitPages: [1], rightToLeft: false)
        XCTAssertEqual(ltr, [.init(source: 0, part: .whole), .init(source: 1, part: .left),
                             .init(source: 1, part: .right), .init(source: 2, part: .whole)])
        let rtl = PresentationLayout.pages(pageCount: 2, splitPages: [0], rightToLeft: true)
        XCTAssertEqual(rtl, [.init(source: 0, part: .right), .init(source: 0, part: .left), .init(source: 1, part: .whole)])
        XCTAssertEqual(PresentationLayout.presentedIndex(ofSource: 2, in: ltr), 3)
        XCTAssertEqual(PresentationLayout.presentedIndex(ofSource: 99, in: ltr), 3)
    }

    func testRightToLeftSpreadOrder() {
        XCTAssertEqual(PresentationLayout.rightToLeftSpreadOrder(count: 6, firstPageAlone: true), [0, 2, 1, 4, 3, 5])
        XCTAssertEqual(PresentationLayout.rightToLeftSpreadOrder(count: 5, firstPageAlone: false), [1, 0, 3, 2, 4])
        XCTAssertEqual(PresentationLayout.rightToLeftSpreadOrder(count: 1, firstPageAlone: true), [0])
        XCTAssertEqual(PresentationLayout.rightToLeftSpreadOrder(count: 0, firstPageAlone: true), [])
    }

    func testHalves() {
        let box = CGRect(x: 10, y: 20, width: 800, height: 600)
        XCTAssertEqual(PresentationLayout.box(for: .left, in: box), CGRect(x: 10, y: 20, width: 400, height: 600))
        XCTAssertEqual(PresentationLayout.box(for: .right, in: box), CGRect(x: 410, y: 20, width: 400, height: 600))
        XCTAssertTrue(PresentationLayout.isWide(CGSize(width: 1200, height: 842)))
        XCTAssertFalse(PresentationLayout.isWide(CGSize(width: 595, height: 842)))
    }
}

final class ContentBoundsTests: XCTestCase {
    func testDetectsInkRectangle() {
        let w = 100, h = 200
        var pixels = [UInt8](repeating: 250, count: w * h)
        for y in 50..<150 { for x in 20..<80 { pixels[y * w + x] = 10 } }
        pixels[5 * w + 5] = 0 // poussière isolée : ignorée
        let r = pixels.withUnsafeBufferPointer {
            ContentBounds.detect(pixels: $0, width: w, height: h, bytesPerRow: w, padding: 0)
        }
        XCTAssertEqual(r?.x ?? -1, 0.20, accuracy: 0.001)
        XCTAssertEqual(r?.y ?? -1, 0.25, accuracy: 0.001)
        XCTAssertEqual(r?.width ?? -1, 0.60, accuracy: 0.001)
        XCTAssertEqual(r?.height ?? -1, 0.50, accuracy: 0.001)
    }

    func testBlankPage() {
        let pixels = [UInt8](repeating: 255, count: 100)
        XCTAssertNil(pixels.withUnsafeBufferPointer { ContentBounds.detect(pixels: $0, width: 10, height: 10, bytesPerRow: 10) })
    }

    func testApplyCropFlipsY() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 200)
        let crop = NormalizedRect(x: 0.1, y: 0.25, width: 0.8, height: 0.5)
        XCTAssertEqual(ContentBounds.apply(crop, to: box), CGRect(x: 10, y: 50, width: 80, height: 100))
        XCTAssertEqual(ContentBounds.apply(NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1), to: box), box)
    }
}

final class GeometryTests: XCTestCase {
    func testTransformsCorners() {
        let box = CGRect(x: 10, y: 20, width: 100, height: 200)
        let bottomLeft = CGPoint(x: 10, y: 20)
        let topRight = CGPoint(x: 110, y: 220)
        let t0 = PageGeometry.pageToView(box: box, rotation: 0)
        XCTAssertEqual(bottomLeft.applying(t0), CGPoint(x: 0, y: 200))
        XCTAssertEqual(topRight.applying(t0), CGPoint(x: 100, y: 0))
        // 90° horaire : le bas-gauche part en haut-gauche ; la vue fait 200 × 100.
        let t90 = PageGeometry.pageToView(box: box, rotation: 90)
        XCTAssertEqual(bottomLeft.applying(t90), CGPoint(x: 0, y: 0))
        XCTAssertEqual(topRight.applying(t90), CGPoint(x: 200, y: 100))
        let t180 = PageGeometry.pageToView(box: box, rotation: 180)
        XCTAssertEqual(bottomLeft.applying(t180), CGPoint(x: 100, y: 0))
        let t270 = PageGeometry.pageToView(box: box, rotation: -90)
        XCTAssertEqual(bottomLeft.applying(t270), CGPoint(x: 200, y: 100))
    }
}

final class MarkdownTests: XCTestCase {
    func testExport() {
        let comments = [
            PageComment(documentId: "d", pageIndex: 2, body: "Second", createdAt: Date(timeIntervalSince1970: 2)),
            PageComment(documentId: "d", pageIndex: 0, body: "  Premier  "),
            PageComment(documentId: "d", pageIndex: 2, body: "Avant", createdAt: Date(timeIntervalSince1970: 1)),
        ]
        let highlights = [Highlight(documentId: "d", pageIndex: 0, rects: [], color: .yellow, text: "texte\nsurligné")]
        let md = MarkdownExporter.export(title: "Cours", comments: comments, highlights: highlights,
                                         date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(md.hasPrefix("# Cours\n"))
        XCTAssertTrue(md.contains("## Page 1\n\n> texte surligné\n\nPremier\n"))
        XCTAssertTrue(md.contains("## Page 3\n\nAvant\n\nSecond\n"))
        XCTAssertLessThan(md.range(of: "Page 1")!.lowerBound, md.range(of: "Page 3")!.lowerBound)
        XCTAssertTrue(MarkdownExporter.export(title: "Vide", comments: []).contains("Aucune note."))
    }
}

final class DatabaseTests: XCTestCase {
    var db: AppDatabase!

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
    }

    func testFirstPageIndex() throws {
        var doc = LibraryDocument(id: "d", title: "Manuel", originalFileName: "m.pdf", pageCount: 100, fileSize: 1)
        XCTAssertEqual(doc.pageLabel(0), "1")
        doc.firstPageIndex = 4
        XCTAssertEqual(doc.pageLabel(0), "i")
        XCTAssertEqual(doc.pageLabel(3), "iv")
        XCTAssertEqual(doc.pageLabel(4), "1")
        XCTAssertEqual(doc.pageLabel(13), "10")
        XCTAssertEqual(doc.sourceIndex(forPrintedPage: 10), 13)
        XCTAssertEqual(doc.sourceIndex(forPrintedPage: 500), 99)
        try db.save(doc)
        XCTAssertEqual(try db.document(id: "d")?.firstPageIndex, 4)
    }

    func testDefaultPromptsAndSettings() throws {
        XCTAssertEqual(try db.aiPrompts().count, AIPrompt.defaults.count)
        XCTAssertEqual(try db.readerDefaults(), .default)
        var s = ReaderSettings.default
        s.layout = .double
        try db.setReaderDefaults(s)
        XCTAssertEqual(try db.readerDefaults().layout, .double)
        var app = AppSettings()
        app.theme = .light
        try db.setAppSettings(app)
        XCTAssertEqual(try db.appSettings().theme, .light)
    }

    func testReadingPositionAndOrdering() throws {
        try db.save(LibraryDocument(id: "a", title: "A", originalFileName: "a.pdf", pageCount: 10, fileSize: 1, importedAt: Date(timeIntervalSince1970: 1)))
        try db.save(LibraryDocument(id: "b", title: "B", originalFileName: "b.pdf", pageCount: 10, fileSize: 1, importedAt: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(try db.allDocuments().map(\.id), ["b", "a"])
        try db.updateReadingPosition(documentId: "a", pageIndex: 7, at: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(try db.allDocuments().map(\.id), ["a", "b"], "le dernier ouvert en premier")
        XCTAssertEqual(try db.document(id: "a")?.lastPageIndex, 7)
    }

    func testCascadeDeleteAndRekey() throws {
        try db.save(LibraryDocument(id: "old", title: "Cours", originalFileName: "c.pdf", pageCount: 5, fileSize: 1))
        try db.save(PageComment(documentId: "old", pageIndex: 1, body: "note"))
        try db.save(Highlight(documentId: "old", pageIndex: 1, rects: [PageRect(x: 1, y: 2, width: 3, height: 4)], color: .green, text: "x"))
        try db.save(InkDrawing(documentId: "old", pageIndex: 2, data: Data([1, 2, 3])), isEmpty: false)
        try db.save(Bookmark(documentId: "old", pageIndex: 3, title: "Chapitre"))
        try db.save(PageTransform(documentId: "old", pageIndex: 0, rotation: 90))

        var new = try XCTUnwrap(db.document(id: "old"))
        new.id = "new"
        new.pageCount = 6
        try db.rekeyDocument(from: "old", to: new)
        XCTAssertNil(try db.document(id: "old"))
        XCTAssertEqual(try db.document(id: "new")?.pageCount, 6)
        XCTAssertEqual(try db.comments(documentId: "new").count, 1)
        XCTAssertEqual(try db.highlights(documentId: "new").first?.rects, [PageRect(x: 1, y: 2, width: 3, height: 4)])
        XCTAssertEqual(try db.inkDrawing(documentId: "new", pageIndex: 2)?.data, Data([1, 2, 3]))
        XCTAssertEqual(try db.bookmarks(documentId: "new").count, 1)
        XCTAssertEqual(try db.pageTransforms(documentId: "new")[0]?.rotation, 90)

        try db.deleteDocument(id: "new")
        XCTAssertEqual(try db.comments(documentId: "new").count, 0, "suppression en cascade")
        XCTAssertEqual(try db.pagesWithInk(documentId: "new"), [])
    }

    func testEmptyInkDeletesRow() throws {
        try db.save(LibraryDocument(id: "d", title: "D", originalFileName: "d.pdf", pageCount: 1, fileSize: 1))
        try db.save(InkDrawing(documentId: "d", pageIndex: 0, data: Data([9])), isEmpty: false)
        XCTAssertEqual(try db.pagesWithInk(documentId: "d"), [0])
        try db.save(InkDrawing(documentId: "d", pageIndex: 0, data: Data()), isEmpty: true)
        XCTAssertEqual(try db.pagesWithInk(documentId: "d"), [])
    }

    func testAutoCropStoredAsJSON() throws {
        try db.save(LibraryDocument(id: "d", title: "D", originalFileName: "d.pdf", pageCount: 1, fileSize: 1))
        let crop = NormalizedRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
        try db.save([PageTransform(documentId: "d", pageIndex: 0, autoCrop: crop)])
        XCTAssertEqual(try db.pageTransforms(documentId: "d")[0]?.autoCrop, crop)
    }
}

final class ImporterTests: XCTestCase {
    var root: URL!
    var importer: DocumentImporter!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        importer = DocumentImporter(storage: DocumentStorage(root: root), database: try AppDatabase.inMemory())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testImportCopiesHashesAndDeduplicates() throws {
        let pdf = try makePDF(pages: 3)
        let first = try importer.importFile(at: pdf, displayName: "設計製図.pdf")
        XCTAssertTrue(first.isNew)
        XCTAssertEqual(first.document.pageCount, 3)
        XCTAssertEqual(first.document.title, "設計製図")
        XCTAssertEqual(first.document.id, try DocumentImporter.sha256(of: pdf))
        XCTAssertEqual(first.document.id.count, 64)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importer.storage.url(for: first.document.id).path))

        let again = try importer.importFile(at: pdf, displayName: "copie.pdf")
        XCTAssertFalse(again.isNew)
        XCTAssertEqual(try importer.database.allDocuments().count, 1)
    }

    func testMetadataTitleOption() throws {
        let pdf = try makePDF(pages: 1)
        let result = try importer.importFile(at: pdf, displayName: "x.pdf", preferFileNameTitle: false)
        XCTAssertEqual(result.document.title, "Titre métadonnées")
    }

    func testRejectsNonPDF() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try Data("pas un pdf".utf8).write(to: url)
        XCTAssertThrowsError(try importer.importFile(at: url)) { XCTAssertEqual($0 as? ImportError, .notAPDF) }
        XCTAssertEqual(try importer.database.allDocuments().count, 0)
    }

    func testReplaceKeepsNotes() throws {
        let v1 = try importer.importFile(at: try makePDF(pages: 4, marker: "1")).document
        try importer.database.save(PageComment(documentId: v1.id, pageIndex: 3, body: "garde-moi"))
        try importer.database.updateReadingPosition(documentId: v1.id, pageIndex: 3)
        let v2 = try importer.replace(documentId: v1.id, withFileAt: try makePDF(pages: 2, marker: "2"), driveRevision: "r2")
        XCTAssertNotEqual(v1.id, v2.id)
        XCTAssertEqual(v2.pageCount, 2)
        XCTAssertEqual(v2.lastPageIndex, 1, "position bornée au nouveau nombre de pages")
        XCTAssertEqual(try importer.database.comments(documentId: v2.id).first?.body, "garde-moi")
        XCTAssertFalse(FileManager.default.fileExists(atPath: importer.storage.url(for: v1.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importer.storage.url(for: v2.id).path))
    }

    func testDeleteRemovesFile() throws {
        let doc = try importer.importFile(at: try makePDF(pages: 1)).document
        try importer.delete(documentId: doc.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: importer.storage.url(for: doc.id).path))
        XCTAssertNil(try importer.database.document(id: doc.id))
    }

    func testHashPerformance() throws {
        // ~8 Mo : le hachage par blocs doit rester rapide et sans pic mémoire.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 7, count: 8 << 20).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        measure { _ = try? DocumentImporter.sha256(of: url) }
    }
}
