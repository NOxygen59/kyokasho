// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import ReaderCore
import SwiftUI
import UniformTypeIdentifiers

/// Sauvegarde complète côté app (#51, C1 ; décisions de NOxygen59 du 29/10/2026) : **tout** le dossier de l'app
/// (`Application Support/Kyokasho`) sauf les modèles d'IA, plus les lectures IA et les traductions de définitions ; les
/// trois bases par l'API de sauvegarde SQLite ; les réglages de l'app. Dictionnaires compris (ceux importés à la main ne
/// se retéléchargent pas). Le fichier va dans le dossier choisi une fois dans Fichiers ; les 10 dernières sont gardées.
/// Hors sauvegarde : modèles (liste seulement), caches, `tmp`, Trousseau, journal de diagnostic, relevé de batterie.
enum LibraryBackupService {
    static let keep = 10
    private static let bookmarkKey = "backup.folderBookmark"
    static let lastBackupKey = "backup.lastDate"

    static var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
    static var kyokasho: URL { support.appendingPathComponent("Kyokasho", isDirectory: true) }

    // MARK: Dossier de sauvegarde (signet de sécurité)

    /// Dossier choisi dans Fichiers (iCloud Drive, Google Drive…), ou `nil`.
    static var folder: URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: bookmarkKey) }
        return url
    }

    static func setFolder(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        UserDefaults.standard.set(try url.bookmarkData(), forKey: bookmarkKey)
    }

    static var lastBackup: Date? { UserDefaults.standard.object(forKey: lastBackupKey) as? Date }

    // MARK: Contenu

    /// Réglages de l'app (domaine UserDefaults de Kyōkasho). Aucun secret n'y est rangé : les jetons sont au Trousseau.
    private static func preferencesFile(in work: URL) throws -> URL {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        let url = work.appendingPathComponent("preferences.plist")
        try PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0).write(to: url)
        return url
    }

    @MainActor
    static func source(_ model: AppModel, work: URL) throws -> LibraryBackup.Source {
        var databases: [(path: String, writer: any DatabaseWriter)] = [("kyokasho/kyokasho.sqlite", model.database.writer),
                                                                      ("kyokasho/Review/review.sqlite", model.review.store.writer)]
        if let dictionaries = model.dictionary.database {
            databases.append(("kyokasho/Dictionaries/dictionaries.sqlite", dictionaries.writer))
        }
        func count(_ writer: any DatabaseWriter, _ table: String) -> Int {
            (try? writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") }) ?? 0
        }
        let models = ((try? FileManager.default.contentsOfDirectory(atPath: kyokasho.appendingPathComponent("Models").path)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted()
        return LibraryBackup.Source(
            databases: databases,
            folders: [("kyokasho", kyokasho), ("analysis", DocumentAnalysisService.folder)],
            files: [("support/definition-translations.json", support.appendingPathComponent("definition-translations.json")),
                    ("preferences.plist", try preferencesFile(in: work))],
            counts: ["documents": count(model.database.writer, "document"), "notes": count(model.database.writer, "pageComment"),
                     "cartes": count(model.review.store.writer, "card")],
            models: models,
            // Modèles retéléchargeables (plusieurs Go) ; journal transactionnel : la sauvegarde est refusée s'il existe.
            excluded: ["kyokasho/Models", "kyokasho/page-shift.json"])
    }

    // MARK: Sauvegarder

    struct Result { let url: URL; let inChosenFolder: Bool; let removed: Int }

    /// Écritures au repos, puis sauvegarde dans un dossier privé, déplacée dans le dossier choisi (sinon laissée à
    /// partager). Refusée pendant une modification des pages, une lecture IA ou une analyse.
    @MainActor
    static func backup(_ model: AppModel) async throws -> Result {
        guard PageShift.pendingDocumentId == nil, model.storageRecoveryError == nil else {
            throw fail("Une modification des pages doit être reprise avant de sauvegarder.")
        }
        guard AITaskCenter.shared.jobs.isEmpty, DocumentAnalysisService.shared.progress == nil else {
            throw fail("Une lecture IA ou une analyse est en cours : sauvegarde possible après sa fin.")
        }
        await model.drainWrites()
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("BackupApp-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let source = try source(model, work: work)
        let name = LibraryBackup.fileName(at: Date())
        let zip = work.appendingPathComponent(name)
        let version = DocumentPackageService.appVersion
        do {
            try await Task.detached(priority: .userInitiated) {
                try LibraryBackup.write(source, to: zip, appVersion: version)
            }.value
        } catch {
            try? fm.removeItem(at: work)
            throw error
        }
        UserDefaults.standard.set(Date(), forKey: lastBackupKey)
        guard let folder else {
            Diagnostics.log("sauvegarde : \(name) prête à partager", "sauvegarde")
            return Result(url: zip, inChosenFolder: false, removed: 0)
        }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let target = folder.appendingPathComponent(name)
        try fm.copyItem(at: zip, to: target)
        try? fm.removeItem(at: work)
        let removed = (try? LibraryBackup.rotate(in: folder, keep: keep).count) ?? 0
        Diagnostics.log("sauvegarde : \(name) écrite, \(removed) ancienne(s) effacée(s)", "sauvegarde")
        return Result(url: target, inChosenFolder: true, removed: removed)
    }

    private static func fail(_ text: String) -> NSError {
        NSError(domain: "Kyokasho.Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}

/// Réglages → Fichiers et comptes → Sauvegarde.
struct BackupSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var folderName = LibraryBackupService.folder?.lastPathComponent
    @State private var choosing = false
    @State private var working = false
    @State private var message: String?
    @State private var shareURL: URL?

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await run() }
                } label: {
                    Label(working ? "Sauvegarde en cours…" : "Sauvegarder maintenant", systemImage: "externaldrive.badge.checkmark")
                }
                .disabled(working)
                if let message { Text(message).font(.footnote).foregroundStyle(Atelier.textSecondary) }
                if let last = LibraryBackupService.lastBackup {
                    LabeledContent("Dernière sauvegarde", value: last.formatted(date: .abbreviated, time: .shortened))
                }
            } footer: {
                Text("Tout : documents, notes, dessins, OCR, lectures IA, traductions, cartes et révisions, conversations, lexique, dictionnaires, réglages. Les modèles d'IA ne sont pas inclus (à retélécharger). Rien ne part en ligne : le fichier va seulement dans le dossier que tu choisis.")
            }
            Section {
                LabeledContent("Dossier", value: folderName ?? "aucun")
                Button(folderName == nil ? "Choisir le dossier de sauvegarde…" : "Changer de dossier…") { choosing = true }
            } footer: {
                Text("Choisis une fois un dossier dans Fichiers (sur l'iPad, iCloud Drive ou Google Drive). Les \(LibraryBackupService.keep) dernières sauvegardes y sont gardées ; seules les plus anciennes sauvegardes de Kyōkasho sont effacées, jamais tes autres fichiers.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Atelier.canvas)
        .navigationTitle("Sauvegarde")
        .sheet(isPresented: $choosing) {
            DocumentPicker(types: [.folder], multiple: false, asCopy: false) { urls in
                guard let url = urls.first else { return }
                do {
                    try LibraryBackupService.setFolder(url)
                    folderName = LibraryBackupService.folder?.lastPathComponent
                } catch { message = "Dossier refusé : \(error.localizedDescription)" }
            }
            .ignoresSafeArea()
        }
        .sheet(item: Binding(get: { shareURL.map(SharedFile.init) }, set: { if $0 == nil { shareURL = nil } })) { file in
            ActivityShareSheet(url: file.url)
        }
    }

    private func run() async {
        working = true
        message = nil
        do {
            let result = try await LibraryBackupService.backup(model)
            if result.inChosenFolder {
                message = "Sauvegarde écrite dans « \(folderName ?? "") »" + (result.removed > 0 ? " ; \(result.removed) ancienne(s) effacée(s)." : ".")
            } else {
                message = "Sauvegarde prête : choisis où l'enregistrer."
                shareURL = result.url
            }
        } catch {
            message = "Sauvegarde impossible : \(error.localizedDescription)"
        }
        working = false
    }

    private struct SharedFile: Identifiable { let url: URL; var id: String { url.path } }
}
