// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import CoreGraphics
import ReaderCore
import ReviewKit
import XCTest

final class BackupRoundTripTests: XCTestCase {
    func runTool(_ arguments: [String]) throws {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../tools/backup_container.py").standardizedFileURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, output)
        guard process.terminationStatus == 0 else { throw NSError(domain: "BackupTest", code: 1) }
    }

    func testRestoreRealGRDBStoresAndReopenForWriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kyokasho-restore-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appendingPathComponent("source")
        let support = container.appendingPathComponent("Library/Application Support/Kyokasho")
        let database = try AppDatabase.open(at: support.appendingPathComponent("kyokasho.sqlite"))
        let review = try ReviewStore.open(directory: support.appendingPathComponent("Review"))
        let doc = LibraryDocument(id: "synth", title: "Manuel", originalFileName: "synth.pdf", pageCount: 2, fileSize: 1,
                                  importedAt: Date(timeIntervalSince1970: 1000))
        try database.save(doc)
        var note = PageComment(documentId: doc.id, pageIndex: 1, body: "Note 図", drawing: Data([3, 2, 1]))
        note.anchorRect = .init(x: 10, y: 20, width: 30, height: 40)
        try database.save(note)
        try database.save(Bookmark(documentId: doc.id, pageIndex: 1, title: "Repère"))
        try database.save(Highlight(documentId: doc.id, pageIndex: 0, rects: [], color: .yellow, text: "texte"))
        try database.save(InkDrawing(documentId: doc.id, pageIndex: 1, data: Data([1, 4])), isEmpty: false)
        let ocr = Data("{\"edited\":true,\"text\":\"図\"}".utf8)
        try database.save(OCRResultRecord(documentId: doc.id, pageIndex: 1, engine: "synthetic", json: ocr, durationMs: 1))
        var card = StudyCard(deckId: try XCTUnwrap(review.decks().first?.id), templateId: try XCTUnwrap(review.templates().first?.id),
                             key: "図|ず", fields: ["Expression": "図"], sourceDocumentId: doc.id, sourcePage: 1,
                             now: Date(timeIntervalSince1970: 1000))
        card.stability = 10
        card.difficulty = 5
        card.reps = 7
        card.state = .review
        card = try review.add(card)
        try review.record(card, log: ReviewEntry(cardId: card.id!, grade: .good, state: .review,
            reviewedAt: Date(timeIntervalSince1970: 2000), elapsedDays: 1, scheduledDays: 3, stability: 10, difficulty: 5, duration: 2))
        let logs = try review.history(cardId: card.id!)
        let media = try review.addMedia(Data([1, 2, 8]), extension: "png")
        let pdf = support.appendingPathComponent("Documents/synth.pdf")
        try FileManager.default.createDirectory(at: pdf.deletingLastPathComponent(), withIntermediateDirectories: true)
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let context = try XCTUnwrap(CGContext(pdf as CFURL, mediaBox: &box, nil))
        for _ in 0..<2 { context.beginPDFPage(nil); context.fill(box); context.endPDFPage() }
        context.closePDF()
        let bytes = try Data(contentsOf: pdf)
        let additional = ["Library/Application Support/Analysis/synth/ovisocr2-1.md": "図 brut",
                          "Library/Application Support/Analysis/synth.json": "{}",
                          "Library/Application Support/Kyokasho/lexique.json": "[]",
                          "Library/Application Support/Kyokasho/Chats/qwen-synth.json": "[]",
                          "Library/Preferences/fr.noxygen59.kyokasho.plist": "préférences synthétiques"]
        for (name, value) in additional {
            let url = container.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(value.utf8).write(to: url)
        }
        // Mettre les vrais pools GRDB au repos et les fermer avant d'attester une copie hors ligne.
        try database.writer.close()
        try review.writer.close()
        let backup = root.appendingPathComponent("backup")
        try runTool(["backup", container.path, backup.path, "--source-stopped"])
        let archive = backup.appendingPathComponent("backup")
        try runTool(["verify", archive.path])
        let target = root.appendingPathComponent("restored")
        try runTool(["restore", archive.path, target.path])
        let restored = target.appendingPathComponent("container")
        let restoredSupport = restored.appendingPathComponent("Library/Application Support/Kyokasho")
        let app = try AppDatabase.open(at: restoredSupport.appendingPathComponent("kyokasho.sqlite"))
        let cards = try ReviewStore.open(directory: restoredSupport.appendingPathComponent("Review"))
        XCTAssertEqual(try app.document(id: doc.id), doc)
        XCTAssertEqual(try app.comments(documentId: doc.id).first?.anchorRect, note.anchorRect)
        XCTAssertEqual(try app.comments(documentId: doc.id).first?.drawing, Data([3, 2, 1]))
        XCTAssertEqual(try app.bookmarks(documentId: doc.id).first?.pageIndex, 1)
        XCTAssertEqual(try app.inkDrawing(documentId: doc.id, pageIndex: 1)?.data, Data([1, 4]))
        XCTAssertEqual(try app.highlights(documentId: doc.id).first?.text, "texte")
        XCTAssertEqual(try app.ocrResult(documentId: doc.id, pageIndex: 1, engine: "synthetic")?.json, ocr)
        XCTAssertEqual(try cards.card(id: card.id!), card)
        XCTAssertEqual(try cards.history(cardId: card.id!), logs)
        XCTAssertEqual(try Data(contentsOf: cards.mediaRoot.appendingPathComponent(media)), Data([1, 2, 8]))
        XCTAssertEqual(try Data(contentsOf: restoredSupport.appendingPathComponent("Documents/synth.pdf")), bytes)
        for (name, value) in additional { XCTAssertEqual(try String(contentsOf: restored.appendingPathComponent(name)), value) }
        try app.save(PageComment(documentId: doc.id, pageIndex: 0, body: "Après restauration"))
        try app.writer.close()
        let reopened = try AppDatabase.open(at: restoredSupport.appendingPathComponent("kyokasho.sqlite"))
        XCTAssertEqual(try reopened.comments(documentId: doc.id).count, 2)
        try reopened.writer.close()
        try cards.writer.close()
    }
}
