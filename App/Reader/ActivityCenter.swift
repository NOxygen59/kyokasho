// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore

/// Registre partagé, appelé depuis n'importe quel fil. Une entrée ne coûte qu'un verrou ; rien n'est relevé tant que le
/// panneau déplié de l'accueil ne le demande pas.
final class ActivityCenter: @unchecked Sendable {
    static let shared = ActivityCenter()
    private let lock = NSLock()
    private var ledger = ActivityLedger()

    typealias Kind = DiagnosticCPULog.Kind
    private struct Observed {
        let kind: Kind
        let start: TimeInterval
        let page: Int?
        let visiblePage: Int?
    }
    private var diagnosticRunning: [UUID: Observed] = [:]
    private var diagnosticLong = DiagnosticCPULog.LongWork()
    /// Copie en mémoire du mode diagnostic (revue R2 D) : les chemins fréquents ne relisent pas les préférences.
    private var diagnosticsOn = false

    func setDiagnostics(_ on: Bool) {
        lock.withLock {
            diagnosticsOn = on
            if !on { diagnosticRunning.removeAll(); diagnosticLong = .init() }
        }
    }

    /// `end` part avec le `defer` de l'appelant : une erreur ou une annulation ferment aussi la mesure.
    func begin(_ kind: Kind, detail: String? = nil, page: Int? = nil) -> UUID {
        let id = UUID()
        lock.withLock {
            ledger.begin(id, kind: kind.rawValue, detail: detail, at: Date())
            if diagnosticsOn { diagnosticRunning[id] = Observed(kind: kind, start: ProcessInfo.processInfo.systemUptime,
                                                                       page: page, visiblePage: page == nil ? DiagnosticCPU.shared.visiblePage : nil) }
        }
        return id
    }

    func end(_ id: UUID) {
        lock.withLock {
            if diagnosticsOn { diagnosticRunning.removeValue(forKey: id) }
            ledger.end(id, at: Date())
        }
    }

    /// Travail synchrone dont le vrai temps processeur est mesuré. À garder hors de tout `await` : la mesure suit un seul fil.
    func measure<Result>(_ kind: Kind, detail: String? = nil, page: Int? = nil, _ work: () throws -> Result) rethrows -> Result {
        let id = begin(kind, detail: detail, page: page)
        let start = ThreadCPU.seconds()
        defer {
            let spent = ThreadCPU.seconds() - start
            lock.withLock {
                ledger.addCPU(kind: kind.rawValue, seconds: spent)
                ledger.end(id, at: Date())
                if diagnosticsOn, let observed = diagnosticRunning.removeValue(forKey: id) {
                    diagnosticLong.add(.init(kind: observed.kind, seconds: ProcessInfo.processInfo.systemUptime - observed.start,
                                             page: observed.page, visiblePage: observed.visiblePage, cpuSeconds: max(0, spent)))
                }
            }
        }
        return try work()
    }

    func snapshot() -> [ActivityLedger.Row] { lock.withLock { ledger.snapshot(at: Date()) } }

    /// Ne consomme pas le relevé de l'accueil et ne reprend jamais ses libellés libres.
    func diagnosticActive() -> [DiagnosticCPULog.Work] {
        lock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            return diagnosticRunning.values.map {
                .init(kind: $0.kind, seconds: now - $0.start, page: $0.page, visiblePage: $0.visiblePage)
            }.sorted { $0.seconds > $1.seconds }
        }
    }

    func takeDiagnosticLongWork() -> DiagnosticCPULog.LongWork {
        lock.withLock {
            let batch = diagnosticLong
            diagnosticLong = .init()
            return batch
        }
    }

    func clearDiagnostic() {
        lock.withLock { diagnosticRunning.removeAll(); diagnosticLong = .init() }
    }
}

extension DiagnosticCPULog.Kind {
    var title: String {
        switch self {
        case .thumbnails: return String(localized: "Miniatures")
        case .importing: return String(localized: "Import de documents")
        case .comicImport: return String(localized: "Import de CBZ")
        case .comicConversion: return String(localized: "Conversion de CBZ en PDF")
        case .backup: return String(localized: "Sauvegarde")
        case .pageRender: return String(localized: "Dessin des pages")
        case .pageText: return String(localized: "Texte des pages")
        case .sharpening: return String(localized: "Nettoyage des scans")
        case .tone: return String(localized: "Teinte des pages")
        case .furigana: return String(localized: "Furigana")
        }
    }
}
