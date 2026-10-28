// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import Foundation
import GLMOCRKit
import OCRKit
import ONNXOCRKit
import ReaderCore
import SwiftUI

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
    /// Document à ouvrir (bibliothèque → lecteur).
    @Published var openDocumentId: String? {
        didSet {
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
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kyokasho", isDirectory: true)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        do {
            database = try AppDatabase.open(at: support.appendingPathComponent("kyokasho.sqlite"))
            persistentStorageAvailable = true
        } catch {
            // Dernier recours : l'app reste utilisable (sans persistance) plutôt que de planter.
            database = try! AppDatabase.inMemory()
            persistentStorageAvailable = false
            lastError = "Base de données inaccessible : \(error.localizedDescription)"
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
                let list = list.filter { !self.deletingIds.contains($0.id) }
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
                    let result = try importer.importFile(at: url, displayName: url.lastPathComponent)
                    if result.isNew {
                        OCRTargetLanguage.set(language, forDocument: result.document.id)
                        newDocuments.append(result.document)
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
                for document in imported {
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

    func delete(_ document: LibraryDocument) {
        let importer = importer
        let thumbnails = thumbnails
        // Retiré de la liste tout de suite ; remis (avec le message d'erreur) si l'effacement échoue.
        deletingIds.insert(document.id)
        documents.removeAll { $0.id == document.id }
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
                Task { @MainActor in self.deletingIds.remove(document.id) }
            } catch {
                Task { @MainActor in
                    self.deletingIds.remove(document.id)
                    self.lastError = "Suppression impossible : \(error.localizedDescription)"
                    self.documents = (try? self.database.allDocuments()) ?? self.documents
                }
            }
        }
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

    /// `pdfPage` : numéro de page du PDF (1 = première page du fichier) qui porte le n° 1 imprimé.
    func setFirstPage(_ document: LibraryDocument, pdfPage: Int) {
        var doc = document
        doc.firstPageIndex = max(0, min(pdfPage - 1, doc.pageCount - 1))
        persist { try $0.save(doc) }
    }

    func settings(for document: LibraryDocument) -> ReaderSettings {
        readerDefaults.applying(document.settingsOverride)
    }
}
