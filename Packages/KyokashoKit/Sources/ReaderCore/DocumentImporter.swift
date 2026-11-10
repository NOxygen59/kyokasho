// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import CryptoKit
import Foundation

/// Emplacement des PDF importés : `<racine>/<sha256>.pdf`. Les fichiers ne sont jamais modifiés.
public struct DocumentStorage: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func url(for documentId: String) -> URL {
        root.appendingPathComponent(documentId).appendingPathExtension("pdf")
    }

    public func remove(documentId: String) {
        try? FileManager.default.removeItem(at: url(for: documentId))
    }

    /// Fichiers d'un import interrompu par un arrêt brutal (`<UUID>.partial`, `<UUID>.page`). Seuls ces noms privés, assez
    /// anciens pour ne pas être en cours d'écriture ; jamais un PDF, ni un dossier, ni un autre nom.
    @discardableResult
    public func removeAbandonedTemporaries(olderThan age: TimeInterval = 3600, now: Date = Date()) -> Int {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let files = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var removed = 0
        for file in files where ["partial", "page"].contains(file.pathExtension)
            && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let date = values.contentModificationDate, now.timeIntervalSince(date) >= age else { continue }
            if (try? fm.removeItem(at: file)) != nil { removed += 1 }
        }
        return removed
    }
}

public enum ImportError: LocalizedError, Equatable {
    case notAPDF
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .notAPDF: return String(localized: "Ce fichier n'est pas un PDF lisible.", bundle: .main)
        case .unreadable(let reason): return String(localized: "Lecture du fichier impossible : \(reason)", bundle: .main)
        }
    }
}

public struct ImportResult: Equatable, Sendable {
    public var document: LibraryDocument
    /// `false` si le même fichier était déjà dans la bibliothèque.
    public var isNew: Bool
    /// Comics : images illisibles ou trop lourdes laissées de côté.
    public var skippedPages = 0
}

/// Importe un PDF : empreinte SHA-256 (lue par blocs, mémoire constante), copie dans le stockage
/// de l'app, lecture du nombre de pages et du titre, enregistrement en base.
public struct DocumentImporter: Sendable {
    public let storage: DocumentStorage
    public let database: AppDatabase

    public init(storage: DocumentStorage, database: AppDatabase) {
        self.storage = storage
        self.database = database
    }

    /// Empreinte SHA-256 du fichier, lu par blocs de 1 Mo.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try autoreleasepool { try handle.read(upToCount: 1 << 20) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Nombre de pages et titre (métadonnées), via CoreGraphics (léger, pas de rendu).
    public static func inspect(_ url: URL) throws -> (pageCount: Int, title: String?) {
        guard let pdf = CGPDFDocument(url as CFURL), pdf.numberOfPages > 0 else { throw ImportError.notAPDF }
        var title: String?
        if let info = pdf.info {
            var raw: CGPDFStringRef?
            if CGPDFDictionaryGetString(info, "Title", &raw), let raw,
               let value = CGPDFStringCopyTextString(raw) as String? {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { title = trimmed }
            }
        }
        return (pdf.numberOfPages, title)
    }

    /// Importe le fichier `source` (déjà téléchargé et lisible).
    /// - Parameter preferFileNameTitle: utilise le nom du fichier plutôt que le titre des métadonnées
    ///   (souvent vide ou générique, ex. « Microsoft PowerPoint - … »).
    @discardableResult
    public func importFile(at source: URL, displayName: String? = nil, preferFileNameTitle: Bool = true,
                           driveFileId: String? = nil, driveRevision: String? = nil) throws -> ImportResult {
        let hash: String
        do {
            hash = try Self.sha256(of: source)
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
        if var existing = try database.document(id: hash) {
            if let driveFileId, existing.driveFileId == nil {
                existing.driveFileId = driveFileId
                existing.driveRevision = driveRevision
                try database.save(existing)
            }
            return ImportResult(document: existing, isNew: false)
        }

        let (pageCount, metadataTitle) = try Self.inspect(source)
        let fileName = displayName ?? source.lastPathComponent
        let baseName = (fileName as NSString).deletingPathExtension
        let title = preferFileNameTitle ? baseName : (metadataTitle ?? baseName)

        try FileManager.default.createDirectory(at: storage.root, withIntermediateDirectories: true)
        let destination = storage.url(for: hash)
        if !FileManager.default.fileExists(atPath: destination.path) {
            // Copie dans un fichier temporaire puis renommage : jamais de PDF à moitié copié.
            let temp = storage.root.appendingPathComponent(UUID().uuidString + ".partial")
            try FileManager.default.copyItem(at: source, to: temp)
            try FileManager.default.moveItem(at: temp, to: destination)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        let document = LibraryDocument(id: hash, title: title, originalFileName: fileName, pageCount: pageCount,
                                fileSize: size, driveFileId: driveFileId, driveRevision: driveRevision)
        try database.save(document)
        return ImportResult(document: document, isNew: true)
    }

    /// Remplace un document par une nouvelle version (même cours mis à jour) en gardant
    /// annotations, signets, commentaires et position de lecture.
    /// - Parameters:
    ///   - replacingInto: identifiant attendu du nouveau PDF (lot C2.3). Le remplacement est
    ///     journalé avant lui (`PageShift.withDriveReplacement`) ; si le fichier téléchargé a changé
    ///     depuis la préparation (nouvelle révision arrivée entre-temps), l'import s'arrête au lieu de
    ///     créer un document que le journal ne décrit pas.
    ///   - asideCorrections: DEC-C3 — remis à `rekeyDocument`, voir sa fiche ; l'app passe
    ///     `PageShift.asideCorrections` pour mettre de côté les lignes corrigées à la main.
    @discardableResult
    public func replace(documentId oldId: String, withFileAt source: URL, driveRevision: String? = nil,
                        replacingInto expectedId: String? = nil,
                        asideCorrections: AppDatabase.AsideCorrections? = nil) throws -> LibraryDocument {
        guard var old = try database.document(id: oldId) else { throw ImportError.unreadable(String(localized: "document inconnu", bundle: .main)) }
        let hash = try Self.sha256(of: source)
        if let expectedId, hash != expectedId {
            throw ImportError.unreadable(String(localized: "Le fichier a changé depuis la préparation du remplacement.", bundle: .main))
        }
        if hash == oldId {
            if let driveRevision { old.driveRevision = driveRevision; try database.save(old) }
            return old
        }
        let (pageCount, _) = try Self.inspect(source)
        let destination = storage.url(for: hash)
        if !FileManager.default.fileExists(atPath: destination.path) {
            let temp = storage.root.appendingPathComponent(UUID().uuidString + ".partial")
            try FileManager.default.copyItem(at: source, to: temp)
            try FileManager.default.moveItem(at: temp, to: destination)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        var updated = old
        updated.id = hash
        updated.pageCount = pageCount
        updated.fileSize = size
        updated.lastPageIndex = min(old.lastPageIndex, max(0, pageCount - 1))
        updated.driveRevision = driveRevision ?? old.driveRevision
        try database.rekeyDocument(from: oldId, to: updated, asideCorrections: asideCorrections)
        storage.remove(documentId: oldId)
        return updated
    }

    /// Supprime le document, ses annotations (cascade) et son fichier.
    public func delete(documentId: String) throws {
        try database.deleteDocument(id: documentId)
        storage.remove(documentId: documentId)
    }
}
