// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
import ZIPFoundation
@testable import ReaderCore

/// Paquet `.kyokasho` : aller-retour complet et refus des paquets altérés (données synthétiques).
final class DocumentPackageTests: XCTestCase {
    var root: URL!
    var pdf: URL!
    var id: String!
    var source: AppDatabase!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kyokasho-package-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Comme dans l'app : l'identifiant est l'empreinte du PDF importé, puis une page ajoutée change le PDF.
        let marker = UUID().uuidString
        id = try DocumentImporter.sha256(of: try makePDF(pages: 3, marker: marker))
        pdf = try makePDF(pages: 4, marker: marker)
        let size = Int64(try pdf.resourceValues(forKeys: [.fileSizeKey]).fileSize!)
        source = try AppDatabase.inMemory()
        var doc = LibraryDocument(id: id, title: "Manuel 図", originalFileName: "m.pdf", pageCount: 3, fileSize: 9)
        doc.firstPageIndex = 1
        doc.lastPageIndex = 2
        try source.save(doc)
        try source.save(PageComment(documentId: id, pageIndex: 2, body: "note", drawing: Data([0, 255])))
        try source.save(Highlight(documentId: id, pageIndex: 1, rects: [], color: .yellow, text: "surligné"))
        try source.writer.write { db in
            try OCRResultRecord(documentId: self.id, pageIndex: 1, engine: "retouche", json: Data([1, 2]), durationMs: 3).insert(db)
        }
        try source.remapPages(documentId: id, mapping: PageMapping.insertion(oldCount: 3, inserted: 1, at: 3), editId: "e",
                              kind: .insertion, expectedVersion: 0, fileSize: size)
        try source.save(LibraryDocument(id: "autre", title: "Autre", originalFileName: "a.pdf", pageCount: 1, fileSize: 1))
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func analysisFolder() throws -> URL {
        let folder = root.appendingPathComponent("analysis-source")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("lecture".utf8).write(to: folder.appendingPathComponent("ovisocr2-1.md"))
        try Data("translation".utf8).write(to: folder.appendingPathComponent("en-1.md"))
        try Data("traduction".utf8).write(to: folder.appendingPathComponent("fr-1.md"))
        return folder
    }

    private func export(_ name: String = "p.kyokasho") throws -> URL {
        let zip = root.appendingPathComponent(name)
        let report = root.appendingPathComponent("report.json")
        try Data("{\"r\":1}".utf8).write(to: report)
        try DocumentPackage.write(to: zip, documentId: id, title: "Manuel 図", pageCount: 4, appVersion: "test",
                                  pdf: pdf, rows: source.packageRows(documentId: id), analysisFolder: analysisFolder(),
                                  report: report, drafts: [2: "brouillon"], preferences: ["ocrLanguage": "japanese"],
                                  dictionaries: ["Jitendex.org"])
        return zip
    }

    func testRoundTripRestoresEverythingOnAnEmptyDevice() throws {
        let zip = try export()
        let contents = try DocumentPackage.open(zip, into: root.appendingPathComponent("open"))
        XCTAssertEqual(contents.manifest.documentId, id)
        XCTAssertEqual(contents.manifest.dictionaries, ["Jitendex.org"])
        XCTAssertEqual(Set(contents.analysisFiles.keys), ["ovisocr2-1.md", "en-1.md", "fr-1.md"])
        XCTAssertEqual(try String(contentsOf: contents.analysisFiles["en-1.md"]!), "translation")
        XCTAssertEqual(contents.drafts, [2: "brouillon"])
        XCTAssertEqual(contents.preferences, ["ocrLanguage": "japanese"])
        XCTAssertEqual(try DocumentImporter.sha256(of: contents.pdf), try DocumentImporter.sha256(of: pdf), "le PDF actuel, pas l'importé")

        let target = try AppDatabase.inMemory()
        try target.installPackage(documentId: id, rows: contents.rows, replacing: false)
        XCTAssertEqual(try target.packageRows(documentId: id), try source.packageRows(documentId: id))
        let doc = try XCTUnwrap(target.document(id: id))
        XCTAssertEqual([doc.pageCount, doc.firstPageIndex, doc.lastPageIndex], [4, 1, 2])
        XCTAssertEqual(try target.comments(documentId: id).first?.drawing, Data([0, 255]))
        XCTAssertEqual(try target.printedNumbers()[id], try source.printedNumbers()[id])
        XCTAssertNil(try target.document(id: "autre"), "un seul document dans le paquet")
    }

    func testExistingDocumentIsNeverOverwrittenWithoutReplacing() throws {
        let contents = try DocumentPackage.open(export(), into: root.appendingPathComponent("open"))
        let target = try AppDatabase.inMemory()
        try target.save(LibraryDocument(id: id, title: "Local", originalFileName: "m.pdf", pageCount: 3, fileSize: 9))
        try target.save(PageComment(documentId: id, pageIndex: 0, body: "locale"))
        XCTAssertThrowsError(try target.installPackage(documentId: id, rows: contents.rows, replacing: false))
        XCTAssertEqual(try target.comments(documentId: id).map(\.body), ["locale"])
        try target.installPackage(documentId: id, rows: contents.rows, replacing: true)
        XCTAssertEqual(try target.comments(documentId: id).map(\.body), ["note"])
        XCTAssertEqual(try target.document(id: id)?.title, "Manuel 図")
    }

    func testTamperedOrForeignPackagesAreRefusedWithoutEffect() throws {
        let zip = try export()
        // Fichier ajouté.
        let extra = try Archive(url: zip, accessMode: .update)
        try extra.addEntry(with: "analysis/en-2.md", type: .file, uncompressedSize: Int64(1)) { (_: Int64, _: Int) in Data("x".utf8) }
        XCTAssertThrowsError(try DocumentPackage.open(zip, into: root.appendingPathComponent("a")))
        // Chemin hors du paquet.
        let evil = try export("evil.kyokasho")
        try Archive(url: evil, accessMode: .update).addEntry(with: "../evil.md", type: .file, uncompressedSize: Int64(1)) { (_: Int64, _: Int) in Data("x".utf8) }
        XCTAssertThrowsError(try DocumentPackage.open(evil, into: root.appendingPathComponent("b")))
        // Pas un zip.
        let text = root.appendingPathComponent("faux.kyokasho")
        try Data("pas un zip".utf8).write(to: text)
        XCTAssertThrowsError(try DocumentPackage.open(text, into: root.appendingPathComponent("c")))
        // Lignes d'un autre document ou colonne inconnue : rien n'est installé.
        let contents = try DocumentPackage.open(try export("ok.kyokasho"), into: root.appendingPathComponent("d"))
        var foreign = contents.rows
        foreign["pageComment"]?[0]["documentId"] = .text("autre")
        let target = try AppDatabase.inMemory()
        XCTAssertThrowsError(try target.installPackage(documentId: id, rows: foreign, replacing: false))
        XCTAssertNil(try target.document(id: id))
        var newer = contents.rows
        newer["highlight"]?[0]["colonneFuture"] = .integer(1)
        XCTAssertThrowsError(try target.installPackage(documentId: id, rows: newer, replacing: false))
        XCTAssertNil(try target.document(id: id))
    }

    /// Recette 68 : un document dont les pages ont changé (PDF ≠ identifiant) s'exporte et se réimporte.
    func testDocumentWhosePagesChangedCanBeExportedAndOpened() throws {
        XCTAssertNotEqual(try DocumentImporter.sha256(of: pdf), id)
        let contents = try DocumentPackage.open(try export(), into: root.appendingPathComponent("o"))
        XCTAssertEqual(contents.manifest.documentId, id)
        XCTAssertEqual(try DocumentImporter.sha256(of: contents.pdf), try DocumentImporter.sha256(of: pdf))
    }

    func testExportRefusesAPDFThatNoLongerMatches() throws {
        let other = try makePDF(pages: 1, marker: "autre")
        XCTAssertThrowsError(try DocumentPackage.write(to: root.appendingPathComponent("x.kyokasho"), documentId: id, title: "T",
                                                       pageCount: 4, appVersion: "test", pdf: other, rows: [:], analysisFolder: nil,
                                                       report: nil, drafts: [:], preferences: [:], dictionaries: []))
    }
}
