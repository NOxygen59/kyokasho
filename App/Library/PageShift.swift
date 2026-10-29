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
        /// Brouillons de notes préparés (RET-008). `nil` dans les journaux écrits avant leur ajout : rien à installer.
        var hasDrafts: Bool? = nil
        /// v3 (#49) : correspondance des pages, version de mise en page attendue et pages finales des cartes
        /// (`nil` = carte gardée sans page). L'identifiant d'opération en base est `transaction`.
        var mapping: PageMapping? = nil
        var expectedLayoutVersion: Int? = nil
        var cardTargets: [Int64: Int?]? = nil
        /// v3 : pages des cartes avant l'opération ; chaque cible doit en être exactement l'image (revue Codex F4).
        var cardSources: [Int64: Int]? = nil
    }

    /// Correspondance d'un journal : v3 la porte ; v2 la décrit par le décalage (pages ajoutées avant les anciennes).
    static func mapping(of p: Pending) throws -> PageMapping {
        if p.version == 3 {
            guard let mapping = p.mapping, mapping.oldCount == p.oldCount, mapping.newCount == p.newCount else {
                throw fail("Correspondance des pages absente du journal : reprise arrêtée sans effacer les données.")
            }
            return mapping
        }
        return try PageMapping(oldCount: p.oldCount, newCount: p.newCount, targets: (0..<p.oldCount).map { $0 + p.offset })
    }

    // Racine injectable par les tests Mac ; en production, le conteneur reste celui de l'app.
    static var support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Kyokasho", isDirectory: true)
    /// Injection de panne uniquement dans le harnais ; nil dans l'app.
    static var checkpoint: ((String) throws -> Void)?
    private static let fm = FileManager.default
    private static var applyingDocuments: Set<String> = []
    private static var marker: URL { support.appendingPathComponent("page-shift.json") }
    static var pendingDocumentId: String? {
        guard let data = try? Data(contentsOf: marker),
              let pending = try? JSONDecoder().decode(Pending.self, from: data) else { return nil }
        return pending.documentId
    }
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

    static func apply(_ model: AppModel, document: LibraryDocument, merged: URL, offset: Int, newCount: Int) async throws -> [String] {
        guard applyingDocuments.insert(document.id).inserted else {
            throw fail("Un ajout de pages de ce document est déjà en cours.")
        }
        defer { applyingDocuments.remove(document.id) }
        await model.ocr.beginPageMutation(documentId: document.id)
        var ownsPendingJournal = false
        do {
            try Task.checkCancellation()
            let current = model.storage.url(for: document.id)
            // PDFPool prend un verrou pendant le rendu : l'attendre hors du MainActor, avant la mutation.
            await Task.detached { PDFPool.release(current) }.value
            try Task.checkCancellation()
            guard !AITaskCenter.shared.jobs.contains(where: { $0.key.contains(document.id) }),
                  DocumentAnalysisService.shared.progress?.documentId != document.id else {
                throw fail("Une lecture IA a commencé pendant l'attente : réessayer après sa fin.")
            }
            guard !fm.fileExists(atPath: marker.path) else {
                throw fail("Un ajout précédent doit être repris avant de modifier les documents.")
            }
            ownsPendingJournal = true
            let result = try applyAfterReadersStop(model, document: document, merged: merged,
                                                    offset: offset, newCount: newCount)
            await model.ocr.endPageMutation(documentId: document.id)
            return result
        } catch {
            // Un journal durable en erreur garde le document fermé jusqu'à la reprise.
            if !ownsPendingJournal || !fm.fileExists(atPath: marker.path) {
                await model.ocr.endPageMutation(documentId: document.id)
            }
            throw error
        }
    }

    private static func applyAfterReadersStop(_ model: AppModel, document: LibraryDocument,
                                              merged: URL, offset: Int, newCount: Int) throws -> [String] {
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
        guard let layoutVersion = try model.database.layoutVersion(documentId: document.id) else {
            throw fail("Le document ou les pages à ajouter ont changé. Aucun ajout effectué.")
        }
        // Journal v3 : la même correspondance sert à la base, aux fichiers, au rapport, aux brouillons et aux cartes.
        let mapping = try PageMapping(oldCount: document.pageCount, newCount: newCount,
                                      targets: (0..<document.pageCount).map { $0 + offset })
        var p = Pending(documentId: document.id, offset: offset, oldCount: document.pageCount,
                        oldSize: document.fileSize, newCount: newCount,
                        newSize: Int64(try merged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0),
                        stage: "prepared", version: 3, transaction: UUID().uuidString,
                        oldHash: try DocumentImporter.sha256(of: current),
                        newHash: try DocumentImporter.sha256(of: merged),
                        hasReport: false, mapping: mapping, expectedLayoutVersion: layoutVersion,
                        cardTargets: originalCardPages.mapValues { mapping.target(of: $0) },
                        cardSources: originalCardPages)
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
                // RET-048 (#74) : comme les brouillons et les lectures IA, une page hors du document arrête l'ajout
                // avant le journal ; un rapport déjà incohérent ne doit pas être décalé en silence.
                guard value.pages.keys.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) else {
                    throw fail("Le rapport d'analyse porte une page inattendue : ajout arrêté sans modification.")
                }
                value.pages = Dictionary(uniqueKeysWithValues: value.pages.compactMap { index, page in
                    guard let target = mapping.target(of: index) else { return nil } // Original gardé dans la copie.
                    var moved = page
                    moved.source = target
                    return (target, moved)
                })
                try bytes.write(to: work.appendingPathComponent("original-report.json"), options: .atomic)
                try JSONEncoder().encode(value).write(to: work.appendingPathComponent("report.json"), options: .atomic)
                p.hasReport = true
            }
            // Brouillons de notes : même schéma que le rapport, valeur finale préparée puis installée.
            // Un fichier illisible n'est pas un brouillon lisible : il reste en place, sans bloquer l'ajout.
            let draftsFile = NoteDraftStore.shared.url(documentId: document.id)
            if let bytes = try? Data(contentsOf: draftsFile), let drafts = try? NoteDraftStore.decode(bytes) {
                guard drafts.keys.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) else {
                    throw fail("Un brouillon de note porte une page inattendue : ajout arrêté sans modification.")
                }
                try bytes.write(to: work.appendingPathComponent("original-drafts.json"), options: .atomic)
                try NoteDraftStore.encode(NoteDraftStore.remapped(drafts, with: mapping))
                    .write(to: work.appendingPathComponent("drafts.json"), options: .atomic)
                p.hasDrafts = true
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
        let mapping = try Self.mapping(of: p)
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
                // Page retirée : pas de fichier installé ; l'original reste dans la copie de l'opération (original-files).
                guard let target = mapping.target(of: page) else { continue }
                name = "\(stem[..<dash])-\(target).md"
            }
            try fm.copyItem(at: url, to: prepared.appendingPathComponent(name))
        }
    }

    private static func complete(_ p: Pending, model: AppModel) throws {
        let work = try workspace(p)
        guard model.persistentStorageAvailable, model.review.persistentStorageAvailable,
              p.oldCount > 0, p.version == 2 || p.version == 3, let oldHash = p.oldHash, let newHash = p.newHash,
              let hasReport = p.hasReport else {
            throw fail("Journal incomplet : reprise arrêtée sans effacer les données.")
        }
        let mapping = try Self.mapping(of: p)
        let cardPages: [Int64: Int?]
        if p.version == 3 {
            guard let targets = p.cardTargets, let sources = p.cardSources, p.expectedLayoutVersion != nil else {
                throw fail("Journal incomplet : reprise arrêtée sans effacer les données.")
            }
            // Même inventaire de cartes, et chaque cible = image exacte de sa page d'origine : `nil` seulement si
            // cette page est retirée (jamais lors d'un simple ajout).
            guard Set(targets.keys) == Set(sources.keys),
                  sources.allSatisfy({ id, page in page >= 0 && page < p.oldCount && targets[id] == mapping.target(of: page) }) else {
                throw fail("Pages de cartes invalides dans le journal.")
            }
            // Inventaire : toute carte encore liée à une page de ce document doit figurer dans le journal ; sinon
            // elle garderait une page devenue fausse. (Une carte déjà détachée par la reprise n'y figure plus.)
            guard Set(try model.review.store.sourcePages(documentId: p.documentId).keys).isSubset(of: sources.keys) else {
                throw fail("Une carte du document manque au journal : reprise arrêtée sans modification.")
            }
            cardPages = targets
        } else {
            guard p.newCount > p.oldCount, p.offset >= 0, p.offset <= p.newCount - p.oldCount, let pages = p.cardPages else {
                throw fail("Journal incomplet : reprise arrêtée sans effacer les données.")
            }
            cardPages = pages.mapValues { $0 }
        }
        // Une carte ne peut viser qu'une ancienne page gardée (jamais une page insérée ni hors du document).
        let kept = Set(mapping.targets.compactMap { $0 })
        guard cardPages.values.allSatisfy({ $0.map(kept.contains) ?? (p.version == 3) }) else {
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
        if p.version == 3, let expectedVersion = p.expectedLayoutVersion, let editId = p.transaction {
            // Reconnu par son identifiant d'opération : une reprise ne l'applique jamais deux fois.
            try model.database.remapPages(documentId: p.documentId, mapping: mapping, editId: editId,
                                          kind: mapping.removed.isEmpty ? .insertion : .removal,
                                          expectedVersion: expectedVersion, fileSize: p.newSize)
        } else {
            try model.database.shiftPages(documentId: p.documentId, by: p.offset,
                                          pageCount: p.newCount, fileSize: p.newSize, expectedPageCount: p.oldCount)
        }
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
        try hit("drafts.before")
        if p.hasDrafts == true {
            // Valeur finale préparée : la réécrire à chaque reprise ne décale jamais deux fois.
            let live = NoteDraftStore.shared.url(documentId: p.documentId)
            try fm.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: work.appendingPathComponent("drafts.json")).write(to: live, options: .atomic)
        }
        try hit("drafts.after")
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
            if p.version == 2 || p.version == 3 {
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
