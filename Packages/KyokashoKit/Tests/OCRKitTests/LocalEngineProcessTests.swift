// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Network
import OCRKit
import XCTest

final class LocalEngineProcessTests: XCTestCase {
    /// Processus simulé : aucun vrai moteur lancé.
    private final class Fake: @unchecked Sendable {
        private let lock = NSLock()
        private var alive = Set<Int32>()
        private var next: Int32 = 100
        private var launches = 0
        var ready = true
        var launchError: Error?

        func launch() throws -> LocalEngineProcess.Instance {
            try lock.withLock {
                if let launchError { throw launchError }
                next += 1
                launches += 1
                alive.insert(next)
                return .init(pid: next, port: 1, token: "t")
            }
        }
        func isAlive(_ pid: Int32) -> Bool { lock.withLock { alive.contains(pid) } }
        func terminate(_ pid: Int32) { lock.withLock { _ = alive.remove(pid) } }
        var aliveCount: Int { lock.withLock { alive.count } }
        var launchCount: Int { lock.withLock { launches } }
        var isReady: Bool { lock.withLock { ready } }
    }

    private func engine(_ fake: Fake, startTimeout: TimeInterval = 5, idleDelay: TimeInterval = 0.05) -> LocalEngineProcess {
        LocalEngineProcess(driver: .init(launch: { try fake.launch() }, isAlive: { fake.isAlive($0) },
                                         terminate: { fake.terminate($0) }, isReady: { _ in fake.isReady },
                                         startTimeout: startTimeout, idleDelay: idleDelay, pollInterval: 0.01))
    }

    func testCancelledSlowStartStopsTheProcess() async throws {
        let fake = Fake()
        fake.ready = false
        let process = engine(fake)
        let read = Task { try await process.beginRead() }
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(fake.aliveCount, 1)
        read.cancel()
        _ = await read.result
        XCTAssertEqual(fake.aliveCount, 0)
        let status = await process.status
        XCTAssertFalse(status.inUse)
    }

    func testCancellingOneOfTwoStartsKeepsTheProcessForTheOther() async throws {
        let fake = Fake()
        fake.ready = false
        let process = engine(fake)
        let first = Task { try await process.beginRead() }
        try await Task.sleep(nanoseconds: 50_000_000)
        let second = Task { try await process.beginRead() }
        try await Task.sleep(nanoseconds: 50_000_000)
        first.cancel()
        _ = await first.result
        XCTAssertEqual(fake.aliveCount, 1)
        fake.ready = true
        _ = try await second.value
        XCTAssertEqual(fake.launchCount, 1)
    }

    func testIdleStopsAfterDelayAndNewReadRestarts() async throws {
        let fake = Fake()
        let process = engine(fake)
        _ = try await process.beginRead()
        await process.endRead()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(fake.aliveCount, 0)
        _ = try await process.beginRead()
        XCTAssertEqual(fake.launchCount, 2)
        await process.stop()
    }

    /// Un service déjà présent qui répond « prêt » n'est pas adopté : sans processus lancé par l'app, la lecture échoue.
    func testForeignServerIsNeverAdopted() async {
        let fake = Fake()
        fake.launchError = LocalEngineProcess.Failure.exitedDuringStart
        let process = engine(fake)
        do {
            _ = try await process.beginRead()
            XCTFail("Un serveur étranger a été adopté")
        } catch {
            XCTAssertEqual(error as? LocalEngineProcess.Failure, .exitedDuringStart)
        }
    }

    func testStartTimeoutStopsTheProcess() async {
        let fake = Fake()
        fake.ready = false
        let process = engine(fake, startTimeout: 0.05)
        do {
            _ = try await process.beginRead()
            XCTFail("Le démarrage aurait dû expirer")
        } catch {
            XCTAssertEqual(error as? LocalEngineProcess.Failure, .startTimedOut)
        }
        XCTAssertEqual(fake.aliveCount, 0)
    }

    /// Réponse 307 d'un serveur local : le corps de la requête n'est pas rejoué vers la destination.
    func testRedirectIsNotFollowed() async throws {
        let target = try NWListener(using: .tcp, on: .any)
        let reached = expectation(description: "destination")
        reached.isInverted = true
        target.newConnectionHandler = { connection in reached.fulfill(); connection.start(queue: .global()) }
        let targetReady = expectation(description: "destination prête")
        target.stateUpdateHandler = { if case .ready = $0 { targetReady.fulfill() } }
        target.start(queue: .global())
        await fulfillment(of: [targetReady], timeout: 5)
        let targetPort = try XCTUnwrap(target.port?.rawValue)

        let source = try NWListener(using: .tcp, on: .any)
        source.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                let reply = "HTTP/1.1 307 Temporary Redirect\r\nLocation: http://127.0.0.1:\(targetPort)/\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let sourceReady = expectation(description: "source prête")
        source.stateUpdateHandler = { if case .ready = $0 { sourceReady.fulfill() } }
        source.start(queue: .global())
        await fulfillment(of: [sourceReady], timeout: 5)
        let sourcePort = try XCTUnwrap(source.port?.rawValue)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(sourcePort)/")!, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.httpBody = Data("page-synthetique".utf8)
        let (_, response) = try await LocalOnlyHTTP.session.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 307)
        await fulfillment(of: [reached], timeout: 0.5)
        source.cancel()
        target.cancel()
    }
}
