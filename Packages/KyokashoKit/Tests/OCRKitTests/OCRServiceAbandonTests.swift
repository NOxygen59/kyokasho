// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore
import XCTest
@testable import OCRKit

/// AV-16-02 G2 : une lecture OCR que plus personne n'attend s'arrête (lecteur fermé) ; une lecture qu'un autre appelant
/// attend encore (analyse du document) continue.
final class OCRServiceAbandonTests: XCTestCase {
    /// Moteur qui tourne jusqu'à son annulation (au plus `limit` secondes) puis rend une page vide.
    private final class WaitingEngine: OCREngine, @unchecked Sendable {
        let id: String
        private let lock = NSLock()
        private var cancelled = false
        private var finished = false
        init(id: String) { self.id = id }

        var sawCancellation: Bool { lock.withLock { cancelled } }
        var didFinish: Bool { lock.withLock { finished } }

        func recognize(_ input: OCRInput) async throws -> OCRPage {
            let limit = Date().addingTimeInterval(1.5)
            while Date() < limit {
                if Task.isCancelled { lock.withLock { cancelled = true }; throw CancellationError() }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            lock.withLock { finished = true }
            return OCRPage(engine: id, lines: [], durationMs: 0)
        }
    }

    private func fixture(engine: WaitingEngine) throws -> (OCRService, String) {
        let db = try AppDatabase.inMemory()
        let id = UUID().uuidString
        try db.save(LibraryDocument(id: id, title: "Synthétique", originalFileName: "test.pdf", pageCount: 1, fileSize: 1))
        OCRService.register(engine)
        return (OCRService(database: db), id)
    }

    private let url = URL(fileURLWithPath: "/dev/null")

    func testLastCallerCancelledStopsTheEngine() async throws {
        let engine = WaitingEngine(id: "attente-\(UUID().uuidString)")
        let (service, id) = try fixture(engine: engine)
        let caller = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await Task.sleep(nanoseconds: 100_000_000)
        caller.cancel()
        _ = try? await caller.value
        let deadline = Date().addingTimeInterval(1)
        while !engine.sawCancellation, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(engine.sawCancellation, "lecture abandonnée encore en cours")
        XCTAssertFalse(engine.didFinish)
    }

    func testAnotherWaitingCallerKeepsTheEngineRunning() async throws {
        let engine = WaitingEngine(id: "attente-\(UUID().uuidString)")
        let (service, id) = try fixture(engine: engine)
        let reader = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let analysis = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await Task.sleep(nanoseconds: 100_000_000)
        reader.cancel()
        let page = try await analysis.value
        XCTAssertEqual(page.engine, engine.id)
        XCTAssertFalse(engine.sawCancellation, "lecture annulée alors qu'un appelant l'attendait")
        XCTAssertTrue(engine.didFinish)
    }

    /// Revue T1 DeepSeek V4 Pro : un appelant qui arrive juste après l'abandon lance une lecture neuve, il ne rejoint pas
    /// la lecture annulée (il recevait `CancellationError`).
    func testCallerArrivingAfterAbandonGetsAFreshRead() async throws {
        let engine = WaitingEngine(id: "attente-\(UUID().uuidString)")
        let (service, id) = try fixture(engine: engine)
        let first = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await Task.sleep(nanoseconds: 100_000_000)
        first.cancel()
        let deadline = Date().addingTimeInterval(1)
        while !engine.sawCancellation, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        let page = try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id)
        XCTAssertEqual(page.engine, engine.id)
    }
}
