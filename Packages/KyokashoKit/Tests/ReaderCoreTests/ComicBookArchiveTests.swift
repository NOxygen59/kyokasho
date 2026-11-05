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

    func testImportIsAComicReadRightToLeftAndNotDuplicated() throws {
        let database = try AppDatabase.inMemory()
        let importer = DocumentImporter(storage: DocumentStorage(root: folder.appendingPathComponent("Docs")), database: database)
        let source = try archive([("1.jpg", try image(width: 30))])
        let first = try importer.importComicArchive(at: source)
        XCTAssertTrue(first.isNew)
        XCTAssertEqual(first.document.title, "tome")
        XCTAssertEqual(first.document.pageCount, 1)
        XCTAssertTrue(first.document.isComic)
        XCTAssertEqual(first.document.settingsOverride.direction, .rightToLeft)
        let saved = try XCTUnwrap(database.document(id: first.document.id))
        XCTAssertEqual(saved.category, .comics)
        let second = try importer.importComicArchive(at: source)
        XCTAssertFalse(second.isNew)
        XCTAssertEqual(second.document.id, first.document.id)
    }
}
