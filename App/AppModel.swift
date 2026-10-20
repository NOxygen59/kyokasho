// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import Foundation
import OCRKit
import ReaderCore
import SwiftUI

/// État global de l'app : base, stockage, bibliothèque, réglages.
@MainActor
final class AppModel: ObservableObject {
    let database: AppDatabase
    let storage: DocumentStorage
    let importer: DocumentImporter
    let thumbnails: ThumbnailCache
    let ocr: OCRService
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
    /// Document à ouvrir (bibliothèque → lecteur).
    @Published var openDocumentId: String?

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
        } catch {
            // Dernier recours : l'app reste utilisable (sans persistance) plutôt que de planter.
            database = try! AppDatabase.inMemory()
            lastError = "Base de données inaccessible : \(error.localizedDescription)"
        }
        storage = DocumentStorage(root: support.appendingPathComponent("Documents", isDirectory: true))
        importer = DocumentImporter(storage: storage, database: database)
        thumbnails = ThumbnailCache(directory: caches.appendingPathComponent("Thumbnails", isDirectory: true))
        ocr = OCRService(database: database)
        benchDirectory = support.appendingPathComponent("Bench", isDirectory: true)
        try? FileManager.default.createDirectory(at: benchDirectory, withIntermediateDirectories: true)
        appSettings = (try? database.appSettings()) ?? AppSettings()
        readerDefaults = (try? database.readerDefaults()) ?? .default

        database.documentsPublisher()
            .replaceError(with: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.documents = $0 }
            .store(in: &cancellables)
    }

    var colorScheme: ColorScheme? {
        switch appSettings.theme {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
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
    func importFiles(_ urls: [URL], cleanUp: Bool = true, openWhenSingle: Bool = true) {
        guard !urls.isEmpty else { return }
        importProgress = ImportProgress(done: 0, total: urls.count, currentName: urls[0].lastPathComponent)
        let importer = importer
        Task.detached(priority: .userInitiated) {
            var lastImported: String?
            var errors: [String] = []
            for (index, url) in urls.enumerated() {
                await MainActor.run {
                    self.importProgress = ImportProgress(done: index, total: urls.count, currentName: url.lastPathComponent)
                }
                let scoped = url.startAccessingSecurityScopedResource()
                do {
                    let result = try importer.importFile(at: url, displayName: url.lastPathComponent)
                    lastImported = result.document.id
                } catch {
                    errors.append("\(url.lastPathComponent) : \(error.localizedDescription)")
                }
                if scoped { url.stopAccessingSecurityScopedResource() }
                if cleanUp { try? FileManager.default.removeItem(at: url) }
            }
            await MainActor.run {
                self.importProgress = nil
                if !errors.isEmpty { self.lastError = errors.joined(separator: "\n") }
                if openWhenSingle, urls.count == 1, let lastImported { self.openDocumentId = lastImported }
            }
        }
    }

    func delete(_ document: LibraryDocument) {
        let importer = importer
        let thumbnails = thumbnails
        ioQueue.async {
            try? importer.delete(documentId: document.id)
            thumbnails.removeAll(for: document.id)
        }
    }

    func rename(_ document: LibraryDocument, to title: String) {
        var doc = document
        doc.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !doc.title.isEmpty else { return }
        persist { try $0.save(doc) }
    }

    func settings(for document: LibraryDocument) -> ReaderSettings {
        readerDefaults.applying(document.settingsOverride)
    }
}
