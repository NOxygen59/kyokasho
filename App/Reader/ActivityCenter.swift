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
        case pageRender, pageText, sharpening, tone, furigana

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

    /// `end` part avec le `defer` de l'appelant : une erreur ou une annulation ferment aussi la mesure.
    func begin(_ kind: Kind, detail: String? = nil) -> UUID {
        let id = UUID()
        lock.withLock { ledger.begin(id, kind: kind.rawValue, detail: detail, at: Date()) }
        return id
    }

    func end(_ id: UUID) { lock.withLock { ledger.end(id, at: Date()) } }

    /// Travail synchrone dont le vrai temps processeur est mesuré. À garder hors de tout `await` : la mesure suit un seul fil.
    func measure<Result>(_ kind: Kind, detail: String? = nil, _ work: () throws -> Result) rethrows -> Result {
        let id = begin(kind, detail: detail)
        let start = ThreadCPU.seconds()
        defer {
            let spent = ThreadCPU.seconds() - start
            lock.withLock {
                ledger.addCPU(kind: kind.rawValue, seconds: spent)
                ledger.end(id, at: Date())
            }
        }
        return try work()
    }

    func snapshot() -> [ActivityLedger.Row] { lock.withLock { ledger.snapshot(at: Date()) } }
}
