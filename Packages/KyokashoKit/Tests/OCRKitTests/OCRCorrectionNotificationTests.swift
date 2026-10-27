// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import XCTest
import ReaderCore
@testable import OCRKit

final class OCRCorrectionNotificationTests: XCTestCase {
    func testSuccessfulStoreNotifiesAfterPersistenceWithExactScope() async throws {
        let db = try AppDatabase.inMemory()
        let id = UUID().uuidString
        try db.save(LibraryDocument(id: id, title: "Synthétique", originalFileName: "test.pdf", pageCount: 2, fileSize: 1))
        let service = OCRService(database: db)
        let page = OCRPage(engine: OCREngineID.vision, lines: [], durationMs: 0)
        let updated = expectation(description: "lecteur averti après écriture")
        let observer = NotificationCenter.default.addObserver(forName: Notification.Name("kyokasho.ocrCacheUpdated"), object: nil, queue: nil) { note in
            guard note.userInfo?["documentId"] as? String == id else { return }
            XCTAssertEqual(note.userInfo?["pageIndex"] as? Int, 1)
            XCTAssertEqual(note.userInfo?["engine"] as? String, page.engine)
            XCTAssertEqual(try? db.ocrEngines(documentId: id, pageIndex: 1), [page.engine])
            updated.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        try await service.store(page, documentId: id, pageIndex: 1)
        await fulfillment(of: [updated], timeout: 1)
    }

    func testAcceptedLineSurvivesReopeningAndReproofreadingWithResidualDoubts() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("synthetic.sqlite")
        let id = UUID().uuidString
        var accepted = OCRLine(text: "末来", box: NormBox(x: 0, y: 0, w: 1, h: 0.1), charBoxes: [],
                               measuredCharBoxes: false, vertical: false, confidence: 0.2)
        accepted.doubt = [0, 1]
        // Même opération que les choix de l'analyse, y compris conserver le texte sans le modifier.
        accepted = accepted.acceptingCorrection(accepted.text)
        XCTAssertEqual(accepted.edited, true)
        XCTAssertEqual(accepted.doubt, [])
        var residual = accepted
        residual.edited = nil
        residual.doubt = [0]
        let page = OCRPage(engine: OCREngineID.vision, lines: [accepted, residual], durationMs: 0)
        do {
            let db = try AppDatabase.open(at: url)
            try db.save(LibraryDocument(id: id, title: "Synthétique", originalFileName: "test.pdf", pageCount: 1, fileSize: 1))
            try await OCRService(database: db).store(page, documentId: id, pageIndex: 0)
        }
        let reopened = OCRService(database: try AppDatabase.open(at: url))
        let read = await reopened.cached(documentId: id, pageIndex: 0, engine: page.engine)
        let cached = try XCTUnwrap(read)
        XCTAssertEqual(cached, page)
        let refined = await OCRProofreader.proofread(cached) { text in [(text.count, false)] }
        let compared = OCRReferenceDiff.markDifferences(refined, reference: "未来未来")
        XCTAssertEqual(compared.lines[0], accepted)
        XCTAssertEqual(OCRProofreader.doubtful(compared), [1], "seule la ligne non acceptée reste à revoir")
        XCTAssertFalse(OCRReferenceDiff.suggestions(compared, reference: "未来未来").contains { $0.line == 0 })
        let other = await reopened.cached(documentId: UUID().uuidString, pageIndex: 0, engine: page.engine)
        XCTAssertNil(other, "aucune correction propagée à un autre document")
    }

    func testChangedCorrectionUpdatesGeometryAndProtectsChosenText() {
        let box = NormBox(x: 0, y: 0, w: 1, h: 0.1)
        var original = OCRLine(text: "未来", box: box, charBoxes: CharacterLayout.proportional("未来", in: box, vertical: false),
                               measuredCharBoxes: true, vertical: false, confidence: 0.3)
        original.doubt = [0]
        let sameLength = original.acceptingCorrection("末来")
        XCTAssertEqual(sameLength.charBoxes, original.charBoxes)
        XCTAssertTrue(sameLength.measuredCharBoxes)
        let longer = original.acceptingCorrection("未来の土地")
        XCTAssertEqual(longer.charBoxes.count, longer.text.count)
        XCTAssertFalse(longer.measuredCharBoxes)
        XCTAssertEqual(longer.edited, true)
        XCTAssertEqual(longer.doubt, [])
    }

    func testFailedStoreDoesNotNotify() async throws {
        let service = OCRService(database: try AppDatabase.inMemory())
        let missing = UUID().uuidString
        let updated = expectation(description: "aucun faux succès")
        updated.isInverted = true
        let observer = NotificationCenter.default.addObserver(forName: Notification.Name("kyokasho.ocrCacheUpdated"), object: nil, queue: nil) { note in
            if note.userInfo?["documentId"] as? String == missing { updated.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        do {
            try await service.store(OCRPage(engine: "test", lines: [], durationMs: 0), documentId: missing, pageIndex: 0)
            XCTFail("document inexistant : l'écriture doit échouer")
        } catch {}
        await fulfillment(of: [updated], timeout: 0.1)
    }
}
