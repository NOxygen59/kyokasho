// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Darwin
import Foundation

/// Les paquets déclarent un segment synchrone sans connaître le registre de l'app.
public enum DiagnosticThreadHook {
    public struct Context: Sendable {
        public let documentID: String
        public let page: Int?
        public let renderKind: DiagnosticCPULog.Kind
        public init(documentID: String, page: Int?, renderKind: DiagnosticCPULog.Kind = .ocrRender) {
            self.documentID = documentID; self.page = page; self.renderKind = renderKind
        }
    }

    public typealias Begin = @Sendable (DiagnosticCPULog.Kind, String?, Int?) -> (() -> Void)?
    private final class Slot: @unchecked Sendable {
        let lock = NSLock()
        var begin: Begin?
    }
    private static let slot = Slot()
    private static let context = TaskLocal<Context?>(wrappedValue: nil)

    public static func install(_ begin: Begin?) { slot.lock.withLock { slot.begin = begin } }

    public static func measure<T>(_ kind: DiagnosticCPULog.Kind, documentID: String? = nil, page: Int? = nil,
                                  useRenderKind: Bool = false, _ work: () throws -> T) rethrows -> T {
        guard let begin = slot.lock.withLock({ slot.begin }) else { return try work() }
        let scope = context.get()
        let end = begin(useRenderKind ? scope?.renderKind ?? kind : kind,
                        documentID ?? scope?.documentID, page ?? scope?.page)
        defer { end?() }
        return try work()
    }

    /// L'identité voyage avec la tâche, jamais le nom du fil. Seul `measure` renomme le fil.
    public static func withContext<T>(documentID: String, page: Int, renderKind: DiagnosticCPULog.Kind = .ocrRender,
                                      _ work: () async throws -> T) async rethrows -> T {
        guard slot.lock.withLock({ slot.begin != nil }) else { return try await work() }
        return try await context.withValue(Context(documentID: documentID, page: page, renderKind: renderKind), operation: work)
    }

    /// Ne renomme que si le nom précédent peut être restauré, sur ce même fil.
    public static func restoreNameAfterSetting(_ kind: DiagnosticCPULog.Kind) -> (() -> Void)? {
        let thread = pthread_self()
        var previous = [CChar](repeating: 0, count: 64)
        guard pthread_getname_np(thread, &previous, previous.count) == 0,
              pthread_setname_np("kyo.\(kind.rawValue)") == 0 else { return nil }
        return { _ = previous.withUnsafeBufferPointer { pthread_setname_np($0.baseAddress!) } }
    }
}
