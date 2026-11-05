// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import ZIPFoundation
@testable import ReaderCore

final class ComicBookArchiveTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    /// Image unie dont la taille identifie la page.
    private func image(width: Int, height: Int = 20, type: UTType = .jpeg) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func archive(_ files: [(String, Data)], name: String = "tome.cbz") throws -> URL {
        let url = folder.appendingPathComponent(name)
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    func testPagesFollowNaturalOrderAndSkipNoise() {
        XCTAssertEqual(ComicBookArchive.pageNames(["10.jpg", "2.JPG", "1.png", "notes.txt", ".cache.jpg", "__MACOSX/._1.jpg", "tome/3.webp"]),
                       ["1.png", "2.JPG", "10.jpg", "tome/3.webp"])
    }

    func testConversionKeepsOrderAndSkipsCorruptImages() throws {
        let source = try archive([("10.jpg", try image(width: 30)), ("2.jpg", try image(width: 20)),
                                  ("3.jpg", Data("pas une image".utf8)), ("info.txt", Data("x".utf8))])
        let output = folder.appendingPathComponent("sortie.pdf")
        let result = try ComicBookArchive.makePDF(from: source, to: output)
        XCTAssertEqual(result, .init(pages: 2, skipped: 1))
        let pdf = try XCTUnwrap(CGPDFDocument(output as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 2)
        XCTAssertEqual(pdf.page(at: 1)?.getBoxRect(.mediaBox).width, 20, "2.jpg avant 10.jpg")
        XCTAssertEqual(pdf.page(at: 2)?.getBoxRect(.mediaBox).width, 30)
    }

    func testJPEGIsNotRecompressed() throws {
        let source = try archive([("1.jpg", try image(width: 200, height: 200))])
        let output = folder.appendingPathComponent("sortie.pdf")
        _ = try ComicBookArchive.makePDF(from: source, to: output)
        XCTAssertNotNil(try Data(contentsOf: output).range(of: Data("DCTDecode".utf8)))
    }

    func testArchiveWithoutImageIsRefused() throws {
        let source = try archive([("info.txt", Data("x".utf8))])
        XCTAssertThrowsError(try ComicBookArchive.makePDF(from: source, to: folder.appendingPathComponent("sortie.pdf")))
    }

    func testImportIsAVisualReadingDocumentAndNotDuplicated() throws {
        let database = try AppDatabase.inMemory()
        let importer = DocumentImporter(storage: DocumentStorage(root: folder.appendingPathComponent("Docs")), database: database)
        let source = try archive([("1.jpg", try image(width: 30))])
        let first = try importer.importComicArchive(at: source)
        XCTAssertTrue(first.isNew)
        XCTAssertEqual(first.document.title, "tome")
        XCTAssertEqual(first.document.pageCount, 1)
        XCTAssertTrue(first.document.isComicArchive)
        let settings = first.document.settingsOverride
        XCTAssertEqual(settings.layout, .auto, "une page en portrait, deux en paysage, quels que soient les réglages généraux")
        XCTAssertEqual(settings.splitWidePages, false, "planches larges intactes")
        XCTAssertEqual(settings.direction, .rightToLeft)
        let second = try importer.importComicArchive(at: source)
        XCTAssertFalse(second.isNew)
        XCTAssertEqual(second.document.id, first.document.id)
    }

    /// Revue Codex de 2b55bd9 : la colonne `category` reste lisible par 1.4.5, où une valeur inconnue viderait la bibliothèque.
    func testComicIsStoredWithACategoryOldVersionsCanRead() throws {
        let database = try AppDatabase.inMemory()
        let importer = DocumentImporter(storage: DocumentStorage(root: folder.appendingPathComponent("Docs")), database: database)
        let document = try importer.importComicArchive(at: try archive([("1.jpg", try image(width: 30))])).document
        let stored = try database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT category FROM document WHERE id = ?", arguments: [document.id])
        }
        XCTAssertNil(stored)
        XCTAssertEqual(Set(DocumentCategory.allCases.map(\.rawValue)), ["book", "textbook"])
    }

    func testCapabilitiesComeFromTheFormatNotTheSpace() {
        var comic = LibraryDocument(id: "a", title: "t", originalFileName: "tome.CBZ", pageCount: 1, fileSize: 1)
        comic.category = .book
        let capabilities = comic.capabilities
        XCTAssertFalse(capabilities.textAnalysis || capabilities.study || capabilities.annotations
                       || capabilities.pageEditing || capabilities.export || capabilities.editableShelf)
        XCTAssertTrue(comic.isInMangaSpace, "un CBZ reste dans Manga, quelle que soit sa catégorie")
        var manga = LibraryDocument(id: "b", title: "t", originalFileName: "manga.pdf", pageCount: 1, fileSize: 1)
        XCTAssertFalse(manga.isInMangaSpace)
        var settings = ReaderSettingsOverride()
        settings.mangaSpace = true
        manga.settingsOverride = settings
        XCTAssertTrue(manga.isInMangaSpace)
        XCTAssertTrue(manga.capabilities.textAnalysis && manga.capabilities.study, "un manga PDF garde toutes ses fonctions")
    }

    func testMangaSpaceUpdateKeepsOtherSettings() throws {
        let database = try AppDatabase.inMemory()
        var document = LibraryDocument(id: "a", title: "t", originalFileName: "m.pdf", pageCount: 1, fileSize: 1)
        var settings = ReaderSettingsOverride()
        settings.direction = .rightToLeft
        document.settingsOverride = settings
        try database.save(document)
        try database.updateMangaSpace(documentId: "a", inManga: true)
        var saved = try XCTUnwrap(database.document(id: "a"))
        XCTAssertTrue(saved.isInMangaSpace)
        XCTAssertEqual(saved.settingsOverride.direction, .rightToLeft)
        try database.updateMangaSpace(documentId: "a", inManga: false)
        saved = try XCTUnwrap(database.document(id: "a"))
        XCTAssertFalse(saved.isInMangaSpace)
        XCTAssertEqual(saved.settingsOverride.direction, .rightToLeft)
    }

    /// Le CBZ est déjà stocké en PDF, et l'identifiant est l'empreinte du fichier : sans contenu différent, la conversion
    /// retomberait sur le même document.
    func testConversionCreatesASeparatePDFWithFullCapabilities() throws {
        let database = try AppDatabase.inMemory()
        let storage = DocumentStorage(root: folder.appendingPathComponent("Docs"))
        let importer = DocumentImporter(storage: storage, database: database)
        let comic = try importer.importComicArchive(at: try archive([("1.jpg", try image(width: 30)), ("2.jpg", try image(width: 40))])).document
        let result = try importer.convertComicToPDF(comic)
        XCTAssertTrue(result.isNew)
        XCTAssertNotEqual(result.document.id, comic.id)
        XCTAssertEqual(result.document.pageCount, 2)
        XCTAssertFalse(result.document.isComicArchive)
        XCTAssertTrue(result.document.isInMangaSpace)
        XCTAssertTrue(result.document.capabilities.textAnalysis)
        XCTAssertEqual(try DocumentImporter.sha256(of: storage.url(for: result.document.id)), result.document.id)
        XCTAssertNotNil(try database.document(id: comic.id), "le CBZ reste en place")
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.url(for: comic.id).path))
        let again = try importer.convertComicToPDF(comic)
        XCTAssertFalse(again.isNew)
        XCTAssertEqual(again.document.id, result.document.id)
    }

    func testConversionFollowsVolumeOrderAndSkipsPDF() {
        func doc(_ title: String, _ file: String) -> LibraryDocument {
            LibraryDocument(id: title, title: title, originalFileName: file, pageCount: 1, fileSize: 1)
        }
        let order = DocumentImporter.conversionOrder([doc("Tome 10", "a.cbz"), doc("Tome 2", "b.cbz"), doc("Manga", "c.pdf")])
        XCTAssertEqual(order.map(\.title), ["Tome 2", "Tome 10"])
    }

    /// Revue Codex de 2b55bd9 : une image immense n'est pas décodée entière.
    func testOversizedPageIsReduced() throws {
        let side = ComicBookArchive.maximumPageSide + 400
        let source = try archive([("1.png", try image(width: side, height: 40, type: .png))])
        let output = folder.appendingPathComponent("sortie.pdf")
        _ = try ComicBookArchive.makePDF(from: source, to: output)
        let box = try XCTUnwrap(CGPDFDocument(output as CFURL)?.page(at: 1)?.getBoxRect(.mediaBox))
        XCTAssertEqual(Int(box.width), ComicBookArchive.maximumPageSide)
    }

    /// Revue Codex de 2b55bd9 : orientations EXIF appliquées (de 5 à 8, largeur et hauteur s'échangent).
    func testExifOrientationsAreApplied() throws {
        for orientation in 1...8 {
            let pixels = try image(width: 40, height: 20)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(pixels as CFData, nil))
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImagePropertyOrientation: orientation] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let output = folder.appendingPathComponent("o\(orientation).pdf")
            _ = try ComicBookArchive.makePDF(from: try archive([("1.jpg", data as Data)], name: "o\(orientation).cbz"), to: output)
            let box = try XCTUnwrap(CGPDFDocument(output as CFURL)?.page(at: 1)?.getBoxRect(.mediaBox))
            XCTAssertEqual(box.size, orientation >= 5 ? CGSize(width: 20, height: 40) : CGSize(width: 40, height: 20), "orientation \(orientation)")
        }
    }

    /// Contre-revue Codex de f8a3fa9 : nettoyage après arrêt brutal, limité aux noms privés assez anciens.
    func testOnlyOldPrivateTemporariesAreRemoved() throws {
        let storage = DocumentStorage(root: folder)
        let old = Date().addingTimeInterval(-7200)
        func file(_ name: String, date: Date) throws -> URL {
            let url = folder.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            return url
        }
        let abandoned = [try file(UUID().uuidString + ".partial", date: old), try file(UUID().uuidString + ".page", date: old)]
        let kept = [try file(UUID().uuidString + ".partial", date: Date()), try file("abc.pdf", date: old),
                    try file("notes.partial", date: old), try file(UUID().uuidString + ".pdf", date: old)]
        let directory = folder.appendingPathComponent(UUID().uuidString + ".page")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: directory.path)
        XCTAssertEqual(storage.removeAbandonedTemporaries(), 2)
        for url in abandoned { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
        for url in kept + [directory] { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent) }
    }
}
