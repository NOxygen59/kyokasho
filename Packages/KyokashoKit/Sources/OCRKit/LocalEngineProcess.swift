// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Session pour un moteur local : aucune redirection suivie. Sinon une réponse 307 rejouerait l'image d'une page vers une
/// autre adresse, ce qui contredirait « rien ne sort du Mac » (revue Codex du 04/11/2026).
public enum LocalOnlyHTTP {
    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
    }()
}

/// Cycle de vie d'un moteur lancé par l'app : démarrage à la première lecture, arrêt après inactivité. L'app ne parle qu'à
/// un processus qu'elle a lancé elle-même : un service déjà présent sur la machine n'est jamais adopté.
public actor LocalEngineProcess {
    public struct Instance: Sendable, Equatable {
        public let pid: Int32
        public let port: Int
        public let token: String

        public init(pid: Int32, port: Int, token: String) {
            self.pid = pid
            self.port = port
            self.token = token
        }
    }

    public struct Driver: Sendable {
        public var launch: @Sendable () throws -> Instance
        public var isAlive: @Sendable (Int32) -> Bool
        public var terminate: @Sendable (Int32) -> Void
        public var isReady: @Sendable (Instance) async -> Bool
        public var startTimeout: TimeInterval
        public var idleDelay: TimeInterval
        public var pollInterval: TimeInterval

        public init(launch: @escaping @Sendable () throws -> Instance, isAlive: @escaping @Sendable (Int32) -> Bool,
                    terminate: @escaping @Sendable (Int32) -> Void, isReady: @escaping @Sendable (Instance) async -> Bool,
                    startTimeout: TimeInterval, idleDelay: TimeInterval, pollInterval: TimeInterval = 1) {
            self.launch = launch
            self.isAlive = isAlive
            self.terminate = terminate
            self.isReady = isReady
            self.startTimeout = startTimeout
            self.idleDelay = idleDelay
            self.pollInterval = pollInterval
        }
    }

    public struct Status: Sendable, Equatable {
        public let starting: Bool
        public let running: Bool
        public let inUse: Bool
    }

    public enum Failure: Error, Equatable {
        case exitedDuringStart
        case startTimedOut
    }

    private let driver: Driver
    private var instance: Instance?
    private var ready = false
    private var reads = 0
    private var idleTask: Task<Void, Never>?

    public init(driver: Driver) { self.driver = driver }

    public var status: Status {
        Status(starting: instance != nil && !ready, running: instance != nil && ready, inUse: reads > 0)
    }

    /// Réserve le moteur pour une lecture. Chaque succès doit être suivi d'un `endRead()`. En cas d'échec, annulation
    /// comprise, rien ne reste réservé, et le processus est arrêté si aucune autre lecture ne s'en sert.
    public func beginRead() async throws -> Instance {
        idleTask?.cancel()
        idleTask = nil
        reads += 1
        do {
            return try await waitUntilReady()
        } catch {
            reads -= 1
            if reads == 0 { stop() }
            throw error
        }
    }

    public func endRead() {
        reads -= 1
        guard reads == 0 else { return }
        let delay = driver.idleDelay
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.stopIfIdle()
        }
    }

    public func stop() {
        idleTask?.cancel()
        idleTask = nil
        guard let current = instance else { return }
        instance = nil
        ready = false
        driver.terminate(current.pid)
    }

    private func stopIfIdle() { if reads == 0 { stop() } }

    private func waitUntilReady() async throws -> Instance {
        if let current = instance, !driver.isAlive(current.pid) {
            instance = nil
            ready = false
        }
        if instance == nil {
            instance = try driver.launch()
            ready = false
        }
        let deadline = Date().addingTimeInterval(driver.startTimeout)
        while true {
            try Task.checkCancellation()
            guard let current = instance, driver.isAlive(current.pid) else {
                instance = nil
                ready = false
                throw Failure.exitedDuringStart
            }
            if ready { return current }
            if await driver.isReady(current) {
                // `stop()` a pu passer pendant l'attente : seule l'instance encore en place devient prête.
                if instance == current {
                    ready = true
                    return current
                }
                continue
            }
            guard Date() < deadline else { throw Failure.startTimedOut }
            try await Task.sleep(nanoseconds: UInt64(driver.pollInterval * 1_000_000_000))
        }
    }
}
