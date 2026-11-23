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
        /// Numéro de lecture qui échoue (pour isoler ce qu'écrit une lecture précédente).
        var failingRun: Int?
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
            let run = lock.withLock { () -> Int in finishes += 1; return starts }
            if run == failingRun { throw OCRError.pageUnavailable }
            return OCRPage(engine: id, lines: [], durationMs: run)  // Numéro de lecture, pour les distinguer en base.
        }
    }

    private let url = URL(fileURLWithPath: "/dev/null")

    /// Valeur relevée par le crochet de la barrière (appelé dans l'acteur).
    private final class SeenAtBarrier: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: Int?
        func record(_ value: Int) { lock.withLock { seen = value } }
        var value: Int? { lock.withLock { seen } }
    }

    private var database: AppDatabase!

    private func fixture(_ engine: GateEngine,
                         postProcess: (@Sendable (OCRPage) async -> OCRPage)? = nil) throws -> (OCRService, String, String) {
        let db = try AppDatabase.inMemory()
        database = db
        let id = UUID().uuidString
        try db.save(LibraryDocument(id: id, title: "Synthétique", originalFileName: "test.pdf", pageCount: 1, fileSize: 1))
        OCRService.register(engine)
        return (OCRService(database: db, postProcess: postProcess), id, "\(id)#0#\(engine.id)#r0")
    }

    private struct NeverTrue: Error, CustomStringConvertible { let description: String }

    /// Attend une condition (5 s au plus) ; lève une erreur sinon, ce qui arrête le test (et `defer` ouvre la porte).
    private func eventually(_ what: String, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await condition()) {
            guard Date() < deadline else { throw NeverTrue(description: "jamais vrai : \(what)") }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func testLastCallerCancelledStopsTheEngine() async throws {
        let engine = GateEngine(cooperative: true)
        let (service, id, key) = try fixture(engine)
        defer { engine.release() }  // Jamais de moteur bloqué après un échec.
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
        defer { engine.release() }  // Jamais de moteur bloqué après un échec.
        let reader = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await eventually("lecteur inscrit, moteur démarré") { await service.lectureState(key).waiters == 1 && engine.startCount == 1 }
        let analysis = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await eventually("analyse inscrite") { await service.lectureState(key).waiters == 2 }
        reader.cancel()
        try await eventually("départ du lecteur compté") { await service.lectureState(key).waiters == 1 }
        engine.release()
        let page = try await analysis.value
        XCTAssertEqual(page.engine, engine.id)
        XCTAssertEqual(engine.cancelCount, 0, "lecture annulée alors qu'un appelant l'attendait")
        XCTAssertEqual(engine.startCount, 1)
        // Revue T3 puis finale Codex : le créateur parti reçoit une annulation, et la lecture menée à terme est
        // pourtant écrite en base (lue directement, sans passer par running[key]).
        do { _ = try await reader.value; XCTFail("le créateur annulé a reçu un résultat") } catch is CancellationError {}
        XCTAssertNotNil(try database.ocrResult(documentId: id, pageIndex: 0, engine: engine.id), "lecture terminée absente du cache")
    }

    /// Revue finale Codex de e790ca2 : une lecture abandonnée pendant sa relecture (moteur déjà fini) ne doit rien écrire
    /// en base ; sinon elle pourrait écraser une lecture plus récente. La lecture suivante échoue exprès : la base doit
    /// rester vide.
    func testAbandonedDuringReviewWritesNothing() async throws {
        let engine = GateEngine(cooperative: false)
        engine.failingRun = 2
        let reviewOpen = Flag()  // Porte de la relecture de la 1re lecture seulement.
        let inReview = Flag()    // Levé par la relecture elle-même : on est bien dedans (revue finale Codex de 547a48f).
        let (service, id, key) = try fixture(engine, postProcess: { page in
            if page.durationMs == 1 {
                inReview.turnOn()
                while !reviewOpen.isOn { Thread.sleep(forTimeInterval: 0.002) }
            }
            return page
        })
        defer { engine.release(); reviewOpen.turnOn() }
        engine.release()  // Le moteur répond tout de suite ; la 1re lecture reste bloquée dans sa relecture.
        let first = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await eventually("1re lecture entrée en relecture") { inReview.isOn }
        first.cancel()
        try await eventually("1re lecture abandonnée") { await service.lectureState(key).abandoned }
        let second = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await eventually("2e appel en attente") { await service.lectureState(key).waitingOnAbandoned == 1 }
        reviewOpen.turnOn()  // La 1re lecture sort de sa relecture, abandonnée.
        do { _ = try await second.value; XCTFail("la 2e lecture devait échouer") } catch OCRError.pageUnavailable {}
        _ = try? await first.value
        XCTAssertNil(try database.ocrResult(documentId: id, pageIndex: 0, engine: engine.id),
                     "la lecture abandonnée a écrit en base")
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var on = false
        var isOn: Bool { lock.withLock { on } }
        func turnOn() { lock.withLock { on = true } }
    }

    /// Revue T1 DeepSeek V4 Pro puis T3 Codex : l'appelant arrivé après l'abandon ne reçoit pas `CancellationError` ; il
    /// attend la fin du moteur qui ignore l'annulation, puis lance une lecture neuve (jamais deux moteurs en parallèle).
    func testCallerAfterAbandonWaitsForTheEndThenReadsAgain() async throws {
        let engine = GateEngine(cooperative: false)
        let (service, id, key) = try fixture(engine)
        defer { engine.release() }  // Jamais de moteur bloqué après un échec.
        let first = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await eventually("premier moteur démarré") { await service.lectureState(key).waiters == 1 && engine.startCount == 1 }
        first.cancel()
        try await eventually("lecture abandonnée, encore en cours") { await service.lectureState(key).abandoned }
        let second = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await eventually("second appel en attente de la fin") { await service.lectureState(key).waitingOnAbandoned == 1 }
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
        defer { engine.release() }  // Jamais de moteur bloqué après un échec.
        let first = Task { try await service.page(documentId: id, url: url, pageIndex: 0, engine: engine.id) }
        try await eventually("moteur démarré") { await service.lectureState(key).waiters == 1 && engine.startCount == 1 }
        first.cancel()
        try await eventually("lecture abandonnée") { await service.lectureState(key).abandoned }
        // Fin du moteur relevée dans l'acteur, à la sortie même de la barrière (revue finale Codex de 7304d95).
        let seen = SeenAtBarrier()
        await service.setPageMutationBarrierHook { seen.record(engine.finishCount) }
        let mutation = Task { () -> Int in
            await service.beginPageMutation(documentId: id)
            return seen.value ?? -1
        }
        // Entrée dans la barrière observée : `beginPageMutation` a déjà capturé la lecture à attendre.
        try await eventually("changement de pages commencé") { await service.isReplacingPages(id) }
        XCTAssertEqual(engine.finishCount, 0)
        engine.release()
        let finishedBeforeMutationEnded = await mutation.value
        XCTAssertEqual(finishedBeforeMutationEnded, 1, "changement de pages terminé avant la fin du moteur")
        await service.endPageMutation(documentId: id)
    }
}
