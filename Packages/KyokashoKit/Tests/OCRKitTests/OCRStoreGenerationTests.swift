// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore
import XCTest
@testable import OCRKit

/// Étape 2 de la reconstruction de l'OCR : une écriture commencée avant un ajout ou une suppression de pages ne doit pas
/// tomber, après la fin de ce changement, sur une page qui en a pris l'index (revue Codex de d87e048, §2).
final class OCRStoreGenerationTests: XCTestCase {
    private func fixture() throws -> (AppDatabase, OCRService, String) {
        let db = try AppDatabase.inMemory()
        let id = UUID().uuidString
        try db.save(LibraryDocument(id: id, title: "Synthétique", originalFileName: "test.pdf", pageCount: 3, fileSize: 1))
        return (db, OCRService(database: db), id)
    }

    private let page = OCRPage(engine: OCREngineID.vision, lines: [], durationMs: 0)

    func testStoreStartedBeforeAPageMutationIsRefusedAfterIt() async throws {
        let (db, service, id) = try fixture()
        let generation = await service.generation(documentId: id)
        await service.beginPageMutation(documentId: id)
        await service.endPageMutation(documentId: id)
        do {
            try await service.store(page, documentId: id, pageIndex: 1, expectedGeneration: generation)
            XCTFail("écriture d'avant le changement de pages acceptée")
        } catch is CancellationError {}
        XCTAssertNil(try db.ocrResult(documentId: id, pageIndex: 1, engine: page.engine))
    }

    func testStoreWithoutMutationStillWritesAndNotifies() async throws {
        let (db, service, id) = try fixture()
        let notified = expectation(description: "notification")
        let observer = NotificationCenter.default.addObserver(forName: OCRService.cacheUpdated, object: nil, queue: nil) { note in
            if note.userInfo?["documentId"] as? String == id { notified.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let generation = await service.generation(documentId: id)
        try await service.store(page, documentId: id, pageIndex: 1, expectedGeneration: generation)
        await fulfillment(of: [notified], timeout: 1)
        XCTAssertNotNil(try db.ocrResult(documentId: id, pageIndex: 1, engine: page.engine))
    }

    func testStoreWithoutExpectedGenerationKeepsTheOldContract() async throws {
        let (db, service, id) = try fixture()
        await service.beginPageMutation(documentId: id)
        await service.endPageMutation(documentId: id)
        try await service.store(page, documentId: id, pageIndex: 2)
        XCTAssertNotNil(try db.ocrResult(documentId: id, pageIndex: 2, engine: page.engine))
    }
}
