// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Lecture seule d'un instantané du journal ; une rotation peut couper le premier caractère UTF-8.
public enum DiagnosticLogSnapshot {
    public static func read(from url: URL) -> String {
        do {
            let data = try Data(contentsOf: url)
            return data.isEmpty ? "Journal vide." : String(decoding: data, as: UTF8.self)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return "Aucun journal enregistré."
        } catch {
            return "Impossible de lire le journal : \(error.localizedDescription)"
        }
    }
}
