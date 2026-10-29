// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit
import ReaderCore
import ReviewKit

// Seule la composition UI est doublée. Le lien PageShift.swift compile le fichier produit exact,
// avec les vrais AppDatabase, ReviewStore, DocumentStorage, PDFKit et DocumentAnalysis.
@MainActor final class AppModel {
    var persistentStorageAvailable = true
    let database: AppDatabase
    let ocr: OCRService
    let storage: DocumentStorage
    let review: ReviewModel
    var storageRecoveryError: String?
    var openDocumentId: String?
    var lastError: String?
    let thumbnails = ThumbnailCache()
    var onDrain: (() async -> Void)?
    func drainWrites() async { await onDrain?() }
    init(root: URL) throws {
        database = try .open(at: root.appendingPathComponent("kyokasho.sqlite"))
        ocr = OCRService(database: database)
        storage = DocumentStorage(root: root.appendingPathComponent("Documents"))
        review = ReviewModel(store: try .open(directory: root.appendingPathComponent("Review")))
    }
}
@MainActor final class ReviewModel {
    var persistentStorageAvailable = true
    let store: ReviewStore
    init(store: ReviewStore) { self.store = store }
}
@MainActor final class DocumentAnalysisService {
    static let shared = DocumentAnalysisService()
    struct Progress { var documentId: String }
    var progress: Progress?
    nonisolated(unsafe) static var folder = FileManager.default.temporaryDirectory
    func shiftReport(_ id: String, by offset: Int) {
        let url = Self.folder.appendingPathComponent(id + ".json")
        guard var report = try? JSONDecoder().decode(DocumentAnalysis.self, from: Data(contentsOf: url)) else { return }
        report.pages = Dictionary(uniqueKeysWithValues: report.pages.map { index, page in
            var value = page; value.source += offset
            return (index + offset, value)
        })
        try? JSONEncoder().encode(report).write(to: url, options: .atomic)
    }
    func reloadAfterPageShift(_ id: String) {}
}
@MainActor final class AITaskCenter {
    static let shared = AITaskCenter()
    struct Job { var key: String }
    var jobs: [Job] = []
}
final class ThumbnailCache { func removeAll(for id: String) {} }
enum ScanSharpening {
    static func removeCache(documentId: String) {}
    static func clearMemory() {}
}
enum FuriganaLayer { static func clearMemory() {} }
enum ToneCache { static func clear() {} }
enum Diagnostics {
    static func error(_ message: String, _ area: String = "app") {}
    static func log(_ message: @autoclosure () -> String, _ area: String = "app") {}
}
@MainActor final class LayoutRegionsCache {
    static let shared = LayoutRegionsCache()
    func clear() {}
}
/// Sauvegarde complète (#51) : jamais en cours dans le harnais.
@MainActor enum LibraryBackupService { static var inProgress = false }
