// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit
import ReaderCore
import UniformTypeIdentifiers

/// Export et import d'un document complet (`.kyokasho`, format dans `ReaderCore.DocumentPackage`).
///
/// Import : le paquet est entièrement vérifié **avant** toute modification. Un document déjà présent n'est remplacé
/// qu'après accord explicite, et son état actuel est d'abord exporté en paquet de sécurité
/// (`Documents/Paquets de sécurité/`, visible dans Fichiers). Les fichiers sont installés d'abord, la base en dernier
/// (une transaction) : si l'app s'arrête au milieu d'un remplacement, le paquet de sécurité permet de revenir en
/// arrière. Le document ne doit pas être ouvert ni en cours de modification des pages.
enum DocumentPackageService {
    /// Type déclaré dans Info.plist (`UTExportedTypeDeclarations`) : Fichiers montre les paquets comme des documents
    /// Kyōkasho et les ouvre dans l'app. Conforme à `public.data` seulement (pas au zip), pour que Fichiers ne
    /// propose pas de les décompresser.
    static let contentType = UTType(exportedAs: "fr.noxygen59.kyokasho.package", conformingTo: .data)

    /// Réglages propres au document (pas ceux de l'app) : langue de l'OCR et modes du lecteur.
    @MainActor
    static func preferences(documentId: String) -> [String: String] {
        var out = ["ocrLanguage": OCRTargetLanguage.forDocument(documentId).rawValue]
        if let modes = UserDefaults.standard.data(forKey: ReaderToolModeStore.key(documentId: documentId)) {
            out["toolModes"] = modes.base64EncodedString()
        }
        return out
    }

    @MainActor
    static func applyPreferences(_ preferences: [String: String], documentId: String) {
        if let raw = preferences["ocrLanguage"], let language = OCRTargetLanguage(rawValue: raw) {
            OCRTargetLanguage.set(language, forDocument: documentId)
        }
        if let base64 = preferences["toolModes"], let data = Data(base64Encoded: base64) {
            UserDefaults.standard.set(data, forKey: ReaderToolModeStore.key(documentId: documentId))
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    /// Écrit le paquet d'un document dans `folder` (hors du fil principal ; les valeurs de l'app sont lues avant).
    static func export(_ document: LibraryDocument, database: AppDatabase, pdf: URL, drafts: [Int: String],
                       preferences: [String: String], dictionaries: [String], to folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(DocumentExport.baseName(document.title) + "." + DocumentPackage.fileExtension)
        try DocumentPackage.write(to: url, documentId: document.id, title: document.title, pageCount: document.pageCount,
                                  appVersion: appVersion, pdf: pdf, rows: database.packageRows(documentId: document.id),
                                  analysisFolder: DocumentAnalysisService.folder.appendingPathComponent(document.id, isDirectory: true),
                                  report: DocumentAnalysisService.folder.appendingPathComponent(document.id + ".json"),
                                  drafts: drafts, preferences: preferences, dictionaries: dictionaries)
        return url
    }

    /// Paquet ouvert et vérifié, en attente d'installation.
    struct Pending: Identifiable {
        var id: String { contents.manifest.documentId }
        let contents: DocumentPackage.Contents
        let folder: URL
        /// Le document est déjà dans la bibliothèque : remplacer demande un accord.
        let exists: Bool
        /// Dictionnaires du paquet absents de cet appareil (à télécharger depuis le catalogue).
        let missingDictionaries: [String]
    }
}

extension AppModel {
    /// Étape 1 : copier, ouvrir et vérifier le paquet (rien n'est modifié dans l'app).
    func openPackage(_ url: URL) async throws -> DocumentPackageService.Pending {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PackageImport-\(UUID().uuidString)", isDirectory: true)
        let installed = Set(dictionary.dictionaries.map(\.title))
        do {
            let contents = try await Task.detached(priority: .userInitiated) { () -> DocumentPackage.Contents in
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                return try DocumentPackage.open(url, into: folder)
            }.value
            return .init(contents: contents, folder: folder,
                         exists: try database.document(id: contents.manifest.documentId) != nil,
                         missingDictionaries: contents.manifest.dictionaries.filter { !installed.contains($0) })
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Paquet abandonné : ses fichiers extraits sont effacés.
    func discardPackage(_ pending: DocumentPackageService.Pending) {
        try? FileManager.default.removeItem(at: pending.folder)
    }

    /// Étape 2 : installer. `replacing` est exigé si le document existe ; sa version actuelle est d'abord exportée
    /// en paquet de sécurité. Renvoie l'adresse de ce paquet de sécurité, s'il y en a un.
    @discardableResult
    func installPackage(_ pending: DocumentPackageService.Pending, replacing: Bool) async throws -> URL? {
        let contents = pending.contents, id = contents.manifest.documentId
        defer { discardPackage(pending) }
        guard storageRecoveryError == nil else { throw packageError("Une reprise est en attente : réessaie après.") }
        guard !LibraryBackupService.inProgress else { throw packageError("Sauvegarde en cours : réessaie après sa fin.") }
        guard openDocumentId != id, !PageShift.isBusy(id) else {
            throw packageError("Ferme le document (et attends la fin d'une modification de ses pages) avant de l'importer.")
        }
        guard !pending.exists || replacing else { throw packageError("Ce document est déjà dans la bibliothèque.") }
        await drainWrites()
        var safety: URL?
        if pending.exists, let current = try database.document(id: id) {
            // Copie de sécurité de l'état actuel, avant de toucher à quoi que ce soit.
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Paquets de sécurité", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamped = folder.appendingPathComponent(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-"), isDirectory: true)
            try FileManager.default.createDirectory(at: stamped, withIntermediateDirectories: true)
            safety = try DocumentPackageService.export(current, database: database, pdf: storage.url(for: id),
                                                       drafts: NoteDraftStore.shared.drafts(documentId: id),
                                                       preferences: DocumentPackageService.preferences(documentId: id),
                                                       dictionaries: dictionary.dictionaries.map(\.title), to: stamped)
        }
        let pdf = storage.url(for: id), database = database
        let analysis = DocumentAnalysisService.folder.appendingPathComponent(id, isDirectory: true)
        let report = DocumentAnalysisService.folder.appendingPathComponent(id + ".json")
        let draftsFile = NoteDraftStore.shared.url(documentId: id)
        await Task.detached { PDFPool.release(pdf) }.value
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            // PDF : même empreinte que celle du paquet = même fichier ; sinon remplacé d'un coup. L'identifiant n'est
            // l'empreinte que d'un PDF jamais modifié (#49) : comparer à celle du manifeste.
            if !fm.fileExists(atPath: pdf.path) || (try? DocumentImporter.sha256(of: pdf)) != contents.manifest.files["document.pdf"] {
                try fm.createDirectory(at: pdf.deletingLastPathComponent(), withIntermediateDirectories: true)
                let staged = pdf.deletingLastPathComponent().appendingPathComponent(".package-\(UUID().uuidString).pdf")
                try fm.copyItem(at: contents.pdf, to: staged)
                if fm.fileExists(atPath: pdf.path) { _ = try fm.replaceItemAt(pdf, withItemAt: staged) } else { try fm.moveItem(at: staged, to: pdf) }
            }
            // Lectures IA et traductions : dossier préparé à côté, puis échangé.
            let staged = analysis.deletingLastPathComponent().appendingPathComponent(".package-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: staged, withIntermediateDirectories: true)
            for (name, file) in contents.analysisFiles { try fm.copyItem(at: file, to: staged.appendingPathComponent(name)) }
            if fm.fileExists(atPath: analysis.path) { try fm.removeItem(at: analysis) }
            try fm.moveItem(at: staged, to: analysis)
            if let file = contents.report {
                try Data(contentsOf: file).write(to: report, options: .atomic)
            } else if fm.fileExists(atPath: report.path) {
                try fm.removeItem(at: report)
            }
            if contents.drafts.isEmpty {
                if fm.fileExists(atPath: draftsFile.path) { try fm.removeItem(at: draftsFile) }
            } else {
                try fm.createDirectory(at: draftsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try NoteDraftStore.encode(contents.drafts).write(to: draftsFile, options: .atomic)
            }
            // Base en dernier, en une transaction.
            try database.installPackage(documentId: id, rows: contents.rows, replacing: replacing)
        }.value
        // Les opérations de pages ne voyagent pas et la cascade a effacé celles d'ici : leurs copies ne peuvent plus
        // rien restaurer (le paquet de sécurité garde l'état remplacé).
        if replacing { PageShift.removeCopies(documentId: id) }
        DocumentPackageService.applyPreferences(contents.preferences, documentId: id)
        thumbnails.removeAll(for: id)
        ScanSharpening.removeCache(documentId: id)
        DocumentAnalysisService.shared.reloadAfterPageShift(id)
        refreshPrintedNumbers()
        Diagnostics.log("paquet : « \(contents.manifest.title) » importé\(replacing ? " (remplacé)" : "")", "import")
        return safety
    }

    private func packageError(_ text: String) -> NSError {
        NSError(domain: "Kyokasho.Package", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
