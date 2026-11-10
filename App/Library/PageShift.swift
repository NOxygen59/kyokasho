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
        /// Copies originales inventoriées avant le journal ; absent des anciens journaux.
        var sealedArchive: Bool? = nil
        /// v3 (C2.3) : remplacement d'un cours Drive. `newDocumentId` = identifiant final (hash du
        /// nouveau PDF, décidé avant le journal), `newRevision` = révision Drive à poser après la
        /// bascule, `newSourcePath` = fichier téléchargé qui permet de finir la copie du PDF si l'app
        /// s'est arrêtée avant la bascule. `nil` dans tous les autres journaux.
        var newDocumentId: String? = nil
        var newRevision: String? = nil
        var newSourcePath: String? = nil
    }

    /// Correspondance d'un journal : v3 la porte ; v2 la décrit par le décalage (pages ajoutées avant les anciennes).
    static func mapping(of p: Pending) throws -> PageMapping {
        if p.version == 3 {
            guard let mapping = p.mapping, mapping.oldCount == p.oldCount, mapping.newCount == p.newCount else {
                throw fail(String(localized: "Correspondance des pages absente du journal : reprise arrêtée sans effacer les données."))
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
    /// Journal déchiffré, quel que soit son type (modification de pages ou remplacement de cours).
    /// Un journal illisible reste en place : les guards le voient par son fichier.
    private static var pending: Pending? {
        guard let data = try? Data(contentsOf: marker),
              let pending = try? JSONDecoder().decode(Pending.self, from: data) else { return nil }
        return pending
    }
    static var pendingDocumentId: String? { pending?.documentId }
    /// Bascule de cours Drive en attente (`kind = "replacement"`, C2.3) : finie par `reconcile` au lancement.
    static var pendingReplacement: Pending? { pending.flatMap { $0.kind == "replacement" ? $0 : nil } }
    private nonisolated static func fail(_ text: String) -> NSError {
        NSError(domain: "Kyokasho.PageShift", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    private static func hit(_ name: String) throws { try checkpoint?(name) }
    private static func safeName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }
    private static func workspace(_ p: Pending) throws -> URL {
        guard let token = p.transaction, UUID(uuidString: token) != nil, safeName(p.documentId) else {
            throw fail(String(localized: "Journal d'ajout de pages invalide : fichiers conservés."))
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
        /// Empreintes des originaux, répertoires compris (valeur "directory"). nil = ancien format non vérifiable.
        var originalHashes: [String: String]? = nil
    }

    /// Inventaire calculé depuis le disque, sans suivre de lien. Comparer les ensembles distingue une absence
    /// normale d'un fichier perdu ; les clés du manifeste ne servent jamais à construire un chemin à lire.
    private static func originalInventory(_ folder: URL) throws -> [String: String] {
        var hashes: [String: String] = [:]
        func visit(_ url: URL, relative: String) throws {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            guard values.isSymbolicLink != true else { throw fail(String(localized: "Lien inattendu dans une archive de pages.")) }
            if values.isDirectory == true {
                hashes[relative] = "directory"
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    try visit(child, relative: relative + "/" + child.lastPathComponent)
                }
            } else {
                guard values.isRegularFile == true else { throw fail(String(localized: "Fichier d'archive inattendu.")) }
                hashes[relative] = try DocumentImporter.sha256(of: url)
            }
        }
        for url in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasPrefix("original") {
            try visit(url, relative: url.lastPathComponent)
        }
        return hashes
    }

    /// Une ancienne copie sans inventaire est conservée, mais ne peut pas promettre une restauration complète.
    private static func validateArchive(_ folder: URL, editId: String, documentId: String) throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        guard manifest.editId == editId, manifest.documentId == documentId,
              let hashes = manifest.originalHashes, hashes["original.pdf"] != nil,
              try originalInventory(folder) == hashes else {
            throw fail(String(localized: "Copie de pages incomplète ou altérée : restauration arrêtée, fichiers conservés."))
        }
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

    /// Une opération de pages en cours sur n'importe quel document (remplacement Drive compris) ou une reprise
    /// en attente (journal `page-shift.json`, P3 n°7 de la revue R2) : la garde réciproque de
    /// `LibraryBackupService.backup` (C2.7). La sauvegarde vérifie aussi le journal avant ce garde ; le compter
    /// ici fait de la garde croisée une condition unique, indépendante de l'ordre des « guard ».
    static var operationInProgress: Bool { !applyingDocuments.isEmpty || pendingDocumentId != nil }

    /// Les clés IA portent l'identifiant entre séparateurs. Refuser les nouveaux travaux tant que le PDF ou
    /// ses indices sont réservés, y compris pendant l'attente d'un importeur Drive détaché.
    /// Remplacement Drive (revue R2 P3 n°10) : le **nouvel** identifiant est réservé lui aussi —
    /// son PDF et son dossier de fichiers apparaissent pendant les déplacements de la bascule
    /// (reprise au lancement comprise, via le journal en attente).
    static func blocksAI(jobKey: String) -> Bool {
        var ids = applyingDocuments.union(pendingDocumentId.map { [$0] } ?? [])
        if let pending = pendingReplacement, let newId = pending.newDocumentId { ids.insert(newId) }
        return jobKey.split(separator: "|").contains { ids.contains(String($0)) }
    }

    /// Le remplacement Drive utilise le même périmètre d'exclusion que les modifications de pages.
    ///
    /// C2.3 : quand un cours est remplacé, le journal suit le protocole des modifications de pages
    /// (même fichier `page-shift.json`, écrit **avant** toute mutation, rejoué au lancement). La
    /// bascule SQL — atomique et dans une seule transaction — applique d'abord la partie base
    /// (`DocumentImporter.replace` → `rekeyDocument`, OCR effacé, cartes suivies), puis
    /// ``completeReplacement`` déplace les fichiers nommés par l'identifiant. Une interruption
    /// quelconque (crash compris) laisse un journal rejoué au lancement suivant, sans perte ni
    /// double déplacement. `replacement = nil` : changement de révision du même fichier, aucune
    /// bascule, aucun journal (comportement inchangé de la réserve du document).
    static func withDriveReplacement<T>(_ model: AppModel, documentId: String,
                                       replacement: DriveReplacement? = nil,
                                       operation: () async throws -> T) async throws -> T {
        guard model.openDocumentId != documentId else { throw fail(String(localized: "Ferme le document avant de le remplacer.")) }
        // Comme PageShift.run : la sauvegarde complète refuse de démarrer pendant une opération de pages (garde
        // dans les deux sens, C2.7) ; ici aussi, démarrer pendant une sauvegarde écraserait des fichiers copiés.
        guard !LibraryBackupService.inProgress else { throw fail(String(localized: "Sauvegarde en cours : réessaie après sa fin.")) }
        guard !fm.fileExists(atPath: marker.path), applyingDocuments.insert(documentId).inserted else {
            throw fail(String(localized: "Une modification des pages est déjà en cours ou doit être reprise."))
        }
        var ownsReplacementJournal = false
        var reservedNewId: String?
        defer {
            applyingDocuments.remove(documentId)
            // P3 n°10 (revue R2) : le fichier du nouvel identifiant et son dossier de lectures IA
            // apparaissent pendant les déplacements ; il quitte la réserve avec le document,
            // failure compris (une réserve jamais levée bloquerait ses tâches IA à jamais).
            if let newId = reservedNewId { applyingDocuments.remove(newId) }
        }
        await model.drainWrites()
        await model.ocr.beginPageMutation(documentId: documentId)
        do {
            let current = model.storage.url(for: documentId)
            await Task.detached { PDFPool.release(current) }.value
            try Task.checkCancellation()
            guard model.openDocumentId != documentId,
                  !AITaskCenter.shared.jobs.contains(where: { $0.key.contains(documentId) }),
                  DocumentAnalysisService.shared.progress?.documentId != documentId else {
                throw fail(String(localized: "Le document est ouvert ou une lecture IA est en cours : remplacement arrêté."))
            }
            if let replacement {
                let journal = try replacementPending(documentId: documentId, replacement: replacement, model: model)
                // La propriété du journal est posée AVANT l'écriture (P3 n°6, revue R2) : une coupure
                // pendant `save` — le journal est écrit au point `journal.after` — doit retrouver
                // dans le catch le droit de le retirer (le document d'origine est encore en base).
                ownsReplacementJournal = true
                // P3 n°10 : le nouvel identifiant devient réservé aux tâches IA dès l'écriture
                // du journal, avant que ses fichiers et son PDF n'apparaissent dans la bascule.
                reservedNewId = replacement.newDocumentId
                applyingDocuments.insert(reservedNewId!)
                try save(journal) // Journal avant toute mutation DAO : c'est la seule écriture encore annulable.
            }
            let result = try await operation()
            try synchronizeCopyOwners(model.database)
            PrintedPageNumbers.set(try model.database.printedNumbers())
            // Quand aucun remplacement n'est journalé, ces étapes-là ne connaissent pas `complete` :
            // la bascule du même fichier n'efface rien (C2.1 ne s'applique que sur changement d'identifiant).
            let pending = pendingReplacement
            if let p = pending, ownsReplacementJournal {
                try complete(p, model: model)
                // N1 (revue R2) : `complete` a retiré le journal à sa dernière étape — la
                // réservation du nouvel identifiant est donc finie. La lever dès ici : le
                // `defer` ne la lèverait qu'au retour, trop tard pour le gardien des tâches
                // IA qui refuse alors la relance de la lecture IA à chaque fois.
                if let newId = reservedNewId { applyingDocuments.remove(newId) }
            }
            await model.ocr.endPageMutation(documentId: documentId)
            if let p = pending, ownsReplacementJournal {
                resumeAIScanAfterReplacement(newId: p.newDocumentId, model: model)
            }
            return result
        } catch {
            // L'invariant garantit le repli : tant que le document d'origine existe en base, la bascule
            // SQL n'a pas été appliquée et aucune mutation (OCR, cartes, fichiers) n'a eu lieu — le
            // journal est retiré et la mise à jour reste relançable. S'il a disparu (crash au milieu
            // de la bascule) : journal conservé, reprise au lancement (`reconcile`).
            if ownsReplacementJournal, fm.fileExists(atPath: marker.path),
               (try? model.database.document(id: documentId)).flatMap({ $0 }) != nil {
                try? fm.removeItem(at: marker)
            } else if fm.fileExists(atPath: marker.path), ownsReplacementJournal {
                block(model, error)
            }
            await model.ocr.endPageMutation(documentId: documentId)
            throw error
        }
    }

    private static func run(_ model: AppModel, document: LibraryDocument, _ operation: Operation) async throws -> [String] {
        guard model.openDocumentId != document.id else {
            throw fail(String(localized: "Ferme le document avant de modifier ses pages."))
        }
        guard !LibraryBackupService.inProgress else { throw fail(String(localized: "Sauvegarde en cours : réessaie après sa fin.")) }
        guard applyingDocuments.insert(document.id).inserted else {
            throw fail(String(localized: "Une modification des pages de ce document est déjà en cours."))
        }
        defer { applyingDocuments.remove(document.id) }
        await model.drainWrites()
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
                throw fail(String(localized: "Une lecture IA a commencé pendant l'attente : réessayer après sa fin."))
            }
            guard !fm.fileExists(atPath: marker.path) else {
                throw fail(String(localized: "Une modification précédente des pages doit être reprise avant de modifier les documents."))
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
                    throw fail(String(localized: "La copie de ces pages n'existe plus : restauration impossible."))
                }
                try validateArchive(archivePDF.deletingLastPathComponent(), editId: archiveId, documentId: document.id)
                merged = try await buildPDF(current: current, archive: archivePDF, mapping: restoring.mapping, plan: restoring)
                built = merged
                plan = restoring
            }
            try hit("build.after")
            try Task.checkCancellation()
            // La fabrication suspend le MainActor : aucune hypothèse d'avant l'attente ne vaut comme verrou.
            guard model.openDocumentId != document.id,
                  !AITaskCenter.shared.jobs.contains(where: { $0.key.contains(document.id) }),
                  DocumentAnalysisService.shared.progress?.documentId != document.id,
                  !fm.fileExists(atPath: marker.path) else {
                throw fail(String(localized: "Le document est occupé après la préparation : aucune modification effectuée."))
            }
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
                throw fail(String(localized: "Le PDF du document a changé : aucune modification des pages."))
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
                guard let page else { throw fail(String(localized: "Une page n'a pas pu être lue : aucune modification des pages.")) }
                out.insert(page, at: out.pageCount)
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PageEdit-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("merged.pdf")
            guard out.write(to: url) else { throw fail(String(localized: "Le nouveau PDF n'a pas pu être écrit : aucune modification des pages.")) }
            return url
        }.value
    }

    private static func prepareAndComplete(_ model: AppModel, document: LibraryDocument, _ operation: Operation,
                                           merged: URL, plan: AppDatabase.RestorationPlan?) throws -> [String] {
        guard model.persistentStorageAvailable, model.review.persistentStorageAvailable else {
            throw fail(String(localized: "Bases persistantes indisponibles : aucune modification des pages."))
        }
        guard !fm.fileExists(atPath: marker.path) else {
            throw fail(String(localized: "Une modification précédente des pages doit être reprise avant de modifier les documents."))
        }
        let mapping: PageMapping, offset: Int, kind: AppDatabase.PageEditKind
        switch operation {
        case .insertion(_, let shift, let newCount):
            guard newCount > document.pageCount, shift >= 0, shift <= newCount - document.pageCount else {
                throw fail(String(localized: "Le document ou les pages à ajouter ont changé. Aucun ajout effectué."))
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
                throw fail(String(localized: "Le document a changé pendant la préparation : aucune restauration effectuée."))
            }
            mapping = plan.mapping
            offset = 0
            kind = .restoration
        }
        guard safeName(document.id), document.pageCount > 0,
              try model.database.document(id: document.id)?.pageCount == document.pageCount,
              PDFDocument(url: model.storage.url(for: document.id))?.pageCount == document.pageCount,
              PDFDocument(url: merged)?.pageCount == mapping.newCount else {
            throw fail(String(localized: "Le document ou ses pages ont changé. Aucune modification des pages."))
        }
        let current = model.storage.url(for: document.id)
        let originalCardPages = try model.review.store.sourcePages(documentId: document.id)
        guard originalCardPages.values.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) else {
            throw fail(String(localized: "Une carte porte une page inattendue : rien n'est modifié."))
        }
        guard let layoutVersion = try model.database.layoutVersion(documentId: document.id) else {
            throw fail(String(localized: "Le document a changé. Aucune modification des pages."))
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
            try fm.copyItem(at: current, to: work.appendingPathComponent("original.pdf"))
            try fm.copyItem(at: merged, to: work.appendingPathComponent("merged.pdf"))
            try prepareFiles(p, work: work, archive: archive)
            let report = DocumentAnalysisService.folder.appendingPathComponent(document.id + ".json")
            let savedReport = archive.map { $0.appendingPathComponent("original-report.json") }
            if fm.fileExists(atPath: report.path) || savedReport.map({ fm.fileExists(atPath: $0.path) }) == true {
                let bytes = fm.fileExists(atPath: report.path) ? try Data(contentsOf: report) : nil
                var value = try bytes.map { try JSONDecoder().decode(DocumentAnalysis.self, from: $0) } ?? DocumentAnalysis(documentId: document.id)
                guard value.documentId == document.id else { throw fail(String(localized: "Rapport associé à un autre document.")) }
                // RET-048 (#74) : comme les brouillons et les lectures IA, une page hors du document arrête l'opération
                // avant le journal ; un rapport déjà incohérent ne doit pas être décalé en silence.
                guard value.pages.keys.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) else {
                    throw fail(String(localized: "Le rapport d'analyse porte une page inattendue : rien n'est modifié."))
                }
                // Seules les pages retirées sortent du rapport (décision de NOxygen59) ; l'original reste dans la copie.
                value.pages = Dictionary(uniqueKeysWithValues: value.pages.compactMap { index, page in
                    guard let target = mapping.target(of: index) else { return nil }
                    var moved = page
                    moved.source = target
                    return (target, moved)
                })
                // Restauration : les pages revenues retrouvent leur analyse, gardée dans la copie de la suppression.
                if let plan, let savedReport, fm.fileExists(atPath: savedReport.path) {
                    let saved = try JSONDecoder().decode(DocumentAnalysis.self, from: Data(contentsOf: savedReport))
                    guard saved.documentId == document.id else { throw fail(String(localized: "Rapport archivé associé à un autre document.")) }
                    for (id, position) in plan.positions {
                        guard let index = plan.originalIndices[id], var page = saved.pages[index] else { continue }
                        page.source = position
                        value.pages[position] = page
                    }
                }
                if let bytes { try bytes.write(to: work.appendingPathComponent("original-report.json"), options: .atomic) }
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
                throw fail(String(localized: "Le fichier des brouillons de notes est illisible : rien n'est modifié."))
            }
            var restoredDrafts: [Int: String] = [:]
            if let plan, let archive, fm.fileExists(atPath: archive.appendingPathComponent("original-drafts.json").path) {
                let saved = try NoteDraftStore.decode(Data(contentsOf: archive.appendingPathComponent("original-drafts.json")))
                for (id, position) in plan.positions {
                    if let index = plan.originalIndices[id], let text = saved[index] { restoredDrafts[position] = text }
                }
            }
            if drafts != nil || !restoredDrafts.isEmpty {
                let current = drafts ?? [:]
                guard current.keys.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) else {
                    throw fail(String(localized: "Un brouillon de note porte une page inattendue : rien n'est modifié."))
                }
                if let draftBytes { try draftBytes.write(to: work.appendingPathComponent("original-drafts.json"), options: .atomic) }
                try NoteDraftStore.encode(NoteDraftStore.remapped(current, with: mapping).merging(restoredDrafts) { live, _ in live })
                    .write(to: work.appendingPathComponent("drafts.json"), options: .atomic)
                p.hasDrafts = true
            }
            // F3 : l'archive complète existe et est relue AVANT la transaction. Une reprise ne l'enrichit jamais
            // depuis des données déjà renumérotées ; les empreintes couvrent aussi les brouillons et les lectures IA.
            let manifest = Manifest(editId: p.transaction!, documentId: document.id, kind: kind.rawValue,
                                    createdAt: Date(), originalHashes: try originalInventory(work))
            try JSONEncoder().encode(manifest).write(to: work.appendingPathComponent("manifest.json"), options: .atomic)
            try validateArchive(work, editId: p.transaction!, documentId: document.id)
            p.sealedArchive = true
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
            try fm.copyItem(at: source, to: work.appendingPathComponent("original-files", isDirectory: true))
            for url in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                    throw fail(String(localized: "Lien symbolique inattendu dans les lectures IA."))
                }
                var name = url.lastPathComponent
                let stem = url.deletingPathExtension().lastPathComponent
                if url.pathExtension == "md", let dash = stem.lastIndex(of: "-"), let page = Int(stem[stem.index(after: dash)...]) {
                    guard page >= 0, page < p.oldCount else { throw fail(String(localized: "Lecture IA hors des pages du document : fichiers conservés.")) }
                    // Page retirée : pas de fichier installé ; l'original reste dans la copie de l'opération (original-files).
                    guard let target = mapping.target(of: page) else { continue }
                    name = "\(stem[..<dash])-\(target).md"
                }
                try fm.copyItem(at: url, to: prepared.appendingPathComponent(name))
            }
        } else {
            // Même vide, le dossier existe avant le journal : une reprise ne doit pas archiver les fichiers finaux.
            try fm.createDirectory(at: work.appendingPathComponent("original-files"), withIntermediateDirectories: true)
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
            guard !fm.fileExists(atPath: target.path) else { throw fail(String(localized: "Lecture IA en double à la restauration : rien n'est modifié.")) }
            try fm.copyItem(at: url, to: target)
        }
    }

    private static func complete(_ p: Pending, model: AppModel) throws {
        // C2.3 : un remplacement de cours suit un autre protocole que les modifications de pages
        // (aucun décalage de pages, fusion possible des identifiants, fichiers servis par identifiant)
        // mais le même journal, la même réserve et la même reprise au lancement.
        if p.kind == "replacement" { try completeReplacement(p, model: model); return }
        let work = try workspace(p)
        guard model.persistentStorageAvailable, model.review.persistentStorageAvailable,
              p.oldCount > 0, p.version == 2 || p.version == 3, let oldHash = p.oldHash, let newHash = p.newHash,
              let hasReport = p.hasReport else {
            throw fail(String(localized: "Journal incomplet : reprise arrêtée sans effacer les données."))
        }
        let mapping = try Self.mapping(of: p)
        let cardPages: [Int64: Int?]
        if p.version == 3 {
            guard let targets = p.cardTargets, let sources = p.cardSources, p.expectedLayoutVersion != nil else {
                throw fail(String(localized: "Journal incomplet : reprise arrêtée sans effacer les données."))
            }
            // Même inventaire de cartes, et chaque cible = image exacte de sa page d'origine : `nil` seulement si
            // cette page est retirée (jamais lors d'un simple ajout).
            guard Set(targets.keys) == Set(sources.keys),
                  sources.allSatisfy({ id, page in page >= 0 && page < p.oldCount && targets[id] == mapping.target(of: page) }) else {
                throw fail(String(localized: "Pages de cartes invalides dans le journal."))
            }
            // Inventaire : toute carte encore liée à une page de ce document doit figurer dans le journal ; sinon
            // elle garderait une page devenue fausse. (Une carte déjà détachée par la reprise n'y figure plus ; une carte
            // déjà rattachée par une restauration interrompue y figure par son plan.)
            let expected = Set(sources.keys).union(p.restoration?.cards.keys ?? [:].keys)
            guard Set(try model.review.store.sourcePages(documentId: p.documentId).keys).isSubset(of: expected) else {
                throw fail(String(localized: "Une carte du document manque au journal : reprise arrêtée sans modification."))
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
            guard coherent else { throw fail(String(localized: "Type d'opération incohérent dans le journal.")) }
            cardPages = targets
        } else {
            guard p.newCount > p.oldCount, p.offset >= 0, p.offset <= p.newCount - p.oldCount, let pages = p.cardPages else {
                throw fail(String(localized: "Journal incomplet : reprise arrêtée sans effacer les données."))
            }
            cardPages = pages.mapValues { $0 }
        }
        // Une carte ne peut viser qu'une ancienne page gardée (jamais une page insérée ni hors du document).
        let kept = Set(mapping.targets.compactMap { $0 })
        guard cardPages.values.allSatisfy({ $0.map(kept.contains) ?? (p.version == 3) }) else {
            throw fail(String(localized: "Pages de cartes invalides dans le journal."))
        }
        if p.sealedArchive == true { try validateArchive(work, editId: p.transaction!, documentId: p.documentId) }
        let preparedPDF = work.appendingPathComponent("merged.pdf")
        guard try DocumentImporter.sha256(of: preparedPDF) == newHash else { throw fail(String(localized: "Copie PDF préparée altérée.")) }
        let current = model.storage.url(for: p.documentId)
        let currentHash = try DocumentImporter.sha256(of: current)
        guard currentHash == oldHash || currentHash == newHash else {
            throw fail(String(localized: "Le PDF a changé depuis l'ajout : reprise arrêtée, copies conservées."))
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
        // F5 : l'affichage suit la base pour tous les appelants (ajout compris) et après chaque reprise.
        // Une lecture SQL échouée garde le journal au lieu de publier un cache vide comme un succès.
        PrintedPageNumbers.set(try model.database.printedNumbers())
        try hit("complete.before")
        try fm.removeItem(at: marker) // Échec = journal conservé ; tout est rejouable.
        // Ajout et suppression : le workspace, hors Caches, reste une copie de secours identifiée par son UUID.
        // Restauration : les deux copies devenues inutiles partent maintenant (recette 68).
        discardAfterRestoration(p, model: model)
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

    // MARK: - Remplacement d'un cours Drive (C2.3, DEC-C2 = A)

    /// Conflits « cible déjà présente » (revue R2 P2 n°4, F4) : un fichier d'arrivée déjà présent
    /// n'est **jamais** écrasé, et la donnée de l'ancienne version est mise de côté dans
    /// ``conflictsBase(for:)``, où elle reste récupérable (aucune donnée inatteignable). Le
    /// compteur par document est affiché dans le rapport de fin vu par l'utilisateur
    /// (`checkDriveUpdates`) et consommé une seule fois par ``consumeReplacementConflicts(for:)``.
    static var lastReplacementConflicts: [String: Int] = [:]
    @MainActor static func consumeReplacementConflicts(for documentId: String) -> Int {
        let count = lastReplacementConflicts[documentId] ?? 0
        lastReplacementConflicts[documentId] = nil
        return count
    }
    /// Corrections manuelles mises de côté pour un document remplacé (décision DEC-C3) : lues
    /// dans le dossier de secours (compteur sur le disque, gardé au-delà d'un arrêt), et retirées
    /// une fois rapportées, comme les conflits ; les fichiers de correction restent disponibles
    /// pour la remise (`OCRService.store`).
    static func consumeReplacementCorrections(for documentId: String) -> Int {
        CorrectionAsideStore.shared.consumeTally(documentId: documentId).corrections
    }
    /// Dossier de secours des conflits, par ancien identifiant et par type de donnée
    /// (`Brouillons`, `Lectures-IA`, `Rapport`, `PDF`) : toujours sous le support de l'app,
    /// jamais sous un chemin construit depuis une donnée hypothétique du journal.
    private static func conflictsBase(for documentId: String) -> URL {
        support.appendingPathComponent("Conflits-remplacement", isDirectory: true)
            .appendingPathComponent(documentId, isDirectory: true)
    }
    private static func noteConflict(_ documentId: String) {
        lastReplacementConflicts[documentId, default: 0] += 1
    }

    // MARK: - Corrections de l'ancienne version mises de côté (décision DEC-C3)

    /// Lignes corrigées à la main de l'ancienne version : `rekeyDocument` offre chaque résultat
    /// OCR **avant** l'effacement de son cache (lignes reconnaissables à leur `originalText`).
    /// Décode ici, puis écrit dans `Corrections-remplacement/<identifiant du nouveau document>/`,
    /// jamais écrasé (`CorrectionAsideStore.keep`). Un résultat illisible n'a pas de lignes
    /// lisibles : rien à mettre de côté (ses corrections, s'il y en avait, ne le seraient pas
    /// reconnaissables), la bascule continue ; tous les résultats écrits par l'app décodent.
    nonisolated static func asideCorrections(_ sourceDocumentId: String, _ newDocumentId: String,
                                             _ pageIndex: Int, _ engine: String, _ pageJSON: Data) throws {
        guard let page = try? JSONDecoder().decode(OCRPage.self, from: pageJSON) else { return }
        let entries = page.lines.compactMap { line in
            line.originalText.map { KeptCorrection(original: $0, corrected: line.text) }
        }
        try CorrectionAsideStore.shared.keep(pageIndex: pageIndex, engine: engine, entries: entries,
                                             documentId: newDocumentId, sourceDocumentId: sourceDocumentId)
    }

    /// Dessin d'encre du survivant perdu pendant une fusion (N2, revue R2) : écrit tel quel
    /// (`PKDrawing.dataRepresentation()`) dans `Conflits-remplacement/<ancien identifiant>/Encre/`,
    /// jamais écrasé (`CorrectionAsideStore.keepInk`). Le dessin du livre remplacé reste sur la
    /// page (même règle que la rotation manuelle, P3 n°9) — rien n'est fusionné ni abandonné.
    nonisolated static func asideInkDrawing(_ sourceDocumentId: String, _ pageIndex: Int, _ data: Data) throws {
        try CorrectionAsideStore.shared.keepInk(sourceDocumentId: sourceDocumentId, pageIndex: pageIndex, data: data)
    }

    /// Plan d'un remplacement, calculé et vérifié **avant** l'écriture du journal : il lui faut
    /// l'empreinte du nouveau PDF (identifiant final), son nombre de pages et sa taille, afin qu'une
    /// bascule interrompue puisse être finie au lancement suivant depuis le journal seul. `source`
    /// est le fichier téléchargé de Drive (temporaire ; le journal garde son chemin pour finir une
    /// copie arrêtée — car l'appelant efface son dossier temporaire après sa tâche d'import).
    struct DriveReplacement {
        var source: URL
        var newDocumentId: String
        var pageCount: Int
        var fileSize: Int64
        var driveRevision: String?
    }

    /// Journal d'un remplacement, écrit après les garde-fous mais avant toute mutation de la base.
    /// Réutilise la même forme et le même fichier que les modifications de pages (les garde-fous
    /// existants le voient sans changement), avec `kind = "replacement"` et les champs spécifiques.
    private static func replacementPending(documentId: String, replacement: DriveReplacement, model: AppModel) throws -> Pending {
        guard safeName(documentId), safeName(replacement.newDocumentId) else {
            throw fail(String(localized: "Identifiant de remplacement invalide : remplacement arrêté."))
        }
        guard replacement.newDocumentId != documentId else {
            throw fail(String(localized: "Même fichier : aucun remplacement à journaler."))
        }
        guard replacement.pageCount > 0, replacement.fileSize > 0 else {
            throw fail(String(localized: "La nouvelle version du PDF est illisible : aucun remplacement effectué."))
        }
        guard let old = try model.database.document(id: documentId) else {
            throw fail(String(localized: "Document introuvable : aucun remplacement effectué."))
        }
        guard old.pageCount > 0 else {
            throw fail(String(localized: "Document vide : aucun remplacement effectué."))
        }
        return Pending(documentId: documentId, offset: 0, oldCount: old.pageCount,
                       oldSize: old.fileSize, newCount: replacement.pageCount,
                       newSize: replacement.fileSize, stage: "prepared", version: 3,
                       transaction: UUID().uuidString, oldHash: nil, newHash: nil,
                       hasReport: false, kind: "replacement",
                       newDocumentId: replacement.newDocumentId, newRevision: replacement.driveRevision,
                       newSourcePath: replacement.source.path)
    }

    /// Fin d'une bascule Drive : lancée par ``withDriveReplacement`` après la bascule SQL, et rejouée
    /// par `reconcile` au lancement si l'app s'est arrêtée entre-temps.
    ///
    /// Invariant de reprise : tant que le document d'origine existe en base, la bascule SQL n'a pas
    /// été appliquée (elle est atomique, dans une transaction) et rien n'a été bougé ; s'il a
    /// disparu, chaque étape suivante est idempotente — un déplacement refusé si la cible existe
    /// (« jamais écraser un fichier existant de la cible : le signaler », source gardée en secours),
    /// donc jamais de double déplacement ni de perte.
    private static func completeReplacement(_ p: Pending, model: AppModel) throws {
        guard let newId = p.newDocumentId, let transaction = p.transaction,
              UUID(uuidString: transaction) != nil,
              p.kind == "replacement", safeName(p.documentId), safeName(newId),
              p.newCount > 0, p.newSize > 0 else {
            throw fail(String(localized: "Journal de remplacement incomplet : reprise arrêtée sans effacer les données."))
        }
        // Le compteur de conflits (P2 n°4) est réinitialisé à chaque bascule du document.
        lastReplacementConflicts[p.documentId] = nil
        guard model.persistentStorageAvailable, model.review.persistentStorageAvailable else {
            throw fail(String(localized: "Bases persistantes indisponibles : journal conservé pour la reprise."))
        }
        try hit("database.before")
        // 1. Bascule SQL, seulement si elle n'a pas encore été appliquée.
        if let old = try model.database.document(id: p.documentId) {
            let pdf = model.storage.url(for: newId)
            if !fm.fileExists(atPath: pdf.path), let sourcePath = p.newSourcePath,
               let sourceHash = (try? DocumentImporter.sha256(of: URL(fileURLWithPath: sourcePath))) {
                // P2 n°3 (revue R2 F3) : l'identifiant du nouveau PDF EST son empreinte SHA-256,
                // enregistrée dans le journal avant toute mutation. Confronter le fichier relu à
                // cette empreinte refuse un journal altéré (qui ne
                // peut ni déplacer ni retirer le PDF d'un autre livre) ; le journal reste en
                // place, aucune donnée n'est touchée. Fichier simplement absent ou illisible :
                // lecture impossible, le journal reste pour le garde « PDF indisponible » du
                // dessous (suspension, ancienne version conservée, relance possible).
                guard sourceHash == newId else {
                    throw fail(String(localized: "Journal de remplacement altéré : le fichier du nouveau PDF ne correspond pas à l'empreinte du journal, reprise arrêtée sans effacer les données."))
                }
                try moveWithoutOverwrite(URL(fileURLWithPath: sourcePath), pdf,
                                         conflicts: (documentId: p.documentId, folder: conflictsBase(for: p.documentId)
                                             .appendingPathComponent("PDF", isDirectory: true)))
            }
            guard PDFDocument(url: pdf)?.pageCount == p.newCount else {
                // Le nouveau PDF n'est plus disponible : rien n'a encore été changé, le journal est
                // retiré et l'utilisateur relance la mise à jour Drive (l'ancienne version reste).
                try? fm.removeItem(at: marker)
                Diagnostics.error(String(localized: "Remplacement suspendu : nouvelle version PDF introuvable, l'ancienne version est conservée."), "pages")
                throw fail(String(localized: "Remplacement suspendu : relance « Vérifier les mises à jour des cours » à la prochaine ouverture."))
            }
            var updated = old
            updated.id = newId
            updated.pageCount = p.newCount
            updated.fileSize = p.newSize
            updated.lastPageIndex = min(old.lastPageIndex, max(0, p.newCount - 1))
            updated.driveRevision = p.newRevision ?? old.driveRevision
            try model.database.rekeyDocument(from: p.documentId, to: updated,
                                             asideCorrections: PageShift.asideCorrections,
                                             asideInk: PageShift.asideInkDrawing)
        }
        guard try model.database.document(id: p.documentId) == nil,
              try model.database.document(id: newId) != nil else {
            throw fail(String(localized: "Remplacement incohérent en base : reprise arrêtée sans effacer les données."))
        }
        try hit("database.after")
        // L'ancien PDF : déjà retiré par l'import pendant la bascule courante ; une reprise au
        // lancement le retire ici (rejouable, aucune référence en base).
        model.storage.remove(documentId: p.documentId)
        // 2. Cartes : DEC-C2 = A (idempotent ; le reste — FSRS, historique, page source — ne bouge pas).
        try hit("cards.before")
        try model.review.store.remapDocumentId(from: p.documentId, to: newId)
        try hit("cards.after")
        // 3. Fichiers nommés par l'identifiant et caches de l'ancien identifiant.
        try installReplacementFiles(from: p.documentId, to: newId, model: model)
        // P2 n°2 (revue R2) : le choix de langue OCR du livre suit ici, quelle que soit la voie —
        // bascule directe (cet appel) ou reprise au lancement (`reconcile`). Sans lui, un cours
        // mixte serait relu par défaut « Japonais ». La relance de la lecture IA (N1) ne se fait
        // **pas** ici : le journal est encore en place jusqu'à sa dernière étape, la réservation
        // du nouvel identifiant bloquerait la tâche à chaque fois ; elle est faite par l'appelant
        // après la levée (`resumeAIScanAfterReplacement`).
        OCRTargetLanguage.remap(from: p.documentId, to: newId)
        try hit("complete.before")
        try fm.removeItem(at: marker) // Dernière étape : tout est rejouable tant que le journal reste.
    }

    /// N1 (revue R2) : relance de la lecture IA du nouveau PDF, **après** la levée de la
    /// réservation du nouvel identifiant (bascule directe comme reprise au lancement). Ne fait
    /// rien si le document n'est plus en base ; `DocumentScan.start` ignore lui-même une lecture
    /// déjà lancée, l'option réglée sur non, un modèle absent ou une analyse en cours.
    @MainActor private static func resumeAIScanAfterReplacement(newId: String?, model: AppModel) {
        guard let newId, let updated = (try? model.database.document(id: newId)).flatMap({ $0 }) else { return }
        DocumentScan.start(updated, url: model.storage.url(for: newId), ocr: model.ocr)
    }

    /// Fichiers servis par identifiant : brouillons de notes, lectures IA et corrections, rapport
    /// d'analyse, modes d'outil. Le contenu ne change pas (C2.3 suit la version mise à jour telle
    /// quelle) ; seule la clef de rangement — le nom — suit le document. Règle unique : ne jamais
    /// écraser un fichier existant de la cible ; l'élément de conflit est mis de côté dans
    /// ``conflictsBase(for:)`` (P2 n°4) et signalé au rapport de fin.
    private static func installReplacementFiles(from oldId: String, to newId: String, model: AppModel) throws {
        let base = conflictsBase(for: oldId)
        try hit("drafts.before")
        try moveWithoutOverwrite(NoteDraftStore.shared.url(documentId: oldId),
                                 NoteDraftStore.shared.url(documentId: newId),
                                 conflicts: (documentId: oldId, folder: base.appendingPathComponent("Brouillons", isDirectory: true)))
        try hit("drafts.after")
        try hit("files.before")
        try moveFolderWithoutOverwrite(from: DocumentAITextStore.folder.appendingPathComponent(oldId, isDirectory: true),
                                       to: DocumentAITextStore.folder.appendingPathComponent(newId, isDirectory: true),
                                       conflicts: (documentId: oldId, folder: base.appendingPathComponent("Lectures-IA", isDirectory: true)))
        try moveAnalysisReport(from: oldId, to: newId,
                               conflicts: (documentId: oldId, folder: base.appendingPathComponent("Rapport", isDirectory: true)))
        try hit("files.installed")
        try hit("modes.before")
        ReaderToolModeStore().remap(from: oldId, to: newId)
        try hit("modes.after")
        // P3 n°5 (revue R2) : données par document restées sous l'ancien identifiant — l'historique
        // des ajouts de pages (préférences, clé `pages.additions.`) et les temps de lecture
        // (journal des séances, clé `stats.v2.readingSessions`). Même règle : rien d'arrivé
        // n'est écrasé, l'ancien côté est retiré après copie ou fusion.
        PageAdditionHistory.remap(from: oldId, to: newId)
        ReadingTimeTracker.shared.remapDocumentId(from: oldId, to: newId)
        // Caches de lecture portant l'ancien identifiant (même balayage qu'une modification de pages).
        model.thumbnails.removeAll(for: oldId)
        ScanSharpening.removeCache(documentId: oldId)
        ScanSharpening.clearMemory()
        FuriganaLayer.clearMemory()
        LayoutRegionsCache.shared.clear()
        ToneCache.clear()
        DocumentAnalysisService.shared.reloadAfterPageShift(oldId)
    }

    /// Le rapport d'analyse contient l'identifiant de son document : réécrit sous le nouvel
    /// identifiant (valeur finale préparée, comme pour les modifications de pages), puis la source
    /// s'en va. Illisible : déplacé tel quel, jamais réécrit — une copie fausse serait pire.
    private static func moveAnalysisReport(from oldId: String, to newId: String,
                                           conflicts: (documentId: String, folder: URL)? = nil) throws {
        let folder = DocumentAnalysisService.folder
        let source = folder.appendingPathComponent(oldId + ".json")
        let target = folder.appendingPathComponent(newId + ".json")
        guard fm.fileExists(atPath: source.path) else { return }
        // DocumentAnalysis.documentId est immuable : le champ est réécrit via le dictionnaire JSON,
        // après validation complète du rapport (une donnée de l'utilisateur reste intacte ailleurs).
        let data = try Data(contentsOf: source)
        if let report = try? JSONDecoder().decode(DocumentAnalysis.self, from: data),
           var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            guard !fm.fileExists(atPath: target.path) else {
                // P2 n°4 : la donnée de l'ancienne version est mise de côté, jamais effacée ni écrasée.
                if let conflicts {
                    try fm.createDirectory(at: conflicts.folder, withIntermediateDirectories: true)
                    try fm.moveItem(at: source, to: conflicts.folder.appendingPathComponent(source.lastPathComponent))
                    noteConflict(conflicts.documentId)
                }
                Diagnostics.error(String(localized: "Remplacement : le rapport du nouveau document existe déjà, l'ancien est mis de côté dans « Conflits-remplacement »."), "pages")
                return
            }
            object["documentId"] = newId
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: target, options: .atomic)
            try? fm.removeItem(at: source)
        } else {
            // Illisible : déplacé tel quel, jamais réécrit — une copie fausse serait pire.
            try moveWithoutOverwrite(source, target, conflicts: conflicts)
        }
    }

    /// Déplacement rejouable : source absente = déjà fait (la reprise ne refait rien) ; cible
    /// présente = jamais écrasée. Avec un dossier de conflits (remplacement Drive, P2 n°4),
    /// l'élément de l'ancienne version est mis de côté dans `conflicts.folder` et compté pour le
    /// rapport de fin ; sinon il reste en place en secours, comme avant.
    private static func moveWithoutOverwrite(_ source: URL, _ target: URL,
                                             conflicts: (documentId: String, folder: URL)? = nil) throws {
        guard source.path != target.path else { return }
        guard fm.fileExists(atPath: source.path) else { return }
        if fm.fileExists(atPath: target.path) {
            if let conflicts {
                try fm.createDirectory(at: conflicts.folder, withIntermediateDirectories: true)
                try fm.moveItem(at: source, to: conflicts.folder.appendingPathComponent(source.lastPathComponent))
                noteConflict(conflicts.documentId)
                Diagnostics.error(String(localized: "Remplacement : « \(target.lastPathComponent) » existe déjà, « \(source.lastPathComponent) » est mis de côté dans « Conflits-remplacement »."), "pages")
            } else {
                Diagnostics.error(String(localized: "Remplacement : « \(target.lastPathComponent) » existe déjà, « \(source.lastPathComponent) » est gardé en secours."), "pages")
            }
            return
        }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: source, to: target)
    }

    /// Dossier des lectures IA : déplacé tel quel si la cible est absente, sinon fichier par
    /// fichier (même règle « jamais écraser », mise de côté au besoin) ; le dossier source ne
    /// part que s'il est vide.
    private static func moveFolderWithoutOverwrite(from source: URL, to target: URL,
                                                   conflicts: (documentId: String, folder: URL)? = nil) throws {
        guard source.path != target.path, fm.fileExists(atPath: source.path) else { return }
        let names = try fm.contentsOfDirectory(atPath: source.path)
        if !fm.fileExists(atPath: target.path) {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: source, to: target)
            return
        }
        for name in names {
            try moveWithoutOverwrite(source.appendingPathComponent(name), target.appendingPathComponent(name), conflicts: conflicts)
        }
        if (try? fm.contentsOfDirectory(atPath: source.path))?.isEmpty == true {
            try? fm.removeItem(at: source)
        }
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

    /// F6 : la base est l'autorité sur le propriétaire d'une opération après remplacement Drive. Les manifestes
    /// sont réparés depuis l'UUID, après remplacement, au lancement et AVANT une suppression en cascade. Une
    /// coupure entre le rekey SQL et ces écritures est donc récupérable, sans rendre l'ancienne archive restaurable.
    static func synchronizeCopyOwners(_ database: AppDatabase) throws {
        for copy in copies() {
            guard let edit = try database.pageEdit(id: copy.folder.lastPathComponent) else { continue }
            if var manifest = copy.manifest {
                guard manifest.editId == edit.id else { throw fail(String(localized: "Identifiant de copie incohérent : fichiers conservés.")) }
                guard manifest.documentId != edit.documentId else { continue }
                manifest.documentId = edit.documentId
                try JSONEncoder().encode(manifest).write(to: copy.folder.appendingPathComponent("manifest.json"), options: .atomic)
            } else {
                // Une fiche perdue peut retrouver son propriétaire, jamais un inventaire prétendument intact.
                let manifest = Manifest(editId: edit.id, documentId: edit.documentId, kind: edit.kind.rawValue, createdAt: edit.appliedAt)
                try JSONEncoder().encode(manifest).write(to: copy.folder.appendingPathComponent("manifest.json"), options: .atomic)
            }
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

    /// Efface tout de suite une copie d'opération du document, à la demande de l'utilisateur (recette 68 : la place
    /// grossissait sans moyen de la libérer). Même ordre rejouable que la purge : archive SQL marquée effacée, puis
    /// dossier. Une suppression effacée n'est plus restaurable ; ses cartes restent sans page. Refusé pendant une
    /// opération ou avec un journal en attente, pour ne jamais retirer une copie qu'une reprise relirait.
    static func discardCopy(_ model: AppModel, editId: String, documentId: String) throws {
        guard !fm.fileExists(atPath: marker.path), !applyingDocuments.contains(documentId) else {
            throw fail(String(localized: "Une modification des pages est en cours : copie gardée."))
        }
        guard let copy = copies().first(where: { $0.folder.lastPathComponent == editId }),
              copy.manifest?.documentId == documentId else {
            throw fail(String(localized: "Copie introuvable pour ce document."))
        }
        try erase(copy, model: model, now: Date())
    }

    /// Toutes les copies d'opération du document, effacées à la demande (mêmes garanties que `discardCopy`).
    static func discardCopies(_ model: AppModel, documentId: String) throws {
        guard !fm.fileExists(atPath: marker.path), !applyingDocuments.contains(documentId) else {
            throw fail(String(localized: "Une modification des pages est en cours : copies gardées."))
        }
        for copy in copies() where copy.manifest?.documentId == documentId {
            try erase(copy, model: model, now: Date())
        }
    }

    /// Restauration terminée : la copie de la suppression restaurée ne sert plus (une suppression ne se restaure
    /// qu'une fois), et celle de la restauration ne contient que l'état « pages supprimées », qu'une nouvelle
    /// suppression refait. Les garder 30 jours faisait grossir la place à chaque aller-retour (recette 68).
    /// Appelée seulement après l'effacement du journal : aucune reprise ne peut plus les relire. Un échec garde
    /// les copies, que la purge des 30 jours ou l'utilisateur effaceront.
    private static func discardAfterRestoration(_ p: Pending, model: AppModel) {
        guard let plan = p.restoration, let token = p.transaction else { return }
        for copy in copies() where [plan.archiveId, token].contains(copy.folder.lastPathComponent)
            && copy.manifest?.documentId == p.documentId {
            do { try erase(copy, model: model, now: Date()) } catch {
                Diagnostics.error("pages : copie \(copy.folder.lastPathComponent) gardée — \(error.localizedDescription)", "pages")
            }
        }
    }

    private static func erase(_ copy: (folder: URL, manifest: Manifest?, created: Date), model: AppModel, now: Date) throws {
        if copy.manifest?.kind == AppDatabase.PageEditKind.removal.rawValue {
            try model.database.purgeArchive(editId: copy.folder.lastPathComponent, at: now)
        }
        try fm.removeItem(at: copy.folder)
        Diagnostics.log("pages : copie \(copy.folder.lastPathComponent) effacée", "pages")
    }

    /// Document supprimé définitivement : ses copies partent avec lui (sa base est déjà effacée par cascade),
    /// comme les lignes de corrections manuelles mises de côté pour lui (DEC-C3 : sans document, elles ne
    /// serviraient plus jamais, la relecture qui les remettait n'a plus lieu).
    static func removeCopies(documentId: String) {
        CorrectionAsideStore.shared.removeAllCorrections(documentId: documentId)
        for copy in copies() where copy.manifest?.documentId == documentId {
            try? fm.removeItem(at: copy.folder)
        }
    }

    private static func block(_ model: AppModel, _ error: Error) {
        model.openDocumentId = nil
        model.storageRecoveryError = String(localized: "La modification des pages doit être reprise avant de continuer. ") + error.localizedDescription
        Diagnostics.error(model.storageRecoveryError!, "pages")
    }

    /// N4 (revue R2) : un journal de reprise refusé (altéré, incohérent, incomplet, ambigu) ne
    /// doit pas enfermer l'app — « Réessayer la reprise » rejoue le même refus à chaque fois,
    /// sans issue. L'utilisateur peut mettre le journal de côté : le fichier est déplacé (jamais
    /// effacé, jamais écrasé : son nom porte l'instant du déplacement) dans
    /// `Conflits-remplacement/journaux-refusés/`, puis la reprise est suspendue sans erreur.
    /// Refusé pendant une opération en cours ou une sauvegarde : le journal y est encore jouable.
    /// Après un déplacement réussi, l'app démarre normalement — un journal refusé n'a rien changé
    /// en base ni dans les fichiers (les gardes s'arrêtent avant tout effet).
    @MainActor static func setAsideRejectedJournal(_ model: AppModel) {
        guard fm.fileExists(atPath: marker.path), applyingDocuments.isEmpty, !LibraryBackupService.inProgress else { return }
        do {
            let folder = support.appendingPathComponent("Conflits-remplacement", isDirectory: true)
                .appendingPathComponent("journaux-refusés", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.moveItem(at: marker, to: folder.appendingPathComponent("page-shift-" + UUID().uuidString + ".json"))
            model.storageRecoveryError = nil
            Diagnostics.error(String(localized: "Journal de reprise mis de côté dans « Conflits-remplacement/journaux-refusés » : l'app redémarre sans le rejouer, rien n'est effacé."), "pages")
        } catch {
            Diagnostics.error("pages : journal refusé non déplacé — \(error.localizedDescription)", "pages")
        }
    }

    static func reconcile(_ model: AppModel) {
        guard fm.fileExists(atPath: marker.path) else {
            do {
                try synchronizeCopyOwners(model.database)
                model.storageRecoveryError = nil
                purgeExpired(model)
            } catch { block(model, error) }
            return
        }
        do {
            guard model.persistentStorageAvailable, model.review.persistentStorageAvailable else {
                throw fail(String(localized: "Bases persistantes indisponibles : journal conservé pour la reprise."))
            }
            let p = try JSONDecoder().decode(Pending.self, from: Data(contentsOf: marker))
            if p.version == 2 || p.version == 3 || p.kind == "replacement" {
                try complete(p, model: model)
                // N1 (revue R2) : la lecture IA du nouveau PDF est relancée après la levée de la
                // réservation — `complete` vient de retirer le journal, dernier gardien.
                if p.kind == "replacement" { resumeAIScanAfterReplacement(newId: p.newDocumentId, model: model) }
                try synchronizeCopyOwners(model.database)
                purgeExpired(model)
            } else {
                // Le protocole v1 ne distingue pas avant/après l'effet pour report/files/cards.
                // Seul le cas PDF ancien + compte de base connu permet une annulation certaine.
                guard safeName(p.documentId), ["db", "pdf"].contains(p.stage),
                      PDFDocument(url: model.storage.url(for: p.documentId))?.pageCount == p.oldCount,
                      let count = try model.database.document(id: p.documentId)?.pageCount,
                      count == p.oldCount || count == p.newCount else {
                    throw fail(String(localized: "Ancien journal ambigu : une réparation sur copie est nécessaire ; journal et fichiers conservés."))
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
