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

    /// Sauvegarde en cours : refuse de lancer une IA, une analyse, une modification de pages ou l'import d'un paquet
    /// pendant la copie (revue Codex de e777c68 : un seul contrôle avant la copie ne suffisait pas).
    @MainActor static private(set) var inProgress = false

    /// Écritures au repos, puis sauvegarde dans un dossier privé, déplacée dans le dossier choisi (sinon laissée à
    /// partager). Refusée pendant une modification des pages, une lecture IA ou une analyse.
    @MainActor
    /// `step` (recette 1.5.6, 4.2) : avancement affiché, sur le fil principal — fraction des fichiers écrits, puis
    /// `nil` avec un libellé pour la vérification et la copie, qui ne se mesurent pas.
    static func backup(_ model: AppModel, step: @escaping @MainActor (Double?, String) -> Void = { _, _ in }) async throws -> Result {
        guard !inProgress else { throw fail(String(localized: "Une sauvegarde est déjà en cours.")) }
        guard PageShift.pendingDocumentId == nil, model.storageRecoveryError == nil else {
            throw fail(String(localized: "Une modification des pages doit être reprise avant de sauvegarder."))
        }
        // Garde dans les deux sens (C2.7) : un remplacement Drive peut modifier les fichiers pendant la copie
        // alors qu'aucun journal n'est encore écrit ; `operationInProgress` couvre aussi cette voie.
        guard !PageShift.operationInProgress else {
            throw fail(String(localized: "Une modification des pages est en cours : sauvegarde possible après sa fin."))
        }
        guard AITaskCenter.shared.jobs.isEmpty, DocumentAnalysisService.shared.progress == nil else {
            throw fail(String(localized: "Une lecture IA ou une analyse est en cours : sauvegarde possible après sa fin."))
        }
        guard !model.libraryMutationInProgress else {
            throw fail(String(localized: "Un import, une suppression ou une orientation est en cours : sauvegarde possible après sa fin."))
        }
        inProgress = true
        let activity = ActivityCenter.shared.begin(.backup)
        defer {
            inProgress = false
            ActivityCenter.shared.end(activity)
        }
        // Écritures en file terminées (notes, encre, position, réglages). Brouillons, conversations, lexique et
        // traductions sont écrits d'un bloc (écriture atomique) : la copie voit l'ancienne ou la nouvelle version,
        // jamais un fichier coupé.
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
                try LibraryBackup.write(source, to: zip, appVersion: version) { done, total in
                    Task { @MainActor in
                        step(Double(done) / Double(max(total, 1)),
                             done == total ? String(localized: "Vérification de la sauvegarde…")
                                           : String(localized: "\(done)/\(total) fichiers"))
                    }
                }
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
        step(nil, String(localized: "Copie dans « \(folder.lastPathComponent) »…"))
        try fm.copyItem(at: zip, to: target)
        try? fm.removeItem(at: work)
        let removed = (try? LibraryBackup.rotate(in: folder, keep: keep).count) ?? 0
        Diagnostics.log("sauvegarde : \(name) écrite, \(removed) ancienne(s) effacée(s)", "sauvegarde")
        return Result(url: target, inChosenFolder: true, removed: removed)
    }

    // MARK: Restaurer

    /// Restauration inachevée au lancement : aucune base ne doit être ouverte (sinon une bibliothèque vide serait créée
    /// à la place de celle mise de côté). Lu par `AppModel`, `ReviewModel` et `DictionaryModel`.
    nonisolated(unsafe) static var restoreBlocked = false
    nonisolated(unsafe) static var restoreMessage: String?

    /// Réglages propres à **cet** iPad, jamais remplacés par ceux de la sauvegarde (revue Codex de e777c68) : dossier
    /// de sauvegarde, comptes et identifiants clients, diagnostic, relevé de batterie, mises à jour, visite guidée,
    /// moniteur, options de débogage.
    static let devicePreferencePrefixes = ["backup.", "google", "github.", "diagnostics.", "energy.", "update.", "intro.",
                                           "monitor.", "debug", "forceLandscape", "appearance.ipadLibrary."]

    /// Domaine restauré : celui de la sauvegarde, sauf les réglages de l'appareil, gardés tels qu'ils sont ici.
    static func mergedPreferences(restored: [String: Any], current: [String: Any]) -> [String: Any] {
        func isDevice(_ key: String) -> Bool { devicePreferencePrefixes.contains { key.hasPrefix($0) } }
        var out = restored.filter { !isDevice($0.key) }
        for (key, value) in current where isDevice(key) { out[key] = value }
        return out
    }

    private nonisolated(unsafe) static var restoreChecked = false

    /// Au lancement, **avant toute ouverture de base**. Appelée en tête de `AppModel.init` (qui ouvre les bases de
    /// l'app, des cartes et des dictionnaires) et de `KyokashoApp.init` : quel que soit l'ordre réel de création par
    /// SwiftUI, le premier appel l'exécute, une seule fois (revue Codex de e777c68).
    static func applyPendingRestoreOnce() {
        guard !restoreChecked else { return }
        restoreChecked = true
        let marker: LibraryRestore.Marker
        do {
            guard let found = try LibraryRestore.pending(support: support) else { return }
            marker = found
        } catch {
            restoreBlocked = true
            restoreMessage = String(localized: "Restauration inachevée : rien n'a été effacé. Ferme puis rouvre l'app. (\(error.localizedDescription))")
            Diagnostics.error("restauration : \(error.localizedDescription)", "sauvegarde")
            return
        }
        Diagnostics.write("restauration de \(marker.backupName)…", level: .info, area: "sauvegarde", sync: true)
        do {
            let bundle = Bundle.main.bundleIdentifier ?? ""
            let current = UserDefaults.standard.persistentDomain(forName: bundle) ?? [:]
            let outcome = try LibraryRestore.apply(support: support, analysis: DocumentAnalysisService.folder) { domain in
                UserDefaults.standard.setPersistentDomain(mergedPreferences(restored: domain, current: current), forName: bundle)
            }
            restoreMessage = String(localized: "Restauration terminée : « \(marker.backupName) ».")
            UserDefaults.standard.set(marker.backupName, forKey: "backup.lastRestoreName")
            if case .cleanupPending = outcome {
                Diagnostics.error("restauration : copies mises de côté non effacées, nouvel essai au prochain lancement", "sauvegarde")
            }
            Diagnostics.write("restauration terminée", level: .info, area: "sauvegarde", sync: true)
        } catch {
            restoreBlocked = true
            restoreMessage = String(localized: "Restauration inachevée : rien n'a été effacé. Ferme puis rouvre l'app pour la reprendre. (\(error.localizedDescription))")
            Diagnostics.error("restauration : \(error.localizedDescription)", "sauvegarde")
        }
    }

    struct Prepared: Identifiable { let id: String; let name: String; let manifest: LibraryBackup.Manifest }

    /// Étape 1 (rien de modifié) : vérifier et extraire la sauvegarde dans le dossier de préparation.
    @MainActor
    static func verifyRestore(from file: URL) async throws -> Prepared {
        guard !FileManager.default.fileExists(atPath: LibraryRestore.markerURL(support: support).path) else {
            throw fail(String(localized: "Une restauration est déjà prête : ferme puis rouvre l'app."))
        }
        let id = UUID().uuidString
        let staging = LibraryRestore.stagingURL(support: support, id: id)
        let manifest: LibraryBackup.Manifest
        do {
            manifest = try await Task.detached(priority: .userInitiated) {
                let access = file.startAccessingSecurityScopedResource()
                defer { if access { file.stopAccessingSecurityScopedResource() } }
                return try LibraryBackup.open(file, into: staging)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return Prepared(id: id, name: file.lastPathComponent, manifest: manifest)
    }

    /// Étape 2, après accord : sauvegarde de sécurité de l'état actuel (obligatoire, dans le dossier choisi), puis
    /// marqueur. La restauration s'applique au prochain lancement de l'app.
    @MainActor
    static func confirmRestore(_ model: AppModel, _ prepared: Prepared) async throws -> Result {
        let staging = LibraryRestore.stagingURL(support: support, id: prepared.id)
        do {
            guard folder != nil else { throw fail(String(localized: "Choisis d'abord un dossier de sauvegarde : la copie de sécurité y sera écrite.")) }
            let safety = try await backup(model)
            _ = try LibraryRestore.writeMarker(support: support, id: prepared.id, backupName: prepared.name)
            Diagnostics.log("sauvegarde : restauration de \(prepared.name) prête, sécurité \(safety.url.lastPathComponent)", "sauvegarde")
            return safety
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Préparation abandonnée : dossier de préparation effacé.
    static func discardRestore(_ prepared: Prepared) {
        try? FileManager.default.removeItem(at: LibraryRestore.stagingURL(support: support, id: prepared.id))
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
    /// Avancement de la sauvegarde en cours (recette 1.5.6, 4.2) : fraction (`nil` : étape non mesurée) et libellé.
    @State private var backupStep: (fraction: Double?, label: String)?
    @State private var message: String?
    @State private var shareURL: URL?
    @State private var pickingBackup = false
    @State private var prepared: LibraryBackupService.Prepared?
    @State private var restoreReady = false
    @State private var confirming = false

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await run() }
                } label: {
                    Label(working ? String(localized: "Sauvegarde en cours…") : String(localized: "Sauvegarder maintenant"), systemImage: "externaldrive.badge.checkmark")
                }
                .disabled(working)
                if let backupStep {
                    if let fraction = backupStep.fraction {
                        ProgressView(value: fraction) { Text(verbatim: backupStep.label).font(.footnote) }
                    } else {
                        ProgressView { Text(verbatim: backupStep.label).font(.footnote) }
                    }
                }
                if let message { Text(message).font(.footnote).foregroundStyle(Atelier.textSecondary) }
                if let last = LibraryBackupService.lastBackup {
                    LabeledContent("Dernière sauvegarde", value: last.formatted(date: .abbreviated, time: .shortened))
                }
            } footer: {
                Text("Tout : documents, notes, dessins, OCR, lectures IA, traductions, cartes et révisions, conversations, lexique, dictionnaires, réglages. Les modèles d'IA ne sont pas inclus (à retélécharger). Rien ne part en ligne : le fichier va seulement dans le dossier que tu choisis.")
            }
            Section {
                Button("Restaurer une sauvegarde…") { pickingBackup = true }.disabled(working)
                if let name = UserDefaults.standard.string(forKey: "backup.lastRestoreName") {
                    LabeledContent("Dernière restauration", value: name)
                }
            } header: {
                Text("Restaurer")
            } footer: {
                Text("La sauvegarde est vérifiée sans rien toucher, puis tu confirmes. Une sauvegarde de sécurité de ta bibliothèque actuelle est faite d'abord dans ton dossier ; la restauration s'applique au prochain lancement de l'app. Les modèles d'IA de l'iPad sont gardés.")
            }
            Section {
                LabeledContent("Dossier", value: folderName ?? String(localized: "aucun"))
                Button(folderName == nil ? String(localized: "Choisir le dossier de sauvegarde…") : String(localized: "Changer de dossier…")) { choosing = true }
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
                } catch { message = String(localized: "Dossier refusé : \(error.localizedDescription)") }
            }
            .ignoresSafeArea()
        }
        .sheet(item: Binding(get: { shareURL.map(SharedFile.init) }, set: { if $0 == nil { shareURL = nil } })) { file in
            ActivityShareSheet(url: file.url)
        }
        .sheet(isPresented: $pickingBackup) {
            DocumentPicker(types: [UTType(filenameExtension: LibraryBackup.fileExtension) ?? .data, .data], multiple: false) { urls in
                guard let url = urls.first else { return }
                Task { await verify(url) }
            }
            .ignoresSafeArea()
        }
        // La sauvegarde vérifiée est passée aux boutons (`presenting`) : la fermeture de l'alerte ne peut pas l'effacer
        // avant l'action. Annuler efface le dossier de préparation.
        .alert("Restaurer cette sauvegarde ?", isPresented: $confirming, presenting: prepared) { p in
            Button("Annuler", role: .cancel) { LibraryBackupService.discardRestore(p); prepared = nil }
            Button("Restaurer", role: .destructive) { Task { await confirm(p) } }
        } message: { p in
            do {
                let c = p.manifest.counts
                Text("« \(p.name) » du \(p.manifest.createdAt.formatted(date: .abbreviated, time: .shortened)) : \(c["documents"] ?? 0) documents, \(c["notes"] ?? 0) notes, \(c["cartes"] ?? 0) cartes. Ta bibliothèque actuelle sera remplacée, après une sauvegarde de sécurité dans ton dossier.")
            }
        }
        .alert("Restauration prête", isPresented: $restoreReady) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ferme Kyōkasho (balaye-la vers le haut dans le sélecteur d'apps) puis rouvre-la : la restauration se fera au lancement.")
        }
    }

    private func run() async {
        working = true
        message = nil
        do {
            defer { backupStep = nil }
            let result = try await LibraryBackupService.backup(model) { fraction, label in backupStep = (fraction, label) }
            if result.inChosenFolder {
                message = String(localized: "Sauvegarde écrite dans « \(folderName ?? "") »") + (result.removed > 0 ? String(localized: " ; \(result.removed) ancienne(s) effacée(s).") : ".")
            } else {
                message = String(localized: "Sauvegarde prête : choisis où l'enregistrer.")
                shareURL = result.url
            }
        } catch {
            message = String(localized: "Sauvegarde impossible : \(error.localizedDescription)")
        }
        working = false
    }

    private func verify(_ url: URL) async {
        working = true
        message = nil
        do { prepared = try await LibraryBackupService.verifyRestore(from: url); confirming = true }
        catch { message = String(localized: "Sauvegarde refusée : \(error.localizedDescription)") }
        working = false
    }

    private func confirm(_ p: LibraryBackupService.Prepared) async {
        prepared = nil
        working = true
        do {
            let safety = try await LibraryBackupService.confirmRestore(model, p)
            message = String(localized: "Sauvegarde de sécurité écrite : \(safety.url.lastPathComponent).")
            restoreReady = true
        } catch {
            message = String(localized: "Restauration annulée : \(error.localizedDescription)")
        }
        working = false
    }

    private struct SharedFile: Identifiable { let url: URL; var id: String { url.path } }
}
