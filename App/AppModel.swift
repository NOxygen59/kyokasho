// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import Foundation
import GLMOCRKit
import OCRKit
import ONNXOCRKit
import ReaderCore
import SwiftUI

private struct PageRotationBlocked: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

/// État global de l'app : base, stockage, bibliothèque, réglages.
@MainActor
final class AppModel: ObservableObject {
    let database: AppDatabase
    let persistentStorageAvailable: Bool
    let storage: DocumentStorage
    let importer: DocumentImporter
    let thumbnails: ThumbnailCache
    let ocr: OCRService
    let dictionary: DictionaryModel
    let review: ReviewModel
    /// Images du banc d'essai OCR.
    let benchDirectory: URL

    @Published private(set) var documents: [LibraryDocument] = []
    @Published var appSettings: AppSettings {
        didSet {
            guard appSettings != oldValue else { return }
            let value = appSettings
            persist { try $0.setAppSettings(value) }
        }
    }
    @Published var readerDefaults: ReaderSettings {
        didSet {
            guard readerDefaults != oldValue else { return }
            let value = readerDefaults
            persist { try $0.setReaderDefaults(value) }
        }
    }
    /// Dessiner au doigt aussi (utile sans Apple Pencil, et dans le simulateur).
    @Published var drawWithFinger: Bool = UserDefaults.standard.bool(forKey: "drawWithFinger") {
        didSet { UserDefaults.standard.set(drawWithFinger, forKey: "drawWithFinger") }
    }

    @Published var importProgress: ImportProgress?
    @Published var lastError: String?
    @Published var storageRecoveryError: String?
    /// Onglets des documents ouverts dans le lecteur (#16), dans l'ordre d'ouverture.
    @Published private(set) var tabs = DocumentTabs()

    /// Document à ouvrir (bibliothèque → lecteur) ; chaque document ouvert prend un onglet.
    /// Paquet `.kyokasho` ouvert depuis Fichiers, pris en charge par la bibliothèque (vérification, accord).
    @Published var incomingPackage: URL?
    @Published var openDocumentId: String? {
        didSet {
            if let openDocumentId { tabs.open(openDocumentId) }
            // Lecteur fermé : la bibliothèque reçoit enfin les positions de lecture mises de côté.
            if openDocumentId == nil, let pending = pendingDocuments {
                pendingDocuments = nil
                documents = pending
            }
        }
    }
    /// Liste reçue pendant la lecture quand seule la position de lecture a changé : pas publiée
    /// tout de suite (sinon la bibliothèque, derrière le lecteur, se redessine à chaque page tournée).
    private var pendingDocuments: [LibraryDocument]?
    /// Documents nouvellement importés dont la catégorie reste à demander (« Livre ou manuel ? », RET-039, #54).
    @Published private(set) var categoryQuestions: [LibraryDocument] = []
    /// Import d'un seul fichier : il s'ouvre une fois la question répondue.
    private var openAfterCategory: String?

    private var cancellables = Set<AnyCancellable>()
    /// File d'écriture : les enregistrements ne bloquent jamais l'interface.
    private let ioQueue = DispatchQueue(label: "kyokasho.io", qos: .utility)

    struct ImportProgress: Equatable {
        var done: Int
        var total: Int
        var currentName: String
    }

    init() {
        // Restauration préparée (#51) : avant d'ouvrir la moindre base, quel que soit l'ordre de création par SwiftUI.
        LibraryBackupService.applyPendingRestoreOnce()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kyokasho", isDirectory: true)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        do {
            guard !LibraryBackupService.restoreBlocked else {
                throw NSError(domain: "Kyokasho.Backup", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: LibraryBackupService.restoreMessage ?? String(localized: "Restauration inachevée.")])
            }
            database = try AppDatabase.open(at: support.appendingPathComponent("kyokasho.sqlite"))
            persistentStorageAvailable = true
        } catch {
            // Dernier recours : l'app reste utilisable (sans persistance) plutôt que de planter.
            database = try! AppDatabase.inMemory()
            persistentStorageAvailable = false
            lastError = String(localized: "Base de données inaccessible : \(error.localizedDescription)")
        }
        storage = DocumentStorage(root: support.appendingPathComponent("Documents", isDirectory: true))
        importer = DocumentImporter(storage: storage, database: database)
        thumbnails = ThumbnailCache(directory: caches.appendingPathComponent("Thumbnails", isDirectory: true))
        // Moteurs à modèle téléchargé : toujours enregistrés, disponibles une fois le modèle installé.
        OCRService.register(NDLOCREngine())
        OCRService.register(PPOCREngine())
        OCRService.register(GLMOCREngine())
        dictionary = DictionaryModel(appDatabase: database)
        // Chaque nouveau résultat OCR est relu (mots du dictionnaire, caractères qui se ressemblent) avant le cache.
        ocr = OCRService(database: database, postProcess: Self.proofreader(dictionary))
        review = ReviewModel(appDatabase: database)
        benchDirectory = support.appendingPathComponent("Bench", isDirectory: true)
        try? FileManager.default.createDirectory(at: benchDirectory, withIntermediateDirectories: true)
        appSettings = (try? database.appSettings()) ?? AppSettings()
        readerDefaults = (try? database.readerDefaults()) ?? .default

        database.documentsPublisher()
            .replaceError(with: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                guard let self else { return }
                // Une suppression en cours ne doit pas faire réapparaître le livre un instant.
                let all = list.filter { !self.deletingIds.contains($0.id) }
                // Corbeille : ces documents existent toujours mais quittent la bibliothèque.
                self.trashedDocuments = all.filter { self.trash.contains($0.id) }
                let list = all.filter { !self.trash.contains($0.id) }
                self.purgeExpiredTrashOnce(all)
                if self.openDocumentId != nil, Self.onlyReadingPositionChanged(self.documents, list) {
                    self.pendingDocuments = list
                } else {
                    self.pendingDocuments = nil
                    self.documents = list
                }
            }
            .store(in: &cancellables)
        // « Ajouter des pages… » interrompu (app arrêtée au milieu) : annulé ou terminé.
        PageShift.reconcile(self)
        // Après la reprise des pages, qui efface un ancien message : la restauration inachevée prime et bloque tout.
        if LibraryBackupService.restoreBlocked { storageRecoveryError = LibraryBackupService.restoreMessage }
        refreshPrintedNumbers()
        // Lexique du domaine lu tout de suite : la relecture de l'OCR (hors du fil principal) s'en sert.
        _ = DomainLexicon.shared
    }

    func persist(_ work: @escaping @Sendable (AppDatabase) throws -> Void) {
        let database = database
        ioQueue.async {
            do { try work(database) } catch {
                Task { @MainActor in self.lastError = error.localizedDescription }
            }
        }
    }

    // MARK: Import

    /// Importe des fichiers déjà copiés localement par le sélecteur (hors fil principal).
    /// Relecture OCR par le dictionnaire (rien si aucun dictionnaire : la page sera relue plus tard).
    /// Les termes du lexique du domaine (`DomainLexicon`) comptent comme des mots connus.
    nonisolated static func proofreader(_ dict: DictionaryModel) -> @Sendable (OCRPage) async -> OCRPage {
        { page in
            guard await dict.hasTermDictionaries else { return page }
            let terms = DomainLexicon.terms
            return await OCRProofreader.proofread(page) { text in
                OCRProofreader.addingTerms(terms, to: await dict.segment(text).map { (length: $0.text.count, known: $0.term != nil) }, in: text)
            }
        }
    }

    /// Chaque document importé est ensuite lu par l'IA (`DocumentScan`, pages pas encore lues).
    func importFiles(_ urls: [URL], cleanUp: Bool = true, openWhenSingle: Bool = true,
                     language: OCRTargetLanguage = .japanese) {
        guard storageRecoveryError == nil else { return }
        guard !LibraryBackupService.inProgress else {
            lastError = String(localized: "Sauvegarde en cours : réessaie après sa fin.")
            return
        }
        guard !urls.isEmpty else { return }
        importProgress = ImportProgress(done: 0, total: urls.count, currentName: urls[0].lastPathComponent)
        let importer = importer
        Task.detached(priority: .userInitiated) {
            var lastImported: String?
            var imported: [LibraryDocument] = []
            var newDocuments: [LibraryDocument] = []
            var errors: [String] = []
            for (index, url) in urls.enumerated() {
                await MainActor.run {
                    self.importProgress = ImportProgress(done: index, total: urls.count, currentName: url.lastPathComponent)
                }
                let scoped = url.startAccessingSecurityScopedResource()
                do {
                    let isComic = url.pathExtension.lowercased() == ComicBookArchive.fileExtension
                    let result = isComic ? try importer.importComicArchive(at: url, displayName: url.lastPathComponent)
                        : try importer.importFile(at: url, displayName: url.lastPathComponent)
                    if result.isNew {
                        OCRTargetLanguage.set(language, forDocument: result.document.id)
                        if !isComic { newDocuments.append(result.document) } // La catégorie d'un comics est connue.
                    }
                    lastImported = result.document.id
                    imported.append(result.document)
                } catch {
                    errors.append("\(url.lastPathComponent) : \(error.localizedDescription)")
                }
                if scoped { url.stopAccessingSecurityScopedResource() }
                if cleanUp { try? FileManager.default.removeItem(at: url) }
            }
            await MainActor.run {
                self.importProgress = nil
                for document in imported where !document.isComic {
                    DocumentScan.start(document, url: self.storage.url(for: document.id), ocr: self.ocr)
                }
                if !errors.isEmpty { self.lastError = errors.joined(separator: "\n") }
                self.categoryQuestions.append(contentsOf: newDocuments)
                if openWhenSingle, urls.count == 1, let lastImported {
                    // Question en attente : le livre s'ouvre après la réponse (`answerCategory`).
                    if self.categoryQuestions.isEmpty { self.openDocumentId = lastImported } else { self.openAfterCategory = lastImported }
                }
            }
        }
    }

    static func onlyReadingPositionChanged(_ old: [LibraryDocument], _ new: [LibraryDocument]) -> Bool {
        guard old.count == new.count else { return false }
        // Par identifiant : l'ordre (dernier ouvert en premier) peut bouger.
        let previous = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for b in new {
            guard let a = previous[b.id] else { return false }
            var x = a, y = b
            x.lastPageIndex = 0; y.lastPageIndex = 0
            x.lastOpenedAt = nil; y.lastOpenedAt = nil
            if x != y { return false }
        }
        return true
    }

    /// Documents en cours de suppression (cachés de la liste jusqu'à la fin de l'effacement).
    private var deletingIds: Set<String> = []
    /// Import ou suppression qui change à la fois la base et les PDF de la bibliothèque.
    /// Une sauvegarde ne doit pas commencer entre ces deux écritures.
    var libraryMutationInProgress: Bool { importProgress != nil || !deletingIds.isEmpty || pageRotationInProgress }
    private var pageRotationInProgress = false

    // MARK: Corbeille

    static let trashKey = "library.trash"
    /// Dates de mise à la corbeille (préférences, donc dans la sauvegarde) ; voir `DocumentTrash`.
    private(set) var trash = DocumentTrash.decode(UserDefaults.standard.data(forKey: AppModel.trashKey))
    /// Documents à la corbeille, du plus récent au plus ancien.
    @Published private(set) var trashedDocuments: [LibraryDocument] = []
    private var trashPurged = false

    private func saveTrash() { UserDefaults.standard.set(trash.encoded(), forKey: Self.trashKey) }

    /// « Supprimer » : met le document de côté (rien n'est effacé ; restaurable pendant 30 jours).
    func moveToTrash(_ document: LibraryDocument) {
        // Lecteur sur ce document : retour à la bibliothèque (son onglet disparaît avec lui de la liste).
        if openDocumentId == document.id { openDocumentId = nil }
        trash.put(document.id)
        saveTrash()
        documents.removeAll { $0.id == document.id }
        pendingDocuments?.removeAll { $0.id == document.id }
        if !trashedDocuments.contains(where: { $0.id == document.id }) { trashedDocuments.insert(document, at: 0) }
        Diagnostics.log("corbeille : « \(document.title) » mis de côté", "bibliotheque")
    }

    func restoreFromTrash(_ document: LibraryDocument) {
        trash.remove(document.id)
        saveTrash()
        trashedDocuments.removeAll { $0.id == document.id }
        documents = ((try? database.allDocuments()) ?? documents).filter { !trash.contains($0.id) && !deletingIds.contains($0.id) }
        Diagnostics.log("corbeille : « \(document.title) » restauré", "bibliotheque")
    }

    /// Efface pour de bon (le même effacement qu'avant la corbeille).
    func deleteForever(_ document: LibraryDocument) {
        trash.remove(document.id)
        saveTrash()
        trashedDocuments.removeAll { $0.id == document.id }
        delete(document)
    }

    func emptyTrash() { trashedDocuments.forEach(deleteForever) }

    /// Une fois par lancement : efface les documents restés plus de 30 jours, et oublie ceux qui n'existent plus.
    private func purgeExpiredTrashOnce(_ all: [LibraryDocument]) {
        guard !trashPurged, !all.isEmpty else { return }
        trashPurged = true
        trash.keep(only: Set(all.map(\.id)))
        let expired = Set(trash.expired())
        saveTrash()
        for document in all where expired.contains(document.id) { deleteForever(document) }
    }

    /// Nouvelle page « 1 » enregistrée ; si les pages ont des identités (#49), leurs numéros imprimés repartent de
    /// cette page (choix explicite de l'utilisateur), puis l'affichage est relu.
    func savePageOne(_ doc: LibraryDocument) {
        persist { database in
            try database.save(doc)
            try database.renumberPrintedPages(documentId: doc.id, firstPageIndex: doc.firstPageIndex)
            Task { @MainActor in self.refreshPrintedNumbers() }
        }
    }

    /// Demande venue du lecteur (bande des pages → corbeille) : le lecteur se ferme, puis la bibliothèque ouvre
    /// « Pages du document » sur cette page (#49 : aucune modification des pages avec le document ouvert).
    struct PageEditRequest: Equatable {
        let documentId: String
        let page: Int
    }
    @Published var pageEditRequest: PageEditRequest?

    func requestPageEdit(documentId: String, page: Int) {
        pageEditRequest = PageEditRequest(documentId: documentId, page: page)
        openDocumentId = nil
    }

    /// Attend la fin des écritures en file (position de lecture, réglages, page 1…) : une écriture tardive du
    /// lecteur ne doit pas arriver après une modification des pages (revue Codex R6).
    func drainWrites() async {
        let queue = ioQueue
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in queue.async { done.resume() } }
    }

    /// Numéros imprimés gardés par page après une modification des pages (#49, R5) : relus depuis la base.
    func refreshPrintedNumbers() {
        PrintedPageNumbers.set((try? database.printedNumbers()) ?? [:])
    }

    func delete(_ document: LibraryDocument) {
        guard !LibraryBackupService.inProgress else {
            lastError = String(localized: "Sauvegarde en cours : réessaie après sa fin.")
            return
        }
        // Avant la cascade SQL : réparer l'association UUID → document des copies d'avant remplacement Drive.
        do { try PageShift.synchronizeCopyOwners(database) }
        catch { lastError = String(localized: "Suppression impossible : \(error.localizedDescription)"); return }
        let importer = importer
        let thumbnails = thumbnails
        // Retiré de la liste tout de suite ; remis (avec le message d'erreur) si l'effacement échoue.
        deletingIds.insert(document.id)
        documents.removeAll { $0.id == document.id }
        closeTab(document.id)
        pendingDocuments?.removeAll { $0.id == document.id }
        let url = storage.url(for: document.id)
        ioQueue.async {
            PDFPool.release(url)
            do {
                try importer.delete(documentId: document.id)
                thumbnails.removeAll(for: document.id)
                ScanSharpening.removeCache(documentId: document.id)
                OCRTargetLanguage.forget(document.id)
                try? NoteDraftStore.shared.removeAll(documentId: document.id)
                ReaderToolModeStore().forget(documentId: document.id)
                PageAdditionHistory.forget(document.id)
                Task { @MainActor in
                    self.deletingIds.remove(document.id)
                    ReadingTimeTracker.shared.forget(documentId: document.id)
                    PageShift.removeCopies(documentId: document.id) // Pages supprimées gardées 30 jours (#49).
                }
            } catch {
                Task { @MainActor in
                    self.deletingIds.remove(document.id)
                    self.lastError = String(localized: "Suppression impossible : \(error.localizedDescription)")
                    self.documents = (try? self.database.allDocuments()) ?? self.documents
                }
            }
        }
    }

    /// Ferme l'onglet ; s'il était affiché, le voisin prend sa place (aucun : retour à la bibliothèque).
    func closeTab(_ id: String) {
        let next = tabs.close(id, current: openDocumentId)
        if next != openDocumentId { openDocumentId = next }
    }

    func rename(_ document: LibraryDocument, to title: String) {
        var doc = document
        doc.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !doc.title.isEmpty else { return }
        persist { try $0.save(doc) }
    }

    /// Réponse à « Livre ou manuel ? » pour le premier document en attente ; `nil` : « Plus tard » (non classé).
    func answerCategory(_ category: DocumentCategory?) {
        guard !categoryQuestions.isEmpty else { return }
        let document = categoryQuestions.removeFirst()
        if let category { setCategory(document.id, category) }
        if categoryQuestions.isEmpty, let id = openAfterCategory {
            openAfterCategory = nil
            openDocumentId = id
        }
    }

    /// Catégorie d'un document (requête ciblée : rien d'autre n'est réécrit).
    func setCategory(_ documentId: String, _ category: DocumentCategory?) {
        // Copie en mémoire mise à jour tout de suite : le lecteur ouvert juste après part de la bonne catégorie et ne
        // la réécrit pas avec l'ancienne en enregistrant ses réglages (la base suit, sur la file d'écriture).
        if let index = documents.firstIndex(where: { $0.id == documentId }) { documents[index].category = category }
        persist { try $0.updateCategory(documentId: documentId, category: category) }
    }

    /// Raison pour laquelle l'orientation est refusée maintenant, affichée dès l'ouverture de l'écran (RET-062).
    func pageRotationBlockReason(for document: LibraryDocument) -> String? {
        if LibraryBackupService.inProgress { return String(localized: "Une sauvegarde est en cours. L'orientation sera possible à sa fin.") }
        if pageRotationInProgress { return String(localized: "Une orientation est déjà en cours d'application.") }
        if AITaskCenter.shared.jobs.contains(where: { $0.key.contains(document.id) })
            || DocumentAnalysisService.shared.progress?.documentId == document.id {
            return String(localized: "Une analyse ou une lecture IA de ce document est en cours. L'orientation sera possible à sa fin.")
        }
        return nil
    }

    /// Applique les rotations confirmées, puis rend périmés uniquement les résultats qui dépendent de l'image tournée.
    /// `rereading` faux (par défaut) : OCR tourné avec la page, lectures IA et traductions gardées, rien n'est perdu.
    /// `rereading` vrai, choix explicite pour une page lue de travers : ces résultats sont effacés et refaits.
    func applyPageRotations(_ rotations: [Int: Int], to document: LibraryDocument, rereading: Bool = false) async throws {
        let valid = rotations.filter { (0..<document.pageCount).contains($0.key) }
        guard !valid.isEmpty else { return }
        if let reason = pageRotationBlockReason(for: document) { throw PageRotationBlocked(reason: reason) }
        pageRotationInProgress = true
        defer { pageRotationInProgress = false }
        await ocr.beginPageMutation(documentId: document.id)
        do {
            let pages = Set(valid.keys)
            try database.applyPageRotations(documentId: document.id, rotations: valid,
                                            keepingOCR: rereading ? OCRPage.jsonKeepingManualEdits : OCRPage.jsonFollowingRotation)
            guard rereading else {
                await ocr.endPageMutation(documentId: document.id)
                return
            }
            // Après la transaction : ces lectures coûtent du temps et de la batterie, un échec de la base ne doit
            // pas les perdre. Si leur effacement échoue, la rotation reste valable et l'utilisateur est prévenu.
            do {
                try DocumentAITextStore.removePages(documentId: document.id, pages: pages)
            } catch {
                Diagnostics.error("rotation : lectures IA non effacées : \(error.localizedDescription)", "lecteur")
                lastError = String(localized: "Orientation appliquée, mais d'anciennes lectures IA n'ont pas pu être effacées.")
            }
            for page in pages { DocumentAnalysisService.shared.invalidatePage(page, documentId: document.id) }
            await ocr.endPageMutation(documentId: document.id)
            DocumentScan.start(document, url: storage.url(for: document.id), ocr: ocr)
        } catch {
            await ocr.endPageMutation(documentId: document.id)
            throw error
        }
    }

    /// `pdfPage` : numéro de page du PDF (1 = première page du fichier) qui porte le n° 1 imprimé.
    func setFirstPage(_ document: LibraryDocument, pdfPage: Int) {
        var doc = document
        doc.firstPageIndex = max(0, min(pdfPage - 1, doc.pageCount - 1))
        savePageOne(doc)
    }

    func settings(for document: LibraryDocument) -> ReaderSettings {
        readerDefaults.applying(document.settingsOverride)
    }
}
