// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Fichiers de diagnostic d'un dossier (`Documents/Diagnostics` dans l'app, dossier temporaire dans les tests) :
/// mise à l'écart DEC-07 comme condition d'accès, écriture du journal avec rotation DEC-06, partage, effacement et
/// poids. Réunion DIAG du 25/11 et revue R2 passage 3 : toutes les décisions sur les fichiers vivent ici pour être
/// éprouvées sur de vrais fichiers ; l'app n'ajoute que sa file d'écriture et ses écrans.
///
/// À appeler depuis une seule file d'écriture (celle du journal de l'app) ; l'état « prêt » est lisible de partout.
public final class DiagnosticStore: @unchecked Sendable {
    public let folder: URL
    private let lock = NSLock()
    private var ready = false

    public init(folder: URL) { self.folder = folder }

    public var journal: URL { folder.appendingPathComponent(DiagnosticJournalPolicy.currentName) }
    public var previousJournal: URL { folder.appendingPathComponent(DiagnosticJournalPolicy.previousName) }
    public var energy: URL { folder.appendingPathComponent("energie.csv") }

    /// Vrai seulement après une mise à l'écart réussie (ou déjà faite) : sinon ni écriture, ni lecture, ni partage.
    public var isReady: Bool { lock.withLock { ready } }

    /// Opérations réelles : présence (une erreur d'accès n'est pas une absence) et déplacement sans remplacement.
    public func fileSystemOperations(_ fm: FileManager = .default) -> DiagnosticFileMigration.Operations {
        let folder = folder
        return .init(presence: { name in
            do {
                _ = try fm.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
                return .present
            } catch let error as NSError where (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError)
                                              || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)) {
                return .absent
            } catch {
                return .unknown
            }
        }, move: { from, to in
            // `moveItem` échoue si la cible existe : jamais d'écrasement.
            (try? fm.moveItem(at: folder.appendingPathComponent(from), to: folder.appendingPathComponent(to))) != nil
        })
    }

    /// Mise à l'écart et état. `record` n'est appelé qu'en cas de réussite (enregistrement de la révision).
    @discardableResult
    public func migrate(storedRevision: Int, operations: DiagnosticFileMigration.Operations? = nil,
                        record: (Int) -> Void) -> DiagnosticFileMigration.Outcome {
        let outcome = DiagnosticFileMigration.run(storedRevision: storedRevision, operations: operations ?? fileSystemOperations())
        if outcome == .ready { record(DiagnosticFileMigration.revision) }
        lock.withLock { ready = outcome == .ready }
        return outcome
    }

    /// Ajoute au journal ; au-delà du seuil, il devient le journal précédent (remplacement atomique) et un nouveau
    /// commence par une ligne de rotation, écrite seulement si le déplacement a réussi. Rien si pas prêt.
    @discardableResult
    public func appendJournal(_ text: String, rotationBytes: Int = DiagnosticJournalPolicy.rotationBytes,
                              now: Date = Date()) -> Bool {
        guard isReady else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let size = Self.size(journal), size > rotationBytes {
            let rotated: Bool
            if fm.fileExists(atPath: previousJournal.path) {
                rotated = (try? fm.replaceItemAt(previousJournal, withItemAt: journal)) != nil
            } else {
                rotated = (try? fm.moveItem(at: journal, to: previousJournal)) != nil
            }
            if rotated && !fm.fileExists(atPath: journal.path) {
                let note = DiagnosticLine.legacy(.alerte, area: DiagnosticZone.journal.rawValue,
                                                 message: "Rotation du journal : l'ancien (\(size) octets) est dans \(DiagnosticJournalPolicy.previousName)",
                                                 at: now)
                try? Data((note + "\n").utf8).write(to: journal)
            }
        }
        if let handle = try? FileHandle(forWritingTo: journal) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: journal)
        }
        return true
    }

    /// Ajoute une ligne au relevé de batterie : création avec `header`, rotation par `rotate` au-delà de `limit`
    /// octets. Rien si pas prêt (revue R2 passage 4 : l'écrivain du relevé éprouvé comme celui du journal).
    @discardableResult
    public func appendEnergy(_ line: String, header: String, limit: Int, rotate: (Data, Int) -> Data) -> Bool {
        guard isReady else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let size = Self.size(energy), size > limit, let data = try? Data(contentsOf: energy) {
            try? rotate(data, limit / 2).write(to: energy)
        }
        if let handle = try? FileHandle(forWritingTo: energy) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? Data((header + "\n" + line + "\n").utf8).write(to: energy)
        }
        return true
    }

    /// Fichiers partageables : actifs existants, seulement si prêt. Les anciens fichiers mis à l'écart n'en font
    /// jamais partie.
    public func shareable() -> [URL] {
        guard isReady else { return [] }
        return [journal, previousJournal, energy].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Anciens fichiers mis à l'écart d'une famille (noms gérés seulement).
    public func isolated(_ family: DiagnosticFileMigration.Family) -> [URL] {
        DiagnosticFileMigration.isolatedNames(family).map { folder.appendingPathComponent($0) }
    }

    /// Effacement **explicite** d'une famille (geste de l'utilisateur), possible même bloqué. Ne touche que les noms
    /// gérés ; un échec ne débloque rien.
    public func erase(_ family: DiagnosticFileMigration.Family) {
        let actives = family == .journal ? [journal, previousJournal] : [energy]
        for url in actives + isolated(family) { try? FileManager.default.removeItem(at: url) }
    }

    /// Poids local de chaque famille (actifs et anciens fichiers mis à l'écart).
    public func sizes() -> (journal: Int, energy: Int) {
        let total = { (urls: [URL]) in urls.reduce(0) { $0 + (Self.size($1) ?? 0) } }
        return (total([journal, previousJournal] + isolated(.journal)), total([energy] + isolated(.energy)))
    }

    static func size(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }
}
