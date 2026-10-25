// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import CoreGraphics
import PDFKit
import OCRKit
import ReaderCore
import ReviewKit
import XCTest
import Darwin

@MainActor
final class PageShiftRecoveryTests: XCTestCase {
    func assertThrowsAsync<T>(_ operation: () async throws -> T, _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail(message, file: file, line: line) }
        catch { }
    }

    func withFixture(_ test: (AppModel, LibraryDocument, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("page-shift-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let saved = PageShift.support
        PageShift.support = root
        DocumentAnalysisService.folder = root.appendingPathComponent("Analysis")
        defer {
            PageShift.checkpoint = nil
            PageShift.support = saved
            try? FileManager.default.removeItem(at: root)
        }
        let model = try AppModel(root: root)
        let doc = LibraryDocument(id: "test-document", title: "Synthétique", originalFileName: "test.pdf", pageCount: 2, fileSize: 1)
        try model.database.save(doc)
        try FileManager.default.createDirectory(at: model.storage.root, withIntermediateDirectories: true)
        try writePDF(model.storage.url(for: doc.id), pages: 4)
        try FileManager.default.createDirectory(at: DocumentAnalysisService.folder.appendingPathComponent(doc.id), withIntermediateDirectories: true)
        try await test(model, doc, root)
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
        try await withFixture { model, _, root in
            try marker(root, stage: "cards")
            PageShift.reconcile(model)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("page-shift.json").path),
                          "Un ancien journal ambigu doit rester disponible pour réparation.")
            XCTAssertNotNil(model.storageRecoveryError)
        }
    }

    func testLegacyReportStageDoesNotSilentlyAcceptUnshiftedReport() async throws {
        try await withFixture { model, doc, root in
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
        try await withFixture { model, doc, root in
            let folder = DocumentAnalysisService.folder.appendingPathComponent(doc.id)
            let original = folder.appendingPathComponent("ovisocr2-2.md")
            try Data("page originale 0".utf8).write(to: original)
            try marker(root, stage: "files")
            PageShift.reconcile(model)
            XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "Une reprise ne doit pas ajouter encore 2 aux noms déjà décalés.")
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("ovisocr2-4.md").path))
        }
    }

    enum PowerLoss: Error { case simulated }

    @discardableResult
    func seed(_ model: AppModel, _ doc: LibraryDocument) throws -> StudyCard {
        try writePDF(model.storage.url(for: doc.id), pages: 2)
        try model.database.save(Highlight(documentId: doc.id, pageIndex: 0, rects: [.init(x: 2, y: 3, width: 4, height: 5)], color: .yellow, text: "図"))
        var note = PageComment(documentId: doc.id, pageIndex: 1, body: "Note", drawing: Data([7, 8]))
        note.anchorRect = .init(x: 10, y: 20, width: 30, height: 40)
        try model.database.save(note)
        try model.database.save(InkDrawing(documentId: doc.id, pageIndex: 1, data: Data([1, 2, 3])), isEmpty: false)
        try model.database.save(Bookmark(documentId: doc.id, pageIndex: 0, title: "Repère"))
        try model.database.save(PageTransform(documentId: doc.id, pageIndex: 1, rotation: 90))
        let payload = Data("OCR retouché".utf8)
        try model.database.save(OCRResultRecord(documentId: doc.id, pageIndex: 0, engine: "test", json: payload, durationMs: 1))
        let folder = DocumentAnalysisService.folder.appendingPathComponent(doc.id)
        try Data("page 0".utf8).write(to: folder.appendingPathComponent("ovisocr2-0.md"))
        try Data("page 1".utf8).write(to: folder.appendingPathComponent("ovisocr2-1.md"))
        try Data("traduction 0".utf8).write(to: folder.appendingPathComponent("fr-0.md"))
        var report = DocumentAnalysis(documentId: doc.id)
        report.pages[0] = .init(source: 0, baseEngine: "test")
        report.pages[1] = .init(source: 1, baseEngine: "test")
        try JSONEncoder().encode(report).write(to: DocumentAnalysisService.folder.appendingPathComponent(doc.id + ".json"))
        var card = StudyCard(deckId: try XCTUnwrap(model.review.store.decks().first?.id),
                             templateId: try XCTUnwrap(model.review.store.templates().first?.id),
                             key: "図|ず", fields: ["Expression": "図"], sourceDocumentId: doc.id, sourcePage: 0, now: Date(timeIntervalSince1970: 1000))
        card.stability = 12.25
        card.difficulty = 4.5
        card.reps = 9
        card.lapses = 2
        card.state = .review
        card = try model.review.store.add(card)
        try model.review.store.record(card, log: ReviewEntry(cardId: card.id!, grade: .good, state: .review,
            reviewedAt: Date(timeIntervalSince1970: 123), elapsedDays: 1, scheduledDays: 3, stability: 12.25, difficulty: 4.5, duration: 2))
        // Données d'un second livre : elles ne doivent jamais bouger.
        try model.database.save(LibraryDocument(id: "other", title: "Autre", originalFileName: "o.pdf", pageCount: 2, fileSize: 1))
        try model.database.save(Bookmark(documentId: "other", pageIndex: 0, title: "Intact"))
        return card
    }

    func verify(_ model: AppModel, _ doc: LibraryDocument, _ card: StudyCard, offset: Int = 2) throws {
        XCTAssertEqual(PDFDocument(url: model.storage.url(for: doc.id))?.pageCount, 4)
        XCTAssertEqual(try model.database.document(id: doc.id)?.pageCount, 4)
        XCTAssertEqual(try model.database.document(id: doc.id)?.firstPageIndex, offset)
        XCTAssertEqual(try model.database.highlights(documentId: doc.id).first?.pageIndex, offset)
        XCTAssertEqual(try model.database.highlights(documentId: doc.id).first?.rects.first?.x, 2)
        XCTAssertEqual(try model.database.comments(documentId: doc.id).first?.pageIndex, 1 + offset)
        XCTAssertEqual(try model.database.comments(documentId: doc.id).first?.anchorRect?.x, 10)
        XCTAssertEqual(try model.database.comments(documentId: doc.id).first?.drawing, Data([7, 8]))
        XCTAssertEqual(try model.database.inkDrawing(documentId: doc.id, pageIndex: 1 + offset)?.data, Data([1, 2, 3]))
        XCTAssertEqual(try model.database.bookmarks(documentId: doc.id).first?.pageIndex, offset)
        XCTAssertEqual(try model.database.pageTransforms(documentId: doc.id)[1 + offset]?.rotation, 90)
        XCTAssertEqual(try model.database.ocrResult(documentId: doc.id, pageIndex: offset, engine: "test")?.json, Data("OCR retouché".utf8))
        let folder = DocumentAnalysisService.folder.appendingPathComponent(doc.id)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("ovisocr2-\(offset).md")), "page 0")
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("ovisocr2-\(1 + offset).md")), "page 1")
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("fr-\(offset).md")), "traduction 0")
        let report = try JSONDecoder().decode(DocumentAnalysis.self,
            from: Data(contentsOf: DocumentAnalysisService.folder.appendingPathComponent(doc.id + ".json")))
        XCTAssertEqual(Set(report.pages.keys), Set([offset, 1 + offset]))
        XCTAssertEqual(report.pages[offset]?.source, offset)
        var expectedCard = card
        expectedCard.sourcePage = offset
        XCTAssertEqual(try model.review.store.card(id: card.id!), expectedCard)
        XCTAssertEqual(try model.review.store.history(cardId: card.id!).count, 1)
        XCTAssertEqual(try model.database.bookmarks(documentId: "other").first?.pageIndex, 0)
    }

    func testInterruptionsAtEveryCommitBoundaryAndRepeatedReopens() async throws {
        let points = ["journal.after", "database.before", "database.after", "pdf.before", "pdf.after",
                      "report.before", "report.after", "files.backup", "files.installed", "cards.before", "cards.after", "complete.before"]
        for point in points {
            try await withFixture { model, doc, root in
                let card = try seed(model, doc)
                let merged = root.appendingPathComponent("input.pdf")
                try writePDF(merged, pages: 4)
                PageShift.checkpoint = { if $0 == point { throw PowerLoss.simulated } }
                await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4 ) }, point)
                XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("page-shift.json").path), point)
                // Première reprise interrompue au même point, puis nouvelle instance de bases.
                let restarted = try AppModel(root: root)
                if point == "journal.after" {
                    PageShift.checkpoint = { if $0 == "database.after" { throw PowerLoss.simulated } }
                }
                PageShift.reconcile(restarted)
                XCTAssertNotNil(restarted.storageRecoveryError, point)
                PageShift.checkpoint = nil
                PageShift.reconcile(restarted)
                XCTAssertNil(restarted.storageRecoveryError, point)
                for _ in 0..<3 { PageShift.reconcile(restarted) }
                try verify(restarted, doc, card)
            }
        }
    }

    func testInitialJournalWriteFailureLeavesAllOriginalsUnchanged() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let beforePDF = try DocumentImporter.sha256(of: model.storage.url(for: doc.id))
            let merged = root.appendingPathComponent("input.pdf")
            try writePDF(merged, pages: 4)
            PageShift.checkpoint = { if $0 == "journal.before" { throw PowerLoss.simulated } }
            await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4 ) })
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("page-shift.json").path))
            XCTAssertEqual(try DocumentImporter.sha256(of: model.storage.url(for: doc.id)), beforePDF)
            XCTAssertEqual(try model.database.document(id: doc.id)?.pageCount, 2)
            XCTAssertEqual(try model.database.bookmarks(documentId: doc.id).first?.pageIndex, 0)
            XCTAssertEqual(try model.review.store.card(id: card.id!), card)
        }
    }

    func testAppendWithoutOffsetPreservesAllSourcePages() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let merged = root.appendingPathComponent("input.pdf")
            try writePDF(merged, pages: 4)
            _ = try await PageShift.apply(model, document: doc, merged: merged, offset: 0, newCount: 4)
            try verify(model, doc, card, offset: 0)
        }
    }

    func testCorruptJournalIsPreservedAndBlocksFurtherModification() async throws {
        try await withFixture { model, doc, root in
            let file = root.appendingPathComponent("page-shift.json")
            try Data("{truncated".utf8).write(to: file)
            PageShift.reconcile(model)
            XCTAssertNotNil(model.storageRecoveryError)
            XCTAssertEqual(try String(contentsOf: file), "{truncated")
            await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: root, offset: 2, newCount: 4 ) })
        }
    }

    func testMissingPreparedPDFRetainsJournalAndDoesNotApplyDatabaseTwice() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            let merged = root.appendingPathComponent("input.pdf")
            try writePDF(merged, pages: 4)
            PageShift.checkpoint = { if $0 == "database.after" { throw PowerLoss.simulated } }
            await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4 ) })
            PageShift.checkpoint = nil
            let pending = try JSONDecoder().decode(PageShift.Pending.self, from: Data(contentsOf: root.appendingPathComponent("page-shift.json")))
            try FileManager.default.removeItem(at: root.appendingPathComponent("PageShift/\(pending.transaction!)/merged.pdf"))
            for _ in 0..<3 { PageShift.reconcile(model) }
            XCTAssertNotNil(model.storageRecoveryError)
            XCTAssertEqual(try model.database.bookmarks(documentId: doc.id).first?.pageIndex, 2)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("page-shift.json").path))
        }
    }


    func testSQLiteCardWriteFailureCanBeRetriedWithoutChangingFSRS() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            try await model.review.store.writer.write { db in
                try db.execute(sql: "CREATE TRIGGER fail_shift BEFORE UPDATE OF sourcePage ON card BEGIN SELECT RAISE(ABORT, 'disque simulé'); END")
            }
            let merged = root.appendingPathComponent("input.pdf")
            try writePDF(merged, pages: 4)
            await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4 ) })
            XCTAssertNotNil(model.storageRecoveryError)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("page-shift.json").path))
            XCTAssertEqual(try model.review.store.card(id: card.id!), card)
            try await model.review.store.writer.write { try $0.execute(sql: "DROP TRIGGER fail_shift") }
            for _ in 0..<3 { PageShift.reconcile(model) }
            XCTAssertNil(model.storageRecoveryError)
            try verify(model, doc, card)
        }
    }

    func testSQLiteFailureRollsBackEveryAnnotationTableBeforeRetry() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            try await model.database.writer.write { db in
                try db.execute(sql: "CREATE TRIGGER fail_shift BEFORE UPDATE ON inkDrawing BEGIN SELECT RAISE(ABORT, 'disque simulé'); END")
            }
            let merged = root.appendingPathComponent("input.pdf")
            try writePDF(merged, pages: 4)
            await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4 ) })
            XCTAssertEqual(try model.database.highlights(documentId: doc.id).first?.pageIndex, 0)
            XCTAssertEqual(try model.database.document(id: doc.id)?.pageCount, 2)
            XCTAssertEqual(PDFDocument(url: model.storage.url(for: doc.id))?.pageCount, 2)
            try await model.database.writer.write { try $0.execute(sql: "DROP TRIGGER fail_shift") }
            PageShift.reconcile(model)
            try verify(model, doc, card)
        }
    }

    func testPersistentStorageFallbackCannotCommitOrDiscardJournal() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            let merged = root.appendingPathComponent("input.pdf")
            try writePDF(merged, pages: 4)
            model.review.persistentStorageAvailable = false
            await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4 ) })
            XCTAssertEqual(try model.database.document(id: doc.id)?.pageCount, 2)
            try marker(root, stage: "db")
            PageShift.reconcile(model)
            XCTAssertNotNil(model.storageRecoveryError)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("page-shift.json").path))
        }
    }

    func testLegacyRollbackWithOldPDFIsSafeAndIdempotent() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            try model.database.shiftPages(documentId: doc.id, by: 2, pageCount: 4, fileSize: 9)
            try marker(root, stage: "pdf")
            for _ in 0..<3 { PageShift.reconcile(model) }
            XCTAssertNil(model.storageRecoveryError)
            XCTAssertEqual(try model.database.document(id: doc.id)?.pageCount, 2)
            XCTAssertEqual(try model.database.bookmarks(documentId: doc.id).first?.pageIndex, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("page-shift.json").path))
        }
    }


    func testFilesystemReportWriteErrorPreservesIntentUntilStorageIsWritable() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let report = DocumentAnalysisService.folder.appendingPathComponent(doc.id + ".json")
            let merged = root.appendingPathComponent("input.pdf")
            try writePDF(merged, pages: 4)
            PageShift.checkpoint = { point in
                if point == "report.before" {
                    try FileManager.default.moveItem(at: report, to: root.appendingPathComponent("report-saved.json"))
                    try FileManager.default.createDirectory(at: report, withIntermediateDirectories: true)
                }
            }
            await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4 ) })
            PageShift.checkpoint = nil
            for _ in 0..<3 { PageShift.reconcile(model) }
            XCTAssertNotNil(model.storageRecoveryError)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("page-shift.json").path))
            try FileManager.default.removeItem(at: report)
            PageShift.reconcile(model)
            try verify(model, doc, card)
        }
    }

    func testIncompleteMergeNeverChangesSourcePDFOrAnnotations() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let pdf = model.storage.url(for: doc.id)
            let original = try DocumentImporter.sha256(of: pdf)
            let merged = root.appendingPathComponent("incomplete.pdf")
            try writePDF(merged, pages: 3)
            await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4 ) })
            XCTAssertEqual(try DocumentImporter.sha256(of: pdf), original)
            XCTAssertEqual(try model.database.bookmarks(documentId: doc.id).first?.pageIndex, 0)
            XCTAssertEqual(try model.review.store.card(id: card.id!), card)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("page-shift.json").path))
        }
    }


    func testAbruptProcessDeathAfterCommittedEffects() async throws {
        let environment = ProcessInfo.processInfo.environment
        if let rootPath = environment["KYOKASHO_CRASH_ROOT"], let point = environment["KYOKASHO_CRASH_POINT"] {
            let root = URL(fileURLWithPath: rootPath)
            PageShift.support = root
            DocumentAnalysisService.folder = root.appendingPathComponent("Analysis")
            let model = try AppModel(root: root)
            let document = try XCTUnwrap(model.database.document(id: "test-document"))
            PageShift.checkpoint = { if $0 == point { Darwin.kill(Darwin.getpid(), SIGKILL) } }
            _ = try await PageShift.apply(model, document: document, merged: root.appendingPathComponent("input.pdf"), offset: 2, newCount: 4)
            XCTFail("Le processus aurait dû être tué au point demandé.")
            return
        }
        let lookup = Process()
        lookup.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        lookup.arguments = ["--find", "xctest"]
        let location = Pipe()
        lookup.standardOutput = location
        try lookup.run()
        lookup.waitUntilExit()
        let executable = String(decoding: location.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for point in ["database.after", "pdf.after", "files.backup", "cards.after"] {
            try await withFixture { model, doc, root in
                let card = try seed(model, doc)
                try writePDF(root.appendingPathComponent("input.pdf"), pages: 4)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = ["-XCTest", "PageShiftTests.PageShiftRecoveryTests/testAbruptProcessDeathAfterCommittedEffects",
                                     Bundle(for: Self.self).bundleURL.path]
                var env = environment
                env["KYOKASHO_CRASH_ROOT"] = root.path
                env["KYOKASHO_CRASH_POINT"] = point
                let sanitizer = Bundle(for: Self.self).bundleURL
                    .appendingPathComponent("Contents/Frameworks/libclang_rt.asan_osx_dynamic.dylib")
                if FileManager.default.fileExists(atPath: sanitizer.path) {
                    // Le runtime doit précéder le chargement du bundle instrumenté (diagnostic ASan).
                    env["DYLD_INSERT_LIBRARIES"] = sanitizer.path
                }
                process.environment = env
                let output = Pipe()
                process.standardOutput = output
                process.standardError = output
                try process.run()
                process.waitUntilExit()
                let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                XCTAssertEqual(process.terminationReason, .uncaughtSignal, log)
                XCTAssertEqual(process.terminationStatus, SIGKILL, log)
                guard process.terminationReason == .uncaughtSignal, process.terminationStatus == SIGKILL else {
                    throw NSError(domain: "CrashHarness", code: 1, userInfo: [NSLocalizedDescriptionKey: log])
                }
                let restarted = try AppModel(root: root)
                for _ in 0..<3 { PageShift.reconcile(restarted) }
                XCTAssertNil(restarted.storageRecoveryError)
                try verify(restarted, doc, card)
            }
        }
    }

}
