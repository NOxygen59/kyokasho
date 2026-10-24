// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit
import PDFKit
import ReaderCore

/// Une intention durable, puis des installations rejouables de valeurs finales. Le journal et les
/// copies préparées restent présents jusqu'à la réussite de TOUS les stockages. Aucun décalage relatif
/// de fichiers/cartes n'est rejoué. Les anciens journaux ambigus sont conservés, jamais devinés.
@MainActor
enum PageShift {
    struct Pending: Codable {
        var documentId: String
        var offset: Int
        var oldCount: Int
        var oldSize: Int64
        var newCount: Int
        var newSize: Int64
        var stage: String
        // Optionnels pour reconnaître les journaux v1 déjà présents, sans migration destructive.
        var version: Int?
        var transaction: String?
        var oldHash: String?
        var newHash: String?
        var cardPages: [Int64: Int]?
        var hasReport: Bool?
    }

    // Racine injectable par les tests Mac ; en production, le conteneur reste celui de l'app.
    static var support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Kyokasho", isDirectory: true)
    /// Injection de panne uniquement dans le harnais ; nil dans l'app.
    static var checkpoint: ((String) throws -> Void)?
    private static let fm = FileManager.default
    private static var marker: URL { support.appendingPathComponent("page-shift.json") }
    private static func fail(_ text: String) -> NSError {
        NSError(domain: "Kyokasho.PageShift", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    private static func hit(_ name: String) throws { try checkpoint?(name) }
    private static func safeName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }
    private static func workspace(_ p: Pending) throws -> URL {
        guard let token = p.transaction, UUID(uuidString: token) != nil, safeName(p.documentId) else {
            throw fail("Journal d'ajout de pages invalide : fichiers conservés.")
        }
        return support.appendingPathComponent("PageShift/" + token, isDirectory: true)
    }
    private static func save(_ p: Pending) throws {
        try hit("journal.before")
        try JSONEncoder().encode(p).write(to: marker, options: .atomic)
        try hit("journal.after")
    }

    static func apply(_ model: AppModel, document: LibraryDocument, merged: URL, offset: Int, newCount: Int) throws -> [String] {
        guard model.persistentStorageAvailable, model.review.persistentStorageAvailable else {
            throw fail("Bases persistantes indisponibles : aucun ajout de pages effectué.")
        }
        guard !fm.fileExists(atPath: marker.path) else {
            throw fail("Un ajout précédent doit être repris avant de modifier les documents.")
        }
        guard safeName(document.id), document.pageCount > 0, newCount > document.pageCount,
              offset >= 0, offset <= newCount - document.pageCount,
              try model.database.document(id: document.id)?.pageCount == document.pageCount,
              PDFDocument(url: model.storage.url(for: document.id))?.pageCount == document.pageCount,
              PDFDocument(url: merged)?.pageCount == newCount else {
            throw fail("Le document ou les pages à ajouter ont changé. Aucun ajout effectué.")
        }
        let current = model.storage.url(for: document.id)
        let originalCardPages = try model.review.store.sourcePages(documentId: document.id)
        guard originalCardPages.values.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) else {
            throw fail("Une carte porte une page inattendue : ajout arrêté sans modification.")
        }
        var p = Pending(documentId: document.id, offset: offset, oldCount: document.pageCount,
                        oldSize: document.fileSize, newCount: newCount,
                        newSize: Int64(try merged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0),
                        stage: "prepared", version: 2, transaction: UUID().uuidString,
                        oldHash: try DocumentImporter.sha256(of: current),
                        newHash: try DocumentImporter.sha256(of: merged),
                        cardPages: originalCardPages.mapValues { $0 + offset },
                        hasReport: false)
        let work = try workspace(p)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            try fm.copyItem(at: current, to: work.appendingPathComponent("original.pdf"))
            try fm.copyItem(at: merged, to: work.appendingPathComponent("merged.pdf"))
            try prepareFiles(p, work: work)
            let report = DocumentAnalysisService.folder.appendingPathComponent(document.id + ".json")
            if fm.fileExists(atPath: report.path) {
                let bytes = try Data(contentsOf: report)
                var value = try JSONDecoder().decode(DocumentAnalysis.self, from: bytes)
                guard value.documentId == document.id else { throw fail("Rapport associé à un autre document.") }
                value.pages = Dictionary(uniqueKeysWithValues: value.pages.map { index, page in
                    var shifted = page
                    shifted.source = index + offset
                    return (index + offset, shifted)
                })
                try bytes.write(to: work.appendingPathComponent("original-report.json"), options: .atomic)
                try JSONEncoder().encode(value).write(to: work.appendingPathComponent("report.json"), options: .atomic)
                p.hasReport = true
            }
            try save(p) // Dernière étape avant toute mutation des données actives.
            try complete(p, model: model)
            model.storageRecoveryError = nil
            return []
        } catch {
            if fm.fileExists(atPath: marker.path) { block(model, error) }
            // Sans journal, seules des copies privées préparatoires existent ; les originaux restent intacts.
            throw error
        }
    }

    private static func prepareFiles(_ p: Pending, work: URL) throws {
        let source = DocumentAnalysisService.folder.appendingPathComponent(p.documentId, isDirectory: true)
        let prepared = work.appendingPathComponent("files", isDirectory: true)
        try fm.createDirectory(at: prepared, withIntermediateDirectories: true)
        guard fm.fileExists(atPath: source.path) else { return }
        for url in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw fail("Lien symbolique inattendu dans les lectures IA.")
            }
            var name = url.lastPathComponent
            let stem = url.deletingPathExtension().lastPathComponent
            if url.pathExtension == "md", let dash = stem.lastIndex(of: "-"), let page = Int(stem[stem.index(after: dash)...]) {
                guard page >= 0, page < p.oldCount else { throw fail("Lecture IA hors des pages du document : fichiers conservés.") }
                name = "\(stem[..<dash])-\(page + p.offset).md"
            }
            try fm.copyItem(at: url, to: prepared.appendingPathComponent(name))
        }
    }

    private static func complete(_ p: Pending, model: AppModel) throws {
        let work = try workspace(p)
        guard model.persistentStorageAvailable, model.review.persistentStorageAvailable,
              p.oldCount > 0, p.newCount > p.oldCount, p.offset >= 0, p.offset <= p.newCount - p.oldCount,
              p.version == 2, let oldHash = p.oldHash, let newHash = p.newHash,
              let cardPages = p.cardPages, let hasReport = p.hasReport else {
            throw fail("Journal incomplet : reprise arrêtée sans effacer les données.")
        }
        guard cardPages.values.allSatisfy({ $0 >= p.offset && $0 < p.oldCount + p.offset }) else {
            throw fail("Pages de cartes invalides dans le journal.")
        }
        let preparedPDF = work.appendingPathComponent("merged.pdf")
        guard try DocumentImporter.sha256(of: preparedPDF) == newHash else { throw fail("Copie PDF préparée altérée.") }
        let current = model.storage.url(for: p.documentId)
        let currentHash = try DocumentImporter.sha256(of: current)
        guard currentHash == oldHash || currentHash == newHash else {
            throw fail("Le PDF a changé depuis l'ajout : reprise arrêtée, copies conservées.")
        }
        try hit("database.before")
        try model.database.shiftPages(documentId: p.documentId, by: p.offset,
                                      pageCount: p.newCount, fileSize: p.newSize, expectedPageCount: p.oldCount)
        try hit("database.after")
        try hit("pdf.before")
        if currentHash != newHash {
            // Copie de travail : le fichier préparé et l'original restent disponibles pour la reprise.
            let install = current.deletingLastPathComponent().appendingPathComponent(".page-shift-\(p.transaction!).pdf")
            if fm.fileExists(atPath: install.path) { try fm.removeItem(at: install) }
            try fm.copyItem(at: preparedPDF, to: install)
            _ = try fm.replaceItemAt(current, withItemAt: install)
        }
        try hit("pdf.after")
        try hit("report.before")
        if hasReport {
            try Data(contentsOf: work.appendingPathComponent("report.json"))
                .write(to: DocumentAnalysisService.folder.appendingPathComponent(p.documentId + ".json"), options: .atomic)
        }
        try hit("report.after")
        try installFiles(p, work: work)
        try hit("cards.before")
        try model.review.store.setSourcePages(documentId: p.documentId, pages: cardPages)
        try hit("cards.after")
        DocumentAnalysisService.shared.reloadAfterPageShift(p.documentId)
        model.thumbnails.removeAll(for: p.documentId)
        ScanSharpening.removeCache(documentId: p.documentId)
        ScanSharpening.clearMemory()
        FuriganaLayer.clearMemory()
        LayoutRegionsCache.shared.clear()
        ToneCache.clear()
        PDFPool.release(current)
        try hit("complete.before")
        try fm.removeItem(at: marker) // Échec = journal conservé ; tout est rejouable.
        // Ne pas jeter ici les originaux : une suppression automatique sera étudiée après recette/restauration.
        // Le workspace, hors Caches, reste une copie de secours identifiée par son UUID.
    }

    private static func installFiles(_ p: Pending, work: URL) throws {
        let source = work.appendingPathComponent("files", isDirectory: true)
        let live = DocumentAnalysisService.folder.appendingPathComponent(p.documentId, isDirectory: true)
        let original = work.appendingPathComponent("original-files", isDirectory: true)
        let install = work.appendingPathComponent("install-files", isDirectory: true)
        // Toujours repartir de la copie préparée, jamais de noms déjà décalés.
        if fm.fileExists(atPath: install.path) { try fm.removeItem(at: install) }
        try fm.copyItem(at: source, to: install)
        if fm.fileExists(atPath: live.path) {
            if !fm.fileExists(atPath: original.path) {
                try fm.moveItem(at: live, to: original)
            } else {
                try fm.removeItem(at: live)
            }
        }
        try hit("files.backup")
        try fm.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: install, to: live)
        try hit("files.installed")
    }

    private static func block(_ model: AppModel, _ error: Error) {
        model.openDocumentId = nil
        model.storageRecoveryError = "L'ajout de pages doit être repris avant de continuer. " + error.localizedDescription
        Diagnostics.error(model.storageRecoveryError!, "pages")
    }

    static func reconcile(_ model: AppModel) {
        guard fm.fileExists(atPath: marker.path) else { model.storageRecoveryError = nil; return }
        do {
            guard model.persistentStorageAvailable, model.review.persistentStorageAvailable else {
                throw fail("Bases persistantes indisponibles : journal conservé pour la reprise.")
            }
            let p = try JSONDecoder().decode(Pending.self, from: Data(contentsOf: marker))
            if p.version == 2 {
                try complete(p, model: model)
            } else {
                // Le protocole v1 ne distingue pas avant/après l'effet pour report/files/cards.
                // Seul le cas PDF ancien + compte de base connu permet une annulation certaine.
                guard safeName(p.documentId), ["db", "pdf"].contains(p.stage),
                      PDFDocument(url: model.storage.url(for: p.documentId))?.pageCount == p.oldCount,
                      let count = try model.database.document(id: p.documentId)?.pageCount,
                      count == p.oldCount || count == p.newCount else {
                    throw fail("Ancien journal ambigu : une réparation sur copie est nécessaire ; journal et fichiers conservés.")
                }
                if count == p.newCount {
                    try model.database.shiftPages(documentId: p.documentId, by: -p.offset,
                                                  pageCount: p.oldCount, fileSize: p.oldSize, expectedPageCount: p.newCount)
                }
                try fm.removeItem(at: marker)
            }
            model.storageRecoveryError = nil
        } catch { block(model, error) }
    }
}
