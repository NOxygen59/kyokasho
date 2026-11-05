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

    /// Mesure sur Mac d'une conversion lourde en PNG, à lancer à la main : KYOKASHO_HEAVY_CBZ=1 swift test --filter testHeavyPNG.
    /// Ne remplace pas l'essai sur iPad. Pages de bruit : le pire cas, car le PNG ne les compresse presque pas.
    func testHeavyPNGConversionMeasure() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KYOKASHO_HEAVY_CBZ"] != nil, "mesure manuelle")
        let width = 2000, height = 3000, count = 40
        let url = folder.appendingPathComponent("lourd.cbz")
        let archive = try Archive(url: url, accessMode: .create)
        var generator = SystemRandomNumberGenerator()
        for index in 0..<count {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            for position in stride(from: 0, to: bytes.count, by: 8) {
                let value = generator.next() as UInt64
                withUnsafeBytes(of: value) { source in
                    for offset in 0..<min(8, bytes.count - position) { bytes[position + offset] = source[offset] }
                }
            }
            let context = try XCTUnwrap(bytes.withUnsafeMutableBytes { buffer in
                CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            })
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let page = data as Data
            try archive.addEntry(with: "\(index).png", type: .file, uncompressedSize: Int64(page.count), compressionMethod: .none) { position, size in
                page.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        func footprintMB() -> Double {
            var info = task_vm_info_data_t()
            var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            _ = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size) }
            }
            return Double(info.phys_footprint) / 1_048_576
        }
        let output = folder.appendingPathComponent("lourd.pdf")
        let baseline = footprintMB()
        var peak = baseline
        let start = Date(), cpuStart = ThreadCPU.seconds()
        let result = try ComicBookArchive.makePDF(from: url, to: output) { _, _ in peak = max(peak, footprintMB()); return .max }
        let input = try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let produced = try XCTUnwrap(output.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        print("MESURE CBZ \(input / 1_048_576) Mo -> PDF \(produced / 1_048_576) Mo, x\(Double(produced) / Double(input)), \(result.pages) pages, durée \(Date().timeIntervalSince(start)) s, CPU \(ThreadCPU.seconds() - cpuStart) s, mémoire +\(peak - baseline) Mo")
    }

    /// Revue Codex de 291c02f : la dernière écriture peut franchir la réserve, sans page suivante pour le voir.
    /// Vise le contrôle après fermeture lui-même (contre-revue de ff60a3a) : le retirer ferait échouer ce test.
    func testReserveCrossedAtCloseFailsWithoutLeavingFile() throws {
        let source = try archive([("1.jpg", try image(width: 30)), ("2.jpg", try image(width: 40))])
        let output = folder.appendingPathComponent("sortie.pdf")
        XCTAssertThrowsError(try ComicBookArchive.makePDF(from: source, to: output) { check, _ in
            check == .afterClose ? ComicBookArchive.minimumFreeBytes - 1 : .max
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try partials(), [])
    }

    func testRewriteReserveCrossedAtCloseFailsWithoutLeavingFile() throws {
        let source = try archive([("1.jpg", try image(width: 30))])
        let pdf = folder.appendingPathComponent("source.pdf")
        _ = try ComicBookArchive.makePDF(from: source, to: pdf)
        let output = folder.appendingPathComponent("copie.pdf")
        XCTAssertThrowsError(try ComicBookArchive.rewritePDF(pdf, to: output, title: "T") { check, _ in
            check == .afterClose ? 0 : .max
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try partials(), [])
    }

    private func partials() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".partial") || $0.hasSuffix(".page") }
    }

    /// Au-dessus de la réserve, mais pas assez pour la page à écrire : refus avant d'écrire.
    func testRoomMustCoverNextPage() throws {
        let free = ComicBookArchive.minimumFreeBytes
        XCTAssertNoThrow(try ComicBookArchive.ensureRoom(in: folder, check: .afterClose) { _, _ in free })
        XCTAssertThrowsError(try ComicBookArchive.ensureRoom(in: folder, forNext: 2, check: .beforePage) { _, _ in free + 1 })
        XCTAssertNoThrow(try ComicBookArchive.ensureRoom(in: folder, forNext: 2, check: .beforePage) { _, _ in free + 2 })
    }

    /// Contre-revue de ff60a3a : un refus ne doit jamais toucher un fichier déjà à cette place.
    func testFailureKeepsExistingDestination() throws {
        let output = folder.appendingPathComponent("existant.pdf")
        let original = Data("ne pas toucher".utf8)
        try original.write(to: output)
        let notArchive = folder.appendingPathComponent("faux.cbz")
        try Data("pas une archive".utf8).write(to: notArchive)
        XCTAssertThrowsError(try ComicBookArchive.makePDF(from: notArchive, to: output))
        XCTAssertEqual(try Data(contentsOf: output), original)
        let source = try archive([("1.jpg", try image(width: 30))])
        XCTAssertThrowsError(try ComicBookArchive.makePDF(from: source, to: output) { check, _ in check == .afterClose ? 0 : .max })
        XCTAssertEqual(try Data(contentsOf: output), original)
        XCTAssertNoThrow(try ComicBookArchive.makePDF(from: source, to: output))
        XCTAssertEqual(CGPDFDocument(output as CFURL)?.numberOfPages, 1)
        XCTAssertEqual(try partials(), [])
    }

    /// Le PDF écrit à la main doit s'ouvrir et se dessiner comme l'image d'origine.
    func testWrittenPagesDrawTheirImage() throws {
        for (name, type): (String, UTType) in [("1.jpg", .jpeg), ("2.png", .png)] {
            let source = try archive([(name, try image(width: 64, height: 48, type: type))], name: name + ".cbz")
            let output = folder.appendingPathComponent(name + ".pdf")
            XCTAssertEqual(try ComicBookArchive.makePDF(from: source, to: output).pages, 1)
            let page = try XCTUnwrap(CGPDFDocument(output as CFURL)?.page(at: 1))
            XCTAssertEqual(page.getBoxRect(.mediaBox).size, CGSize(width: 64, height: 48))
            let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
            context.drawPDFPage(page)
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            let center = (24 * context.bytesPerRow) + 32 * 4
            XCTAssertEqual(Double(pixels[center]), 204, accuracy: 12, name)
            XCTAssertEqual(Double(pixels[center + 1]), 51, accuracy: 12, name)
            XCTAssertEqual(Double(pixels[center + 2]), 51, accuracy: 12, name)
        }
    }

    /// Pas de chat sur un manga, en PDF comme en CBZ ; le reste du panneau d'étude d'un manga PDF demeure.
    func testChatIsOffOnManga() {
        var pdf = LibraryDocument(id: "a", title: "a", originalFileName: "a.pdf", pageCount: 1, fileSize: 1)
        XCTAssertTrue(pdf.capabilities.chat)
        pdf.settingsOverride.mangaSpace = true
        XCTAssertFalse(pdf.capabilities.chat)
        XCTAssertTrue(pdf.capabilities.study)
        let comic = LibraryDocument(id: "b", title: "b", originalFileName: "b.cbz", pageCount: 1, fileSize: 1)
        XCTAssertFalse(comic.capabilities.chat)
    }

    /// Contre-revue : une grande page à décoder respecte son budget de pixels ; ses proportions restent.
    func testDecodedPageRespectsPixelBudget() throws {
        let source = try archive([("1.png", try image(width: 5000, height: 4000, type: .png))])
        let output = folder.appendingPathComponent("sortie.pdf")
        _ = try ComicBookArchive.makePDF(from: source, to: output)
        let box = try XCTUnwrap(CGPDFDocument(output as CFURL)?.page(at: 1)?.getBoxRect(.mediaBox))
        XCTAssertLessThanOrEqual(Int(box.width) * Int(box.height), ComicBookArchive.maximumDecodedPixels + 10_000)
        XCTAssertGreaterThan(Int(box.width) * Int(box.height), ComicBookArchive.maximumDecodedPixels * 9 / 10)
        XCTAssertEqual(box.width / box.height, 1.25, accuracy: 0.01)
    }

    /// Revue Codex : la voie de secours, qui garde tout en mémoire, refuse les gros fichiers. Fin de fichier sans table lisible.
    func testCoreGraphicsFallbackIsBounded() throws {
        let source = try archive([("1.jpg", try image(width: 30))])
        let pdf = folder.appendingPathComponent("source.pdf")
        _ = try ComicBookArchive.makePDF(from: source, to: pdf)
        var bytes = try Data(contentsOf: pdf)
        bytes.append(Data(repeating: 0x20, count: 5000))
        try bytes.write(to: pdf)
        let output = folder.appendingPathComponent("copie.pdf")
        XCTAssertThrowsError(try ComicBookArchive.rewritePDF(pdf, to: output, title: "T", coreGraphicsLimit: 10) { _, _ in .max })
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertNoThrow(try ComicBookArchive.rewritePDF(pdf, to: output, title: "T") { _, _ in .max })
        XCTAssertEqual(CGPDFDocument(output as CFURL)?.numberOfPages, 1)
    }

    /// Les CBZ déjà importés ont été écrits par Core Graphics : ils doivent prendre la voie sans mémoire, pas la voie de secours.
    func testOldCoreGraphicsPDFUsesTitleUpdate() throws {
        let pdf = folder.appendingPathComponent("ancien.pdf")
        var box = CGRect(x: 0, y: 0, width: 50, height: 50)
        let context = try XCTUnwrap(CGContext(pdf as CFURL, mediaBox: &box, nil))
        context.beginPage(mediaBox: &box)
        context.endPage()
        context.closePDF()
        let output = folder.appendingPathComponent("copie.pdf")
        try ComicBookArchive.rewritePDF(pdf, to: output, title: "Tome", coreGraphicsLimit: 0) { _, _ in .max }
        let before = try Data(contentsOf: pdf)
        XCTAssertEqual(try Data(contentsOf: output).prefix(before.count), before)
        XCTAssertEqual(CGPDFDocument(output as CFURL)?.numberOfPages, 1)
    }

    /// Une image en niveaux de gris reste grise, et sort juste malgré le filtre sur place.
    func testGrayPNGDrawsRightAndStaysGray() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        context.setFillColor(gray: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 15, width: 40, height: 15))
        let page = try XCTUnwrap(ImagePDFWriter.losslessPage(try XCTUnwrap(context.makeImage())))
        XCTAssertEqual(page.colorSpace, "DeviceGray")
        let output = folder.appendingPathComponent("gris.pdf")
        let writer = try ImagePDFWriter(url: output)
        try writer.add(page)
        try writer.finish()
        let drawn = try XCTUnwrap(CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 40,
                                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        drawn.drawPDFPage(try XCTUnwrap(CGPDFDocument(output as CFURL)?.page(at: 1)))
        let pixels = try XCTUnwrap(drawn.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(Double(pixels[5 * 40 + 20]), 0.9 * 255, accuracy: 4, "haut de l'image")
        XCTAssertEqual(Double(pixels[25 * 40 + 20]), 0.3 * 255, accuracy: 4, "bas de l'image")
    }

    /// Le JPEG entre tel quel dans le PDF, sans recompression.
    func testJPEGIsCopiedUnchanged() throws {
        let jpeg = try image(width: 80, height: 60)
        let source = try archive([("1.jpg", jpeg)])
        let output = folder.appendingPathComponent("sortie.pdf")
        _ = try ComicBookArchive.makePDF(from: source, to: output)
        XCTAssertNotNil(try Data(contentsOf: output).range(of: jpeg))
    }

    /// Titre ajouté sans toucher aux octets d'origine : l'empreinte change, les pages restent, et la mise à jour survit à une
    /// seconde mise à jour.
    func testTitleUpdateKeepsOriginalBytes() throws {
        let source = try archive([("1.jpg", try image(width: 30)), ("2.jpg", try image(width: 40))])
        let pdf = folder.appendingPathComponent("source.pdf")
        _ = try ComicBookArchive.makePDF(from: source, to: pdf)
        let copy = folder.appendingPathComponent("copie.pdf")
        try ComicBookArchive.rewritePDF(pdf, to: copy, title: "転生 Tome 2")
        let (before, after) = (try Data(contentsOf: pdf), try Data(contentsOf: copy))
        XCTAssertEqual(after.prefix(before.count), before)
        XCTAssertGreaterThan(after.count, before.count)
        let document = try XCTUnwrap(CGPDFDocument(copy as CFURL))
        XCTAssertEqual(document.numberOfPages, 2)
        var title: CGPDFStringRef?
        XCTAssertTrue(CGPDFDictionaryGetString(try XCTUnwrap(document.info), "Title", &title))
        XCTAssertEqual(CGPDFStringCopyTextString(try XCTUnwrap(title)) as String?, "転生 Tome 2")
        let again = folder.appendingPathComponent("encore.pdf")
        try ComicBookArchive.rewritePDF(copy, to: again, title: "Autre")
        XCTAssertEqual(CGPDFDocument(again as CFURL)?.numberOfPages, 2)
    }

    func testZlibStreamMatchesKnownChecksum() throws {
        // Adler-32 de « Wikipedia » : 0x11E60398.
        let stream = try XCTUnwrap(ImagePDFWriter.zlib(Array("Wikipedia".utf8)))
        XCTAssertEqual(Array(stream.suffix(4)), [0x11, 0xE6, 0x03, 0x98])
        XCTAssertEqual(Array(stream.prefix(2)), [0x78, 0x9C])
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

    /// Revue Codex de d350047 : la conversion ne doit pas gonfler un CBZ en JPEG, images reprises sans recompression.
    func testConvertedPDFKeepsJPEGCompressionAndSize() throws {
        let database = try AppDatabase.inMemory()
        let storage = DocumentStorage(root: folder.appendingPathComponent("Docs"))
        let importer = DocumentImporter(storage: storage, database: database)
        let pages = try (0..<6).map { ("\($0).jpg", try noisyJPEG(side: 600 + $0)) }
        let comic = try importer.importComicArchive(at: try archive(pages)).document
        let converted = try importer.convertComicToPDF(comic).document
        let data = try Data(contentsOf: storage.url(for: converted.id))
        XCTAssertNotNil(data.range(of: Data("DCTDecode".utf8)))
        XCTAssertLessThan(Double(converted.fileSize), Double(comic.fileSize) * 1.05 + 4096,
                          "CBZ \(comic.fileSize) octets, PDF \(converted.fileSize) octets")
    }

    /// Image difficile à compresser : un écart de taille se verrait.
    private func noisyJPEG(side: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        var generator = SystemRandomNumberGenerator()
        let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: context.bytesPerRow * side)
        for index in 0..<(context.bytesPerRow * side) { pixels[index] = UInt8.random(in: 0...255, using: &generator) }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testResetIgnoresTheMangaSpace() {
        var settings = ReaderSettingsOverride()
        settings.mangaSpace = true
        XCTAssertFalse(settings.hasReaderOverrides)
        settings.direction = .rightToLeft
        XCTAssertTrue(settings.hasReaderOverrides)
    }

    func testSelectionKeepsTouchOrder() {
        var batch = BatchDeletion()
        for id in ["c", "a", "b"] { batch.toggle(id) }
        batch.toggle("a")
        XCTAssertEqual(batch.order, ["c", "b"])
    }

    /// Part de temps active : pas de valeur après la fin, fin en double sans effet, tri par activité.
    func testActivityLedgerReportsBusyShareOnly() {
        var ledger = ActivityLedger()
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(ledger.snapshot(at: start), [])
        let one = UUID(), two = UUID()
        ledger.begin(one, kind: "a", detail: "x", at: start)
        ledger.begin(two, kind: "b", detail: nil, at: start.addingTimeInterval(1.5))
        var rows = ledger.snapshot(at: start.addingTimeInterval(2))
        XCTAssertEqual(rows.map(\.kind), ["a", "b"])
        XCTAssertEqual(rows[0].busyShare, 1, accuracy: 0.001)
        XCTAssertEqual(rows[1].busyShare, 0.25, accuracy: 0.001)
        XCTAssertEqual(rows[0].detail, "x")
        ledger.end(one, at: start.addingTimeInterval(3))
        ledger.end(one, at: start.addingTimeInterval(3))
        rows = ledger.snapshot(at: start.addingTimeInterval(4))
        XCTAssertEqual(rows.first { $0.kind == "a" }?.busyShare ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(ledger.snapshot(at: start.addingTimeInterval(5)).map(\.kind), ["b"])
    }
}
