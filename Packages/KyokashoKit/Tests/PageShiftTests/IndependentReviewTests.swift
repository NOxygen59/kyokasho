// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit
import ReaderCore
import XCTest
import PDFKit

private actor ReviewGate {
    var continuation: CheckedContinuation<Void, Never>?
    var started = false
    func wait() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private struct ReviewSlowEngine: OCREngine {
    let id = "independent-review-slow"
    let gate: ReviewGate
    func recognize(_ input: OCRInput) async throws -> OCRPage {
        await gate.wait()
        return OCRPage(engine: id, lines: [], durationMs: 1)
    }
}

extension PageShiftRecoveryTests {
    // Regression specification: an OCR started on the old PDF must not populate the inserted page.
    func testIndependentReviewLateOCRMustNotWriteOldPageIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let savedSupport = PageShift.support
        let savedFolder = DocumentAnalysisService.folder
        defer {
            PageShift.support = savedSupport
            DocumentAnalysisService.folder = savedFolder
            try? FileManager.default.removeItem(at: root)
        }
        PageShift.support = root
        DocumentAnalysisService.folder = root.appendingPathComponent("Analysis")
        let model = try AppModel(root: root)
        let doc = LibraryDocument(id: "late-ocr", title: "Synthetic", originalFileName: "s.pdf", pageCount: 2, fileSize: 1)
        try model.database.save(doc)
        try FileManager.default.createDirectory(at: model.storage.root, withIntermediateDirectories: true)
        try writePDF(model.storage.url(for: doc.id), pages: 2)
        let merged = root.appendingPathComponent("merged.pdf")
        try writePDF(merged, pages: 4)
        let gate = ReviewGate()
        let engine = ReviewSlowEngine(gate: gate)
        OCRService.register(engine)
        let ocr = OCRService(database: model.database)
        let pending = Task {
            try await ocr.page(documentId: doc.id, url: model.storage.url(for: doc.id), pageIndex: 0, engine: engine.id)
        }
        while !(await gate.started) { await Task.yield() }
        // Reader closure cancels its caller; detached recognition can still finish.
        pending.cancel()
        _ = try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4)
        await gate.release()
        _ = try? await pending.value
        XCTAssertNil(try model.database.ocrResult(documentId: doc.id, pageIndex: 0, engine: engine.id),
                     "OCR from the old page 0 was persisted on the newly inserted page 0 after PageShift completed")
    }

    func testOCRRequestsAndManualStoresAreBlockedDuringPageMutation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try AppDatabase.open(at: root.appendingPathComponent("app.sqlite"))
        try database.save(LibraryDocument(id: "one", title: "Synthétique", originalFileName: "one.pdf", pageCount: 3, fileSize: 1))
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = ReviewGate()
        let engine = ReviewSlowEngine(gate: gate)
        OCRService.register(engine)
        let ocr = OCRService(database: database)
        let initial = Task { try await ocr.page(documentId: "one", url: root, pageIndex: 0, engine: engine.id) }
        while !(await gate.started) { await Task.yield() }
        let release = Task {
            // `beginPageMutation` must wait for this non-cooperative engine to finish.
            try? await Task.sleep(nanoseconds: 20_000_000)
            await gate.release()
        }
        await ocr.beginPageMutation(documentId: "one")
        _ = await release.value
        await ocr.endPageMutation(documentId: "one")
        do { _ = try await initial.value; XCTFail("Un résultat de l'ancienne génération a été rendu") }
        catch { }
        XCTAssertNil(try database.ocrResult(documentId: "one", pageIndex: 0, engine: engine.id))
        await ocr.beginPageMutation(documentId: "one")
        await assertThrowsAsync { try await ocr.page(documentId: "one", url: root, pageIndex: 0, engine: engine.id) }
        await assertThrowsAsync { try await ocr.store(OCRPage(engine: engine.id, lines: [], durationMs: 1), documentId: "one", pageIndex: 0) }
        await ocr.endPageMutation(documentId: "one")
        try await ocr.store(OCRPage(engine: engine.id, lines: [], durationMs: 1), documentId: "one", pageIndex: 2)
        XCTAssertNotNil(try database.ocrResult(documentId: "one", pageIndex: 2, engine: engine.id))
    }

    func testPDFPoolWaitDoesNotBlockMainActor() async throws {
        try await withFixture { model, doc, root in
            try writePDF(model.storage.url(for: doc.id), pages: 2)
            let merged = root.appendingPathComponent("merged.pdf")
            try writePDF(merged, pages: 4)
            let held = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let url = model.storage.url(for: doc.id)
            let holder = Task.detached {
                try PDFPool.withDocument(url) { _ in
                    held.signal()
                    _ = release.wait(timeout: .now() + 2)
                }
            }
            _ = await Task.detached { held.wait(timeout: .now() + 2) }.value
            let started = Date()
            let addition = Task { try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4) }
            // This MainActor continuation must run while PDFPool still holds its lock.
            try await Task.sleep(nanoseconds: 100_000_000)
            release.signal()
            XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
            _ = try await addition.value
            try await holder.value
        }
    }

    func testOCRReopensAfterRecoveryAndAfterPreflightError() async throws {
        try await withFixture { model, doc, root in
            let engine = "review-manual"
            let page = OCRPage(engine: engine, lines: [], durationMs: 1)
            let invalid = root.appendingPathComponent("missing.pdf")
            await assertThrowsAsync { try await PageShift.apply(model, document: doc, merged: invalid, offset: 2, newCount: 4) }
            try await model.ocr.store(page, documentId: doc.id, pageIndex: 0)
            let merged = root.appendingPathComponent("merged.pdf")
            try writePDF(model.storage.url(for: doc.id), pages: 2)
            try writePDF(merged, pages: 4)
            PageShift.checkpoint = { if $0 == "database.after" { throw PowerLoss.simulated } }
            await assertThrowsAsync { try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4) }
            await assertThrowsAsync { try await model.ocr.store(page, documentId: doc.id, pageIndex: 0) }
            PageShift.checkpoint = nil
            PageShift.reconcile(model)
            XCTAssertNil(model.storageRecoveryError)
            await model.ocr.endPageMutation(documentId: doc.id) // même action que le bouton de reprise
            try await model.ocr.store(page, documentId: doc.id, pageIndex: 3)
            XCTAssertNotNil(try model.database.ocrResult(documentId: doc.id, pageIndex: 3, engine: engine))
        }
    }

    func testCancelledPageShiftBeforeJournalLeavesOCRUsable() async throws {
        try await withFixture { model, doc, root in
            try writePDF(model.storage.url(for: doc.id), pages: 2)
            let merged = root.appendingPathComponent("merged.pdf")
            try writePDF(merged, pages: 4)
            let gate = ReviewGate()
            let engine = ReviewSlowEngine(gate: gate)
            OCRService.register(engine)
            let old = Task { try await model.ocr.page(documentId: doc.id, url: model.storage.url(for: doc.id), pageIndex: 0, engine: engine.id) }
            while !(await gate.started) { await Task.yield() }
            let adding = Task { try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4) }
            await Task.yield()
            adding.cancel()
            await gate.release()
            do { _ = try await adding.value; XCTFail("L'ajout annulé a réussi") } catch { }
            _ = try? await old.value
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("page-shift.json").path))
            XCTAssertEqual(try model.database.document(id: doc.id)?.pageCount, 2)
            try await model.ocr.store(OCRPage(engine: engine.id, lines: [], durationMs: 1), documentId: doc.id, pageIndex: 0)
        }
    }
}
