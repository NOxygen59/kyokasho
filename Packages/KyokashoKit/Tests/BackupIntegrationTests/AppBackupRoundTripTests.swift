// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import DictionaryKit
import Foundation
import ReaderCore
import ReviewKit
import XCTest

extension BackupRoundTripTests {
    /// Format réellement proposé dans Réglages : trois bases ouvertes (API SQLite de sauvegarde), fichiers,
    /// extraction vérifiée, installation au lancement puis réouverture en écriture. Aucun conteneur personnel.
    func testAppArchiveRestoresRealStoresAndFilesWithoutOldLibraryData() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("kyokasho-app-backup-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func put(_ data: Data, _ url: URL) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let source = root.appendingPathComponent("source")
        let library = source.appendingPathComponent("Kyokasho")
        let database = try AppDatabase.open(at: library.appendingPathComponent("kyokasho.sqlite"))
        let review = try ReviewStore.open(directory: library.appendingPathComponent("Review"))
        let dictionary = try DictionaryDatabase.open(directory: library.appendingPathComponent("Dictionaries"))
        defer { try? database.writer.close(); try? review.writer.close(); try? dictionary.writer.close() }
        try DictionaryImporter(database: dictionary).importDictionary(at: syntheticDictionary(in: root))
        let doc = LibraryDocument(id: "synth", title: "Manuel 図", originalFileName: "synth.pdf", pageCount: 1,
                                  fileSize: 1, importedAt: Date(timeIntervalSince1970: 1000))
        try database.save(doc)
        var note = PageComment(documentId: doc.id, pageIndex: 0, body: "Note corrigée 図",
                               createdAt: Date(timeIntervalSince1970: 1000), updatedAt: Date(timeIntervalSince1970: 1001),
                               drawing: Data([1, 0, 255]))
        note.anchorRect = .init(x: 10, y: 20, width: 30, height: 40)
        try database.save(note)
        try database.save(Bookmark(documentId: doc.id, pageIndex: 0, title: "Repère"))
        try database.save(Highlight(documentId: doc.id, pageIndex: 0, rects: [], color: .yellow, text: "図"))
        try database.save(InkDrawing(documentId: doc.id, pageIndex: 0, data: Data([7, 8])), isEmpty: false)
        let ocr = Data(#"{"edited":true,"text":"図 corrigé"}"#.utf8)
        try database.save(OCRResultRecord(documentId: doc.id, pageIndex: 0, engine: "synthetic", json: ocr, durationMs: 1))
        var card = StudyCard(deckId: try XCTUnwrap(review.decks().first?.id),
                             templateId: try XCTUnwrap(review.templates().first?.id), key: "図|ず",
                             fields: ["Expression": "図"], sourceDocumentId: doc.id, sourcePage: 0,
                             now: Date(timeIntervalSince1970: 1000))
        card.stability = 10; card.difficulty = 5; card.reps = 7; card.state = .review
        card = try review.add(card)
        try review.record(card, log: ReviewEntry(cardId: card.id!, grade: .good, state: .review,
            reviewedAt: Date(timeIntervalSince1970: 2000), elapsedDays: 1, scheduledDays: 3,
            stability: 10, difficulty: 5, duration: 2))
        let history = try review.history(cardId: card.id!)
        let media = try review.addMedia(Data([4, 5, 6]), extension: "png")
        let pdf = library.appendingPathComponent("Documents/synth.pdf")
        try fm.createDirectory(at: pdf.deletingLastPathComponent(), withIntermediateDirectories: true)
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let context = try XCTUnwrap(CGContext(pdf as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil); context.fill(box); context.endPDFPage(); context.closePDF()
        let pdfBytes = try Data(contentsOf: pdf)
        try NoteDraftStore(folder: library.appendingPathComponent("NoteDrafts"))
            .setDraft("Brouillon 図", documentId: doc.id, page: 0)
        let files = ["Kyokasho/lexique.json": "[]", "Kyokasho/Chats/qwen-synth.json": "[]",
                     "Kyokasho/PageShift/archive/original.pdf": "copie synthétique",
                     "Analysis/synth/ovisocr2-0.md": "図 lecture corrigée",
                     "Analysis/synth.json": "{}",
                     "definition-translations.json": #"{"図":"figure"}"#]
        for (path, text) in files { try put(Data(text.utf8), source.appendingPathComponent(path)) }
        try put(Data([99]), library.appendingPathComponent("Models/source-model/weights.bin"))
        try put(Data("transaction exclue".utf8), library.appendingPathComponent("page-shift.json"))
        let prefs = source.appendingPathComponent("preferences.plist")
        try put(PropertyListSerialization.data(fromPropertyList: ["theme.id": "sepia"], format: .binary, options: 0), prefs)
        let archive = root.appendingPathComponent("complete.kyokasho-sauvegarde")
        // Même sélection que LibraryBackupService.source ; les pools restent ouverts pendant la sauvegarde.
        try LibraryBackup.write(.init(databases: [("kyokasho/kyokasho.sqlite", database.writer),
            ("kyokasho/Review/review.sqlite", review.writer),
            ("kyokasho/Dictionaries/dictionaries.sqlite", dictionary.writer)],
            folders: [("kyokasho", library), ("analysis", source.appendingPathComponent("Analysis"))],
            files: [("support/definition-translations.json", source.appendingPathComponent("definition-translations.json")),
                    ("preferences.plist", prefs)], counts: ["documents": 1, "notes": 1, "cartes": 1],
            models: ["source-model"], excluded: ["kyokasho/Models", "kyokasho/page-shift.json"]),
            to: archive, appVersion: "test")
        // Des modifications postérieures ne doivent pas contaminer la copie déjà créée.
        try database.save(PageComment(documentId: doc.id, pageIndex: 0, body: "Après sauvegarde"))
        let target = root.appendingPathComponent("target")
        try put(Data("ancien PDF".utf8), target.appendingPathComponent("Kyokasho/Documents/old.pdf"))
        try put(Data([42]), target.appendingPathComponent("Kyokasho/Models/local/weights.bin"))
        try put(Data("ancienne lecture".utf8), target.appendingPathComponent("Analysis/old.md"))
        let id = UUID().uuidString
        let manifest = try LibraryBackup.open(archive, into: LibraryRestore.stagingURL(support: target, id: id))
        XCTAssertEqual(manifest.counts, ["documents": 1, "notes": 1, "cartes": 1])
        XCTAssertEqual(manifest.models, ["source-model"])
        XCTAssertFalse(manifest.files.keys.contains { $0.contains("Models/") || $0.hasSuffix("page-shift.json") })
        XCTAssertFalse(manifest.files.keys.contains { $0.hasSuffix("-wal") || $0.hasSuffix("-shm") })
        _ = try LibraryRestore.writeMarker(support: target, id: id, backupName: archive.lastPathComponent)
        var restoredPreferences: [String: Any] = [:]
        try LibraryRestore.apply(support: target, analysis: target.appendingPathComponent("Analysis")) { restoredPreferences = $0 }
        XCTAssertEqual(restoredPreferences["theme.id"] as? String, "sepia")
        XCTAssertNil(try LibraryRestore.pending(support: target))
        let live = target.appendingPathComponent("Kyokasho")
        let app = try AppDatabase.open(at: live.appendingPathComponent("kyokasho.sqlite"))
        let cards = try ReviewStore.open(directory: live.appendingPathComponent("Review"))
        let dict = try DictionaryDatabase.open(directory: live.appendingPathComponent("Dictionaries"))
        defer { try? app.writer.close(); try? cards.writer.close(); try? dict.writer.close() }
        XCTAssertEqual(try app.document(id: doc.id), doc)
        XCTAssertEqual(try app.comments(documentId: doc.id), [note])
        XCTAssertEqual(try app.bookmarks(documentId: doc.id).first?.title, "Repère")
        XCTAssertEqual(try app.highlights(documentId: doc.id).first?.text, "図")
        XCTAssertEqual(try app.inkDrawing(documentId: doc.id, pageIndex: 0)?.data, Data([7, 8]))
        XCTAssertEqual(try app.ocrResult(documentId: doc.id, pageIndex: 0, engine: "synthetic")?.json, ocr)
        XCTAssertEqual(try cards.card(id: card.id!), card)
        XCTAssertEqual(try cards.history(cardId: card.id!), history)
        XCTAssertEqual(try Data(contentsOf: cards.mediaRoot.appendingPathComponent(media)), Data([4, 5, 6]))
        XCTAssertEqual(try dict.terms(matching: ["図"], dictionaryIds: Set(try dict.dictionaries().compactMap(\.id))).count, 1)
        XCTAssertEqual(try Data(contentsOf: live.appendingPathComponent("Documents/synth.pdf")), pdfBytes)
        XCTAssertEqual(NoteDraftStore(folder: live.appendingPathComponent("NoteDrafts")).drafts(documentId: doc.id), [0: "Brouillon 図"])
        for (path, text) in files { XCTAssertEqual(try String(contentsOf: target.appendingPathComponent(path)), text, path) }
        XCTAssertEqual(try Data(contentsOf: live.appendingPathComponent("Models/local/weights.bin")), Data([42]))
        XCTAssertFalse(fm.fileExists(atPath: live.appendingPathComponent("Documents/old.pdf").path))
        XCTAssertFalse(fm.fileExists(atPath: target.appendingPathComponent("Analysis/old.md").path))
        try app.save(PageComment(documentId: doc.id, pageIndex: 0, body: "Écrit après restauration"))
        card.reps += 1
        try cards.update(card)
        try app.writer.close(); try cards.writer.close()
        let reopened = try AppDatabase.open(at: live.appendingPathComponent("kyokasho.sqlite"))
        let reopenedCards = try ReviewStore.open(directory: live.appendingPathComponent("Review"))
        defer { try? reopened.writer.close(); try? reopenedCards.writer.close() }
        XCTAssertEqual(try reopened.comments(documentId: doc.id).count, 2)
        XCTAssertEqual(try reopenedCards.card(id: card.id!)?.reps, 8)
    }
}
