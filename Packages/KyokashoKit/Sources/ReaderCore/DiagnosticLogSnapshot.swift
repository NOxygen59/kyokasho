// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Lecture seule d'un instantané du journal ; une rotation peut couper le premier caractère UTF-8.
public enum DiagnosticLogSnapshot {
    public static func read(from url: URL) -> String {
        do {
            let data = try Data(contentsOf: url)
            return data.isEmpty ? String(localized: "Journal vide.", bundle: .main) : String(decoding: data, as: UTF8.self)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return String(localized: "Aucun journal enregistré.", bundle: .main)
        } catch {
            return String(localized: "Impossible de lire le journal : \(error.localizedDescription)", bundle: .main)
        }
    }

    /// Fin du journal, pour l'affichage (RET-045, #67).
    public struct Tail: Equatable, Sendable {
        /// Lignes à afficher, de la plus ancienne à la plus récente (ou un seul message si le journal est absent,
        /// vide ou illisible).
        public var lines: [String]
        /// Octets du début du fichier non affichés (0 : tout le journal est là).
        public var omittedBytes: Int
    }

    /// Lit seulement la fin du journal : au plus `maxBytes` octets, puis au plus `maxLines` lignes.
    ///
    /// Le journal peut atteindre 2 Mo. Le lire en entier et le donner à un seul `Text` SwiftUI prenait plus de 30 s à
    /// s'afficher sur l'iPad. Seule la fin est lue (déplacement dans le fichier, sans tout charger) ; quand la lecture
    /// commence au milieu du fichier, la première ligne, sans doute coupée, est écartée. Le fichier complet reste
    /// disponible par « Partager le journal ».
    public static func readTail(from url: URL, maxBytes: Int = 200_000, maxLines: Int = 1_000) -> Tail {
        // `FileHandle` ouvre aussi un dossier sans erreur : même message que `read(from:)` dans ce cas.
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return Tail(lines: [read(from: url)], omittedBytes: 0)
        }
        // `FileHandle` ne renvoie pas le même code d'erreur que `Data(contentsOf:)` pour un fichier absent.
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Tail(lines: [String(localized: "Aucun journal enregistré.", bundle: .main)], omittedBytes: 0)
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            return Tail(lines: [String(localized: "Impossible de lire le journal : \(error.localizedDescription)", bundle: .main)], omittedBytes: 0)
        }
        defer { try? handle.close() }
        do {
            let size = Int(try handle.seekToEnd())
            if size == 0 { return Tail(lines: [String(localized: "Journal vide.", bundle: .main)], omittedBytes: 0) }
            let start = max(0, size - maxBytes)
            try handle.seek(toOffset: UInt64(start))
            let data = try handle.readToEnd() ?? Data()
            var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
            if lines.last == "" { lines.removeLast() }
            var omitted = start
            if start > 0, !lines.isEmpty {
                omitted += lines.removeFirst().utf8.count + 1
            }
            if lines.count > maxLines {
                let dropped = lines.prefix(lines.count - maxLines)
                omitted += dropped.reduce(0) { $0 + $1.utf8.count + 1 }
                lines.removeFirst(dropped.count)
            }
            return Tail(lines: lines, omittedBytes: omitted)
        } catch {
            return Tail(lines: [String(localized: "Impossible de lire le journal : \(error.localizedDescription)", bundle: .main)], omittedBytes: 0)
        }
    }
}
