// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
@testable import ReaderCore

/// Contre-revue R2 du lot C2 « Drive » (10/11/2026), constats S4 et S5, corrigés par Claude.
final class RekeyReviewS4S5Tests: XCTestCase {
    private func document(_ id: String) -> LibraryDocument {
        LibraryDocument(id: id, title: id, originalFileName: "\(id).pdf", pageCount: 3, fileSize: 1)
    }

    /// S4 : fusion sans moyen de mettre de côté le dessin du survivant → refus, aucun dessin perdu.
    func testMergeWithoutInkAsideIsRefusedAndKeepsBothDrawings() throws {
        let database = try AppDatabase.inMemory()
        try database.save(document("ancien"))
        try database.save(document("survivant"))
        try database.save(InkDrawing(documentId: "ancien", pageIndex: 1, data: Data([1])), isEmpty: false)
        try database.save(InkDrawing(documentId: "survivant", pageIndex: 1, data: Data([2])), isEmpty: false)
        XCTAssertThrowsError(try database.rekeyDocument(from: "ancien", to: document("survivant"))) {
            XCTAssertEqual($0 as? RekeyError, .inkWouldBeLost)
        }
        let drawings = try database.writer.read { db in try InkDrawing.fetchAll(db) }
        XCTAssertEqual(Set(drawings.map(\.data)), [Data([1]), Data([2])])
        XCTAssertNotNil(try database.document(id: "ancien"), "transaction annulée : rien n'a bougé")
    }

    /// S5 : la même mise de côté rejouée (transaction annulée puis refaite) n'écrit qu'un fichier.
    func testSameCorrectionsKeptTwiceMakeOneFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aside-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = CorrectionAsideStore(root: root)
        let entries = [KeptCorrection(original: "建貝", corrected: "建具")]
        try store.keep(pageIndex: 2, engine: "vision", entries: entries, documentId: "nouveau", sourceDocumentId: "ancien")
        try store.keep(pageIndex: 2, engine: "vision", entries: entries, documentId: "nouveau", sourceDocumentId: "ancien")
        try store.keep(pageIndex: 2, engine: "vision", entries: [KeptCorrection(original: "a", corrected: "b")],
                       documentId: "nouveau", sourceDocumentId: "ancien")
        let files = try FileManager.default.contentsOfDirectory(at: store.folder(documentId: "nouveau"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertEqual(files.count, 2, "même contenu = même fichier ; contenu différent = autre fichier")
        XCTAssertEqual(store.pendingCorrections(documentId: "nouveau", pageIndex: 2, engine: "vision").count, 2)
    }

    /// Analyse avant candidate 1.5.5 (DeepSeek #1) : en fusion, la version qui reste est le même fichier ; son OCR et
    /// son rognage automatique restent (rien à relire).
    func testMergeKeepsTheSurvivorOCR() throws {
        let database = try AppDatabase.inMemory()
        try database.save(document("ancien"))
        try database.save(document("survivant"))
        try database.save(OCRResultRecord(documentId: "survivant", pageIndex: 0, engine: "vision", json: Data("{}".utf8), durationMs: 1))
        try database.rekeyDocument(from: "ancien", to: document("survivant"), asideInk: { _, _, _ in })
        XCTAssertNotNil(try database.ocrResult(documentId: "survivant", pageIndex: 0, engine: "vision"))
        XCTAssertNil(try database.document(id: "ancien"))
    }
}
