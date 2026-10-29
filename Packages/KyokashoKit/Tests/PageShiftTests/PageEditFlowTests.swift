// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import PDFKit
import OCRKit
import ReaderCore
import ReviewKit
import XCTest

/// Suppression et restauration de pages (#49, S2/S3) de bout en bout, sur le fichier produit `PageShift.swift` et un
/// conteneur synthétique : base, PDF, lectures IA, rapport, brouillons, cartes ; pannes à chaque étape ; purge.
extension PageShiftRecoveryTests {
    /// Résumé lisible de tout ce qui dépend des pages du document de test.
    func pageState(_ model: AppModel, _ doc: LibraryDocument, _ card: StudyCard) throws -> [String] {
        let folder = DocumentAnalysisService.folder.appendingPathComponent(doc.id)
        let report = try? JSONDecoder().decode(DocumentAnalysis.self,
            from: Data(contentsOf: DocumentAnalysisService.folder.appendingPathComponent(doc.id + ".json")))
        return [
            "pdf \(PDFDocument(url: model.storage.url(for: doc.id))?.pageCount ?? -1)",
            "base \(try model.database.document(id: doc.id)?.pageCount ?? -1)",
            "surlignages \(try model.database.highlights(documentId: doc.id).map(\.pageIndex))",
            "notes \(try model.database.comments(documentId: doc.id).map { "\($0.pageIndex):\($0.body)" })",
            "encre \(try [0, 1, 2, 3].filter { try model.database.inkDrawing(documentId: doc.id, pageIndex: $0) != nil })",
            "repères \(try model.database.bookmarks(documentId: doc.id).map(\.pageIndex))",
            "rotations \(try model.database.pageTransforms(documentId: doc.id).filter { $0.value.rotation != 0 }.keys.sorted())",
            "ocr \(try [0, 1, 2, 3].filter { try model.database.ocrResult(documentId: doc.id, pageIndex: $0, engine: "test") != nil })",
            "fichiers \(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted())",
            "rapport \((report?.pages ?? [:]).map { "\($0.key)=\($0.value.source)" }.sorted())",
            "brouillons \(NoteDraftStore.shared.drafts(documentId: doc.id).sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" })",
            "carte \(String(describing: try model.review.store.card(id: card.id!)?.sourcePage))",
            "fsrs \(try model.review.store.card(id: card.id!)?.reps ?? -1)/\(try model.review.store.history(cardId: card.id!).count)",
            "autre \(try model.database.bookmarks(documentId: "other").map(\.pageIndex))",
        ]
    }

    func archiveId(_ model: AppModel, _ doc: LibraryDocument) throws -> String {
        try XCTUnwrap(model.database.pageEdits(documentId: doc.id).last { $0.kind == .removal }?.id)
    }

    func testRemoveThenRestoreGivesEverythingBack() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let before = try pageState(model, doc, card)
            try await PageShift.removePages(model, document: doc, pages: [0])
            XCTAssertNil(model.storageRecoveryError)
            XCTAssertEqual(try pageState(model, doc, card), [
                "pdf 1", "base 1", "surlignages []", "notes [\"0:Note\"]", "encre [0]", "repères []", "rotations [0]",
                "ocr []", "fichiers [\"ovisocr2-0.md\"]", "rapport [\"0=0\"]", "brouillons [\"0:brouillon 1\"]",
                "carte nil", "fsrs 9/1", "autre [0]"])
            let removed = try XCTUnwrap(model.database.document(id: doc.id))
            try await PageShift.restorePages(model, document: removed, archiveId: try archiveId(model, doc))
            XCTAssertNil(model.storageRecoveryError)
            XCTAssertEqual(try pageState(model, doc, card), before)
            XCTAssertEqual(try String(contentsOf: DocumentAnalysisService.folder.appendingPathComponent(doc.id + "/fr-0.md")), "traduction 0")
        }
    }

    func testRemovalAndRestorationSurviveAPowerCutAtEveryStep() async throws {
        for point in Self.boundaries {
            try await withFixture { model, doc, root in
                let card = try seed(model, doc)
                let before = try pageState(model, doc, card)
                PageShift.checkpoint = { if $0 == point { throw PowerLoss.simulated } }
                await assertThrowsAsync({ try await PageShift.removePages(model, document: doc, pages: [0]) }, point)
                PageShift.checkpoint = nil
                let restarted = try AppModel(root: root)
                for _ in 0..<2 { PageShift.reconcile(restarted) }
                XCTAssertNil(restarted.storageRecoveryError, point)
                XCTAssertEqual(try pageState(restarted, doc, card)[0...3], ["pdf 1", "base 1", "surlignages []", "notes [\"0:Note\"]"], point)
                XCTAssertEqual(try pageState(restarted, doc, card)[11], "carte nil", point)

                let removed = try XCTUnwrap(restarted.database.document(id: doc.id))
                let archive = try archiveId(restarted, doc)
                PageShift.checkpoint = { if $0 == point { throw PowerLoss.simulated } }
                await assertThrowsAsync({ try await PageShift.restorePages(restarted, document: removed, archiveId: archive) }, point)
                PageShift.checkpoint = nil
                let again = try AppModel(root: root)
                for _ in 0..<2 { PageShift.reconcile(again) }
                XCTAssertNil(again.storageRecoveryError, point)
                XCTAssertEqual(try pageState(again, doc, card), before, point)
            }
        }
    }

    func testOpenDocumentAndConcurrentEditsAreRefused() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            model.openDocumentId = doc.id
            await assertThrowsAsync({ try await PageShift.removePages(model, document: doc, pages: [0]) })
            model.openDocumentId = nil
            await assertThrowsAsync({ try await PageShift.removePages(model, document: doc, pages: [0, 1]) }, "toutes les pages")
            XCTAssertEqual(try model.database.document(id: doc.id)?.pageCount, 2)
            XCTAssertFalse(PageShift.isBusy(doc.id))
        }
    }

    func testPurgeAfterThirtyDaysMakesRestorationImpossible() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            try await PageShift.removePages(model, document: doc, pages: [1])
            let archive = try archiveId(model, doc)
            XCTAssertGreaterThan(PageShift.copiesSize(documentId: doc.id), 0)
            PageShift.purgeExpired(model, now: Date().addingTimeInterval(29 * 24 * 3600))
            XCTAssertNoThrow(try model.database.restorationPlan(documentId: doc.id, archiveId: archive), "pas encore échue")
            // Panne entre la base et le dossier : la purge suivante termine.
            PageShift.checkpoint = { if $0 == "purge.database" { throw PowerLoss.simulated } }
            PageShift.purgeExpired(model, now: Date().addingTimeInterval(31 * 24 * 3600))
            PageShift.checkpoint = nil
            XCTAssertGreaterThan(PageShift.copiesSize(documentId: doc.id), 0)
            PageShift.purgeExpired(model, now: Date().addingTimeInterval(31 * 24 * 3600))
            XCTAssertEqual(PageShift.copiesSize(documentId: doc.id), 0)
            XCTAssertNotNil(try model.database.pageEdit(id: archive)?.purgedAt)
            XCTAssertTrue(try model.database.archivedRows(editId: archive).isEmpty)
            let current = try XCTUnwrap(model.database.document(id: doc.id))
            await assertThrowsAsync({ try await PageShift.restorePages(model, document: current, archiveId: archive) })
            XCTAssertEqual(try pageState(model, doc, card)[1], "base 1")
        }
    }

    func testDeletingTheDocumentRemovesItsCopies() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            try await PageShift.removePages(model, document: doc, pages: [1])
            XCTAssertGreaterThan(PageShift.copiesSize(documentId: doc.id), 0)
            PageShift.removeCopies(documentId: doc.id)
            XCTAssertEqual(PageShift.copiesSize(documentId: doc.id), 0)
        }
    }
}
