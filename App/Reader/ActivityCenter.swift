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

    enum Kind: String {
        case thumbnails, importing, comicImport, comicConversion, backup

        var title: String {
            switch self {
            case .thumbnails: return String(localized: "Miniatures")
            case .importing: return String(localized: "Import de documents")
            case .comicImport: return String(localized: "Import de CBZ")
            case .comicConversion: return String(localized: "Conversion de CBZ en PDF")
            case .backup: return String(localized: "Sauvegarde")
            }
        }
    }

    /// `end` part avec le `defer` de l'appelant : une erreur ou une annulation ferment aussi la mesure.
    func begin(_ kind: Kind, detail: String? = nil) -> UUID {
        let id = UUID()
        lock.withLock { ledger.begin(id, kind: kind.rawValue, detail: detail, at: Date()) }
        return id
    }

    func end(_ id: UUID) { lock.withLock { ledger.end(id, at: Date()) } }

    func snapshot() -> [ActivityLedger.Row] { lock.withLock { ledger.snapshot(at: Date()) } }
}
