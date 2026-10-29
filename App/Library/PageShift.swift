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
        /// v3 (S2/S3) : type d'opération (`nil` = ajout, journaux écrits avant), cartes détachées par une suppression
        /// (archivées avec leur page) et plan d'une restauration (recalculé et comparé dans la transaction).
        var kind: String? = nil
        var detachedCards: [Int64: Int]? = nil
        var restoration: AppDatabase.RestorationPlan? = nil
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
    private nonisolated static func fail(_ text: String) -> NSError {
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

    /// Une opération sur les pages d'un document (#49) : toutes passent par le même journal v3 rejouable.
    enum Operation {
        /// Pages ajoutées (`merged` = PDF complet préparé par l'appelant ; `offset` pages avant les anciennes).
        case insertion(merged: URL, offset: Int, newCount: Int)
        /// Pages retirées (indices de base 0) ; gardées 30 jours dans la copie de l'opération.
        case removal(Set<Int>)
        /// Pages d'une suppression remises en place (`archiveId` = identifiant de la suppression).
        case restoration(archiveId: String)
    }

    /// Durée de conservation des copies d'opération (suppressions restaurables, copies des ajouts) : décision de
    /// NOxygen59 du 29/10/2026. La purge a lieu au lancement suivant l'échéance, pas exactement à J+30.
    static let retention: TimeInterval = 30 * 24 * 3600

    /// Fiche de la copie d'une opération (`PageShift/<opération>/manifest.json`) : sert à la purge et au stockage.
    struct Manifest: Codable {
        var editId: String
        var documentId: String
        var kind: String
        var createdAt: Date
    }

    static func apply(_ model: AppModel, document: LibraryDocument, merged: URL, offset: Int, newCount: Int) async throws -> [String] {
        try await run(model, document: document, .insertion(merged: merged, offset: offset, newCount: newCount))
    }

    static func removePages(_ model: AppModel, document: LibraryDocument, pages: Set<Int>) async throws {
        _ = try await run(model, document: document, .removal(pages))
    }

    static func restorePages(_ model: AppModel, document: LibraryDocument, archiveId: String) async throws {
        _ = try await run(model, document: document, .restoration(archiveId: archiveId))
    }

    /// Une opération de pages à la fois par document (ajout, suppression, restauration ; le remplacement Drive
    /// vérifie aussi `isBusy`). Le document ne doit pas être ouvert dans le lecteur : ses écritures tardives
    /// (notes, encre, brouillons, position) viseraient l'ancienne numérotation (revue Codex R6).
    static func isBusy(_ documentId: String) -> Bool {
        applyingDocuments.contains(documentId) || pendingDocumentId == documentId
    }

    private static func run(_ model: AppModel, document: LibraryDocument, _ operation: Operation) async throws -> [String] {
        guard model.openDocumentId != document.id else {
            throw fail("Ferme le document avant de modifier ses pages.")
        }
        guard applyingDocuments.insert(document.id).inserted else {
            throw fail("Une modification des pages de ce document est déjà en cours.")
        }
        defer { applyingDocuments.remove(document.id) }
        await model.ocr.beginPageMutation(documentId: document.id)
        var ownsPendingJournal = false
        var built: URL?
        defer { if let built { try? fm.removeItem(at: built.deletingLastPathComponent()) } }
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
                throw fail("Une modification précédente des pages doit être reprise avant de modifier les documents.")
            }
            // Suppression et restauration : le nouveau PDF est fabriqué ici, hors du fil principal.
            var plan: AppDatabase.RestorationPlan?
            var merged: URL
            switch operation {
            case .insertion(let url, _, _):
                merged = url
            case .removal(let pages):
                let mapping = try PageMapping.removal(oldCount: document.pageCount, removing: pages)
                merged = try await buildPDF(current: current, archive: nil, mapping: mapping, plan: nil)
                built = merged
            case .restoration(let archiveId):
                let restoring = try model.database.restorationPlan(documentId: document.id, archiveId: archiveId)
                let archivePDF = support.appendingPathComponent("PageShift/\(archiveId)/original.pdf")
                guard UUID(uuidString: archiveId) != nil, fm.fileExists(atPath: archivePDF.path) else {
                    throw fail("La copie de ces pages n'existe plus : restauration impossible.")
                }
                merged = try await buildPDF(current: current, archive: archivePDF, mapping: restoring.mapping, plan: restoring)
                built = merged
                plan = restoring
            }
            try Task.checkCancellation()
            ownsPendingJournal = true
            let result = try prepareAndComplete(model, document: document, operation, merged: merged, plan: plan)
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

    /// Nouveau PDF : pages actuelles gardées à leur nouvelle place ; pour une restauration, pages reprises de la copie
    /// de la suppression (`archive`). Fichier temporaire privé, effacé après l'opération.
    private nonisolated static func buildPDF(current: URL, archive: URL?, mapping: PageMapping,
                                             plan: AppDatabase.RestorationPlan?) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard let source = PDFDocument(url: current), source.pageCount == mapping.oldCount else {
                throw fail("Le PDF du document a changé : aucune modification des pages.")
            }
            let saved = archive.flatMap { PDFDocument(url: $0) }
            let restored = Dictionary(uniqueKeysWithValues: (plan?.positions ?? [:]).map { ($1, $0) })
            let kept = Dictionary(uniqueKeysWithValues: mapping.targets.enumerated().compactMap { old, new in new.map { ($0, old) } })
            let out = PDFDocument()
            for position in 0..<mapping.newCount {
                var page: PDFPage?
                if let old = kept[position] {
                    page = source.page(at: old)?.copy() as? PDFPage
                } else if let id = restored[position], let index = plan?.originalIndices[id] {
                    page = saved?.page(at: index)?.copy() as? PDFPage
                }
                guard let page else { throw fail("Une page n'a pas pu être lue : aucune modification des pages.") }
                out.insert(page, at: out.pageCount)
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PageEdit-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("merged.pdf")
            guard out.write(to: url) else { throw fail("Le nouveau PDF n'a pas pu être écrit : aucune modification des pages.") }
            return url
        }.value
    }

    private static func prepareAndComplete(_ model: AppModel, document: LibraryDocument, _ operation: Operation,
                                           merged: URL, plan: AppDatabase.RestorationPlan?) throws -> [String] {
        guard model.persistentStorageAvailable, model.review.persistentStorageAvailable else {
            throw fail("Bases persistantes indisponibles : aucune modification des pages.")
        }
        guard !fm.fileExists(atPath: marker.path) else {
            throw fail("Une modification précédente des pages doit être reprise avant de modifier les documents.")
        }
        let mapping: PageMapping, offset: Int, kind: AppDatabase.PageEditKind
        switch operation {
        case .insertion(_, let shift, let newCount):
            guard newCount > document.pageCount, shift >= 0, shift <= newCount - document.pageCount else {
                throw fail("Le document ou les pages à ajouter ont changé. Aucun ajout effectué.")
            }
            mapping = try PageMapping(oldCount: document.pageCount, newCount: newCount,
                                      targets: (0..<document.pageCount).map { $0 + shift })
            offset = shift
            kind = .insertion
        case .removal(let pages):
            mapping = try PageMapping.removal(oldCount: document.pageCount, removing: pages)
            offset = 0
            kind = .removal
        case .restoration(let archiveId):
            // Le plan a servi à fabriquer le PDF : il doit être encore exact (rien n'a changé pendant la fabrication).
            guard let plan, try model.database.restorationPlan(documentId: document.id, archiveId: archiveId) == plan else {
                throw fail("Le document a changé pendant la préparation : aucune restauration effectuée.")
            }
            mapping = plan.mapping
            offset = 0
            kind = .restoration
        }
        guard safeName(document.id), document.pageCount > 0,
              try model.database.document(id: document.id)?.pageCount == document.pageCount,
              PDFDocument(url: model.storage.url(for: document.id))?.pageCount == document.pageCount,
              PDFDocument(url: merged)?.pageCount == mapping.newCount else {
            throw fail("Le document ou ses pages ont changé. Aucune modification des pages.")
        }
        let current = model.storage.url(for: document.id)
        let originalCardPages = try model.review.store.sourcePages(documentId: document.id)
        guard originalCardPages.values.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) else {
            throw fail("Une carte porte une page inattendue : rien n'est modifié.")
        }
        guard let layoutVersion = try model.database.layoutVersion(documentId: document.id) else {
            throw fail("Le document a changé. Aucune modification des pages.")
        }
        // Journal v3 : la même correspondance sert à la base, aux fichiers, au rapport, aux brouillons et aux cartes.
        let targets = originalCardPages.mapValues { mapping.target(of: $0) }
        var p = Pending(documentId: document.id, offset: offset, oldCount: document.pageCount,
                        oldSize: document.fileSize, newCount: mapping.newCount,
                        newSize: Int64(try merged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0),
                        stage: "prepared", version: 3, transaction: UUID().uuidString,
                        oldHash: try DocumentImporter.sha256(of: current),
                        newHash: try DocumentImporter.sha256(of: merged),
                        hasReport: false, mapping: mapping, expectedLayoutVersion: layoutVersion,
                        cardTargets: targets, cardSources: originalCardPages, kind: kind.rawValue,
                        detachedCards: originalCardPages.filter { targets[$0.key] == .some(nil) },
                        restoration: plan)
        let work = try workspace(p)
        let archive = plan.map { support.appendingPathComponent("PageShift/\($0.archiveId)", isDirectory: true) }
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            try JSONEncoder().encode(Manifest(editId: p.transaction!, documentId: document.id, kind: kind.rawValue, createdAt: Date()))
                .write(to: work.appendingPathComponent("manifest.json"), options: .atomic)
            try fm.copyItem(at: current, to: work.appendingPathComponent("original.pdf"))
            try fm.copyItem(at: merged, to: work.appendingPathComponent("merged.pdf"))
            try prepareFiles(p, work: work, archive: archive)
            let report = DocumentAnalysisService.folder.appendingPathComponent(document.id + ".json")
            if fm.fileExists(atPath: report.path) {
                let bytes = try Data(contentsOf: report)
                var value = try JSONDecoder().decode(DocumentAnalysis.self, from: bytes)
                guard value.documentId == document.id else { throw fail("Rapport associé à un autre document.") }
                // RET-048 (#74) : comme les brouillons et les lectures IA, une page hors du document arrête l'opération
                // avant le journal ; un rapport déjà incohérent ne doit pas être décalé en silence.
                guard value.pages.keys.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) else {
                    throw fail("Le rapport d'analyse porte une page inattendue : rien n'est modifié.")
                }
                // Seules les pages retirées sortent du rapport (décision de NOxygen59) ; l'original reste dans la copie.
                value.pages = Dictionary(uniqueKeysWithValues: value.pages.compactMap { index, page in
                    guard let target = mapping.target(of: index) else { return nil }
                    var moved = page
                    moved.source = target
                    return (target, moved)
                })
                // Restauration : les pages revenues retrouvent leur analyse, gardée dans la copie de la suppression.
                if let plan, let archive, let saved = try? JSONDecoder().decode(DocumentAnalysis.self,
                        from: Data(contentsOf: archive.appendingPathComponent("original-report.json"))), saved.documentId == document.id {
                    for (id, position) in plan.positions {
                        guard let index = plan.originalIndices[id], var page = saved.pages[index] else { continue }
                        page.source = position
                        value.pages[position] = page
                    }
                }
                try bytes.write(to: work.appendingPathComponent("original-report.json"), options: .atomic)
                try JSONEncoder().encode(value).write(to: work.appendingPathComponent("report.json"), options: .atomic)
                p.hasReport = true
            }
            // Brouillons de notes : même schéma que le rapport, valeur finale préparée puis installée.
            // Un fichier illisible n'est pas un brouillon lisible : il reste en place sans bloquer un ajout ; pour une
            // suppression ou une restauration, il arrête l'opération (il serait faux après renumérotation).
            let draftsFile = NoteDraftStore.shared.url(documentId: document.id)
            let draftBytes = try? Data(contentsOf: draftsFile)
            let drafts = draftBytes.flatMap { try? NoteDraftStore.decode($0) }
            if draftBytes != nil, drafts == nil, kind != .insertion {
                throw fail("Le fichier des brouillons de notes est illisible : rien n'est modifié.")
            }
            var restoredDrafts: [Int: String] = [:]
            if let plan, let archive, let bytes = try? Data(contentsOf: archive.appendingPathComponent("original-drafts.json")),
               let saved = try? NoteDraftStore.decode(bytes) {
                for (id, position) in plan.positions {
                    if let index = plan.originalIndices[id], let text = saved[index] { restoredDrafts[position] = text }
                }
            }
            if drafts != nil || !restoredDrafts.isEmpty {
                let current = drafts ?? [:]
                guard current.keys.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) else {
                    throw fail("Un brouillon de note porte une page inattendue : rien n'est modifié.")
                }
                if let draftBytes { try draftBytes.write(to: work.appendingPathComponent("original-drafts.json"), options: .atomic) }
                try NoteDraftStore.encode(NoteDraftStore.remapped(current, with: mapping).merging(restoredDrafts) { live, _ in live })
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

    private static func prepareFiles(_ p: Pending, work: URL, archive: URL?) throws {
        let mapping = try Self.mapping(of: p)
        let source = DocumentAnalysisService.folder.appendingPathComponent(p.documentId, isDirectory: true)
        let prepared = work.appendingPathComponent("files", isDirectory: true)
        try fm.createDirectory(at: prepared, withIntermediateDirectories: true)
        if fm.fileExists(atPath: source.path) {
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
        // Restauration : lectures IA des pages revenues, reprises de la copie de la suppression.
        guard let plan = p.restoration, let archive else { return }
        let saved = archive.appendingPathComponent("original-files", isDirectory: true)
        guard fm.fileExists(atPath: saved.path) else { return }
        let byIndex = Dictionary(uniqueKeysWithValues: plan.originalIndices.compactMap { id, index in plan.positions[id].map { (index, $0) } })
        for url in try fm.contentsOfDirectory(at: saved, includingPropertiesForKeys: nil) {
            let stem = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "md", let dash = stem.lastIndex(of: "-"),
                  let page = Int(stem[stem.index(after: dash)...]), let position = byIndex[page] else { continue }
            let target = prepared.appendingPathComponent("\(stem[..<dash])-\(position).md")
            guard !fm.fileExists(atPath: target.path) else { throw fail("Lecture IA en double à la restauration : rien n'est modifié.") }
            try fm.copyItem(at: url, to: target)
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
            // elle garderait une page devenue fausse. (Une carte déjà détachée par la reprise n'y figure plus ; une carte
            // déjà rattachée par une restauration interrompue y figure par son plan.)
            let expected = Set(sources.keys).union(p.restoration?.cards.keys ?? [:].keys)
            guard Set(try model.review.store.sourcePages(documentId: p.documentId).keys).isSubset(of: expected) else {
                throw fail("Une carte du document manque au journal : reprise arrêtée sans modification.")
            }
            // Type d'opération cohérent avec la correspondance, les cartes détachées et le plan de restauration.
            let kind = AppDatabase.PageEditKind(rawValue: p.kind ?? "insertion")
            let expectedDetached = sources.filter { targets[$0.key] == .some(nil) }
            let detached = p.detachedCards ?? [:]
            let coherent: Bool
            switch kind {
            case .insertion?: coherent = mapping.removed.isEmpty && p.restoration == nil && detached.isEmpty
            case .removal?: coherent = p.restoration == nil && detached == expectedDetached
            case .restoration?: coherent = p.restoration?.mapping == mapping && mapping.removed.isEmpty && detached.isEmpty
            case nil: coherent = false
            }
            guard coherent else { throw fail("Type d'opération incohérent dans le journal.") }
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
                                          kind: AppDatabase.PageEditKind(rawValue: p.kind ?? "insertion") ?? .insertion,
                                          expectedVersion: expectedVersion, fileSize: p.newSize,
                                          detachedCards: p.detachedCards ?? [:], restoring: p.restoration)
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
        // Restauration : cartes détachées par la suppression, rattachées à leur page revenue si toujours sans page.
        if let plan = p.restoration { try model.review.store.reattachSourcePages(documentId: p.documentId, pages: plan.cards) }
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

    // MARK: - Copies des opérations : conservation 30 jours, purge, place occupée

    private static var copiesRoot: URL { support.appendingPathComponent("PageShift", isDirectory: true) }

    /// Copies d'opération présentes (suppressions restaurables, copies des ajouts), avec leur fiche si elle existe.
    /// Les copies des ajouts faites avant les fiches (#49) n'en ont pas : leur date de création sert d'échéance.
    static func copies() -> [(folder: URL, manifest: Manifest?, created: Date)] {
        guard let folders = try? fm.contentsOfDirectory(at: copiesRoot, includingPropertiesForKeys: [.creationDateKey]) else { return [] }
        return folders.filter { UUID(uuidString: $0.lastPathComponent) != nil }.map { folder in
            let manifest = try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
            let created = manifest?.createdAt ?? (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return (folder, manifest, created)
        }
    }

    /// Place réelle des copies (PDF complets compris), pour un document ou pour toutes.
    static func copiesSize(documentId: String? = nil) -> Int64 {
        copies().filter { documentId == nil || $0.manifest?.documentId == documentId }.reduce(0) { total, copy in
            let files = fm.enumerator(at: copy.folder, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { $0 as? URL } ?? []
            return total + files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
    }

    /// Copies arrivées à échéance effacées : au lancement, après une reprise réussie, jamais pendant une opération ni
    /// avec un journal en attente. Rejouable : la base d'abord (archive marquée effacée), puis le dossier ; une coupure
    /// entre les deux refait simplement les deux au lancement suivant.
    static func purgeExpired(_ model: AppModel, now: Date = Date()) {
        guard !fm.fileExists(atPath: marker.path), applyingDocuments.isEmpty, model.persistentStorageAvailable else { return }
        for copy in copies() where now.timeIntervalSince(copy.created) >= retention {
            do {
                if copy.manifest?.kind == AppDatabase.PageEditKind.removal.rawValue {
                    try model.database.purgeArchive(editId: copy.folder.lastPathComponent, at: now)
                }
                try hit("purge.database")
                try fm.removeItem(at: copy.folder)
                Diagnostics.log("pages : copie \(copy.folder.lastPathComponent) effacée après 30 jours", "pages")
            } catch {
                Diagnostics.error("pages : copie \(copy.folder.lastPathComponent) non effacée — \(error.localizedDescription)", "pages")
            }
        }
    }

    /// Document supprimé définitivement : ses copies partent avec lui (sa base est déjà effacée par cascade).
    static func removeCopies(documentId: String) {
        for copy in copies() where copy.manifest?.documentId == documentId {
            try? fm.removeItem(at: copy.folder)
        }
    }

    private static func block(_ model: AppModel, _ error: Error) {
        model.openDocumentId = nil
        model.storageRecoveryError = "La modification des pages doit être reprise avant de continuer. " + error.localizedDescription
        Diagnostics.error(model.storageRecoveryError!, "pages")
    }

    static func reconcile(_ model: AppModel) {
        guard fm.fileExists(atPath: marker.path) else {
            model.storageRecoveryError = nil
            purgeExpired(model)
            return
        }
        do {
            guard model.persistentStorageAvailable, model.review.persistentStorageAvailable else {
                throw fail("Bases persistantes indisponibles : journal conservé pour la reprise.")
            }
            let p = try JSONDecoder().decode(Pending.self, from: Data(contentsOf: marker))
            if p.version == 2 || p.version == 3 {
                try complete(p, model: model)
                purgeExpired(model)
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
