// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore
import XCTest
@testable import OCRKit

/// AV-16-02 G2 : une lecture OCR que plus personne n'attend s'arrête (lecteur fermé) ; une lecture qu'un autre appelant
/// attend encore (analyse du document) continue ; un appelant qui arrive après l'abandon attend la fin réelle puis relit ;
/// `beginPageMutation` attend toujours une lecture abandonnée. Synchronisé sur l'état du service, pas sur des délais.
final class OCRServiceAbandonTests: XCTestCase {
    /// Moteur retenu jusqu'à `release()`. Coopératif : s'arrête à l'annulation ; sinon l'ignore (moteur natif).
    private final class GateEngine: OCREngine, @unchecked Sendable {
        let id: String
        let cooperative: Bool
        private let lock = NSLock()
        private var released = false
        private var starts = 0, cancels = 0, finishes = 0
        init(cooperative: Bool) {
            id = "porte-\(UUID().uuidString)"
            self.cooperative = cooperative
        }
        var startCount: Int { lock.withLock { starts } }
        var cancelCount: Int { lock.withLock { cancels } }
        var finishCount: Int { lock.withLock { finishes } }
        func release() { lock.withLock { released = true } }

        func recognize(_ input: OCRInput) async throws -> OCRPage {
            lock.withLock { starts += 1 }
            while !lock.withLock({ released }) {
                if cooperative, Task.isCancelled { lock.withLock { cancels += 1 }; throw CancellationError() }
                Thread.sleep(forTimeInterval: 0.002)
            }
            lock.withLock { finishes += 1 }
            return OCRPage(engine: id, lines: [], durationMs: 0)
        }
    }

    private let url = URL(fileURLWithPath: "/dev/null")

    private func fixture(_ engine: GateEngine) throws -> (OCRService, String, String) {
        let db = try AppDatabase.inMemory()
        let id = UUID().uuidString
        try db.save(LibraryDocument(id: id, title: "Synthétique", originalFileName: "test.pdf", pageCount: 1, fileSize: 1))
        OCRService.register(engine)
        return (OCRService(database: db), id, "\(id)#0#\(engine.id)#r0")
    }

    /// Attend une condition (5 s au plus) ; échoue sinon.
    private func eventually(_ what: String, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await condition()) {
            guard Date() < deadline else { return XCTFail("jamais vrai : \(what)") }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func testLastCallerCancelledStopsTheEngine() async throws {
        let engine = GateEngine(cooperative: true)
        let (service, id, key) = try fixture(engine)
        let caller = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await eventually("lecture lancée, un appelant") { await service.lectureState(key).waiters == 1 && engine.startCount == 1 }
        caller.cancel()
        try await eventually("moteur annulé") { engine.cancelCount == 1 }
        _ = try? await caller.value
        XCTAssertEqual(engine.finishCount, 0)
        try await eventually("clé libérée") { await !service.lectureState(key).running }
    }

    func testAnotherWaitingCallerKeepsTheEngineRunning() async throws {
        let engine = GateEngine(cooperative: true)
        let (service, id, key) = try fixture(engine)
        let reader = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await eventually("lecteur inscrit") { await service.lectureState(key).waiters == 1 }
        let analysis = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await eventually("analyse inscrite") { await service.lectureState(key).waiters == 2 }
        reader.cancel()
        try await eventually("départ du lecteur compté") { await service.lectureState(key).waiters == 1 }
        engine.release()
        let page = try await analysis.value
        XCTAssertEqual(page.engine, engine.id)
        XCTAssertEqual(engine.cancelCount, 0, "lecture annulée alors qu'un appelant l'attendait")
        XCTAssertEqual(engine.startCount, 1)
    }

    /// Revue T1 DeepSeek V4 Pro puis T3 Codex : l'appelant arrivé après l'abandon ne reçoit pas `CancellationError` ; il
    /// attend la fin du moteur qui ignore l'annulation, puis lance une lecture neuve (jamais deux moteurs en parallèle).
    func testCallerAfterAbandonWaitsForTheEndThenReadsAgain() async throws {
        let engine = GateEngine(cooperative: false)
        let (service, id, key) = try fixture(engine)
        let first = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await eventually("première lecture inscrite") { await service.lectureState(key).waiters == 1 }
        first.cancel()
        try await eventually("lecture abandonnée, encore en cours") { await service.lectureState(key).abandoned }
        let second = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(engine.startCount, 1, "seconde lecture lancée pendant l'ancienne")
        engine.release()
        let page = try await second.value
        XCTAssertEqual(page.engine, engine.id)
        XCTAssertEqual(engine.startCount, 2)
    }

    /// Revue T3 Codex : `beginPageMutation` attend la fin réelle d'une lecture abandonnée (barrière de PageShift).
    func testPageMutationWaitsForAnAbandonedRead() async throws {
        let engine = GateEngine(cooperative: false)
        let (service, id, key) = try fixture(engine)
        let first = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await eventually("lecture inscrite") { await service.lectureState(key).waiters == 1 }
        first.cancel()
        try await eventually("lecture abandonnée") { await service.lectureState(key).abandoned }
        let mutation = Task { () -> Int in
            await service.beginPageMutation(documentId: id)
            return engine.finishCount
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        engine.release()
        let finishedBeforeMutationEnded = await mutation.value
        XCTAssertEqual(finishedBeforeMutationEnded, 1, "changement de pages terminé avant la fin du moteur")
        await service.endPageMutation(documentId: id)
    }
}
