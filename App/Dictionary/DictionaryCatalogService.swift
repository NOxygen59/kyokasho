// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import Foundation
import Network
import SwiftUI

/// Télécharge, importe et met à jour les dictionnaires du catalogue (#50). Étapes : lire l'index publié par le
/// projet, télécharger le .zip à l'adresse qu'il donne (dossier temporaire `DictionaryDownload-<UUID>`, effacé ensuite),
/// l'importer en flux (`DictionaryImporter`), puis, pour une mise à jour, supprimer l'ancienne version et donner sa
/// place à la nouvelle dans l'ordre de priorité. Un seul téléchargement à la fois.
@MainActor
final class DictionaryCatalogService: ObservableObject {
    static let shared = DictionaryCatalogService()

    enum Phase: Equatable { case index, download(Double), importing(Double) }

    @Published private(set) var working: (id: String, phase: Phase)?
    @Published private(set) var errors: [String: String] = [:]
    /// Versions publiées plus récentes que celles installées (après « Rechercher des mises à jour »).
    @Published private(set) var updates: [String: YomitanIndex] = [:]
    @Published private(set) var checking = false
    /// Dictionnaires à proposer (identifiants du catalogue, ou celui du lexique fourni) : gardés d'un lancement
    /// à l'autre jusqu'à la réponse de l'utilisateur. Rien n'est installé sans son accord.
    @Published private(set) var offeredUpdates: [String] = UserDefaults.standard.stringArray(forKey: offeredKey) ?? [] {
        didSet { UserDefaults.standard.set(offeredUpdates, forKey: Self.offeredKey) }
    }
    private static let offeredKey = "dictionaries.offeredUpdates"
    private var task: Task<Void, Never>?
    /// +1 à chaque installation : les messages de progression d'une installation annulée sont ignorés.
    private var generation = 0
    private var queue: [String] = []
    /// La file installe aussi ce qui est absent (« Tout installer ») ; sinon elle ne met à jour que l'existant.
    private var installsMissing = false
    private static let lastAutomaticCheckKey = "dictionaries.lastUpdateCheck"
    /// Version du lexique fourni déjà proposée : « Plus tard » ne redemande pas à chaque retour dans l'app.
    private static var bundledOfferedKey: String { "dictionaries.bundledOfferedRevision." + BundledLexicon.selectedLanguage.rawValue }

    /// Une proposition conservée avant un changement de langue ne doit pas installer la mauvaise variante.
    private func discardOtherLanguageOffers() {
        offeredUpdates.removeAll { id in
            BundledLexicon.Language.allCases.contains { $0.resource == id } && id != BundledLexicon.resource
        }
    }

    func installed(_ entry: CatalogEntry, in model: DictionaryModel) -> DictionaryInfo? {
        model.dictionaries.first { DictionaryCatalog.baseTitle($0.title) == entry.titlePrefix }
    }

    func install(_ entry: CatalogEntry, model: DictionaryModel) {
        guard working == nil, let database = model.database else { return }
        errors[entry.id] = nil
        offeredUpdates.removeAll { $0 == entry.id } // Installé par ailleurs : plus rien à proposer.
        let previous = installed(entry, in: model)
        working = (entry.id, .index)
        generation += 1
        let run = generation
        // Progression publiée seulement pour l'installation en cours (revue après recette 1.4.8, P2 6).
        let report: @Sendable (Phase) -> Void = { phase in
            Task { @MainActor in if self.generation == run, self.working?.id == entry.id { self.working = (entry.id, phase) } }
        }
        task = Task { [weak self] in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DictionaryDownload-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            do {
                let (indexData, _) = try await URLSession.shared.data(from: entry.indexURL)
                let index = try YomitanIndex.decode(indexData)
                guard let download = index.downloadUrl, download.scheme == "https" else {
                    throw URLError(.badURL)
                }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let zip = folder.appendingPathComponent("\(entry.id).zip")
                try await Self.download(download, to: zip, expected: entry.approxBytes) { fraction in
                    report(.download(fraction))
                }
                try Task.checkCancellation()
                self?.working = (entry.id, .importing(0))
                var last = Date.distantPast
                let importing = Task.detached(priority: .userInitiated) {
                    try DictionaryImporter(database: database).importDictionary(at: zip) { p in
                        guard Date().timeIntervalSince(last) > 0.1 || p.fraction >= 1 else { return }
                        last = Date()
                        report(.importing(p.fraction))
                    }
                }
                // « Annuler » arrête aussi l'import d'une nouvelle installation (l'importeur efface ce qu'il a commencé).
                // Une mise à jour va au bout : l'importeur retire l'ancienne version avant de remplir la nouvelle, et
                // l'arrêter en route ne laisserait aucun des deux.
                _ = try await withTaskCancellationHandler { try await importing.value } onCancel: {
                    if previous == nil { importing.cancel() }
                }
                // Mise à jour : l'ancienne version part, la nouvelle prend sa place dans l'ordre.
                if let previous, let oldId = previous.id, previous.title != index.title {
                    try? await Task.detached { try database.deleteDictionary(id: oldId) }.value
                    model.reload()
                    var list = model.dictionaries
                    if let new = list.firstIndex(where: { $0.title == index.title }) {
                        let item = list.remove(at: new)
                        list.insert(item, at: min(previous.priority, list.count))
                        try? database.setOrder(list.compactMap(\.id))
                    }
                }
                self?.updates[entry.id] = nil
                Diagnostics.log("dictionnaires : « \(index.title) » installé depuis le catalogue", "dictionnaire")
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
                // Téléchargement arrêté par « Annuler » : pas une erreur.
            } catch {
                self?.errors[entry.id] = error.localizedDescription
                Diagnostics.log("dictionnaires : échec « \(entry.name) » — \(error.localizedDescription)", "dictionnaire")
            }
            model.reload()
            model.applyFirstLanguage()
            self?.working = nil
            self?.task = nil
            self?.installNextQueued(model: model)
        }
    }

    func cancel() {
        queue = []
        task?.cancel()
    }

    /// Version du lexique fourni dans le paquet (`nil` : app construite sans lui). Lue une fois.
    static let bundledRevision: String? = BundledLexicon.url().flatMap { try? BundledLexicon.revision(of: $0) }

    func installedBundled(in model: DictionaryModel) -> DictionaryInfo? {
        model.dictionaries.first { $0.title == BundledLexicon.title }
    }

    /// Lexique fourni avec l'app : importé depuis le paquet, sans réseau. Même titre d'une version à l'autre :
    /// l'importeur remplace l'ancienne version à sa place dans l'ordre.
    func installBundled(model: DictionaryModel) {
        guard working == nil, let database = model.database, let zip = BundledLexicon.url() else { return }
        let id = BundledLexicon.resource
        errors[id] = nil
        offeredUpdates.removeAll { $0 == id }
        working = (id, .importing(0))
        task = Task { [weak self] in
            do {
                var last = Date.distantPast
                let info = try await Task.detached(priority: .userInitiated) {
                    try DictionaryImporter(database: database).importDictionary(at: zip) { p in
                        guard Date().timeIntervalSince(last) > 0.1 || p.fraction >= 1 else { return }
                        last = Date()
                        Task { @MainActor in self?.working = (id, .importing(p.fraction)) }
                    }
                }.value
                Diagnostics.log("dictionnaires : « \(info.title) » (\(info.revision)) installé depuis l'app", "dictionnaire")
            } catch is CancellationError {
            } catch {
                self?.errors[id] = error.localizedDescription
                Diagnostics.log("dictionnaires : échec du lexique fourni — \(error.localizedDescription)", "dictionnaire")
            }
            model.reload()
            model.applyFirstLanguage()
            self?.working = nil
            self?.task = nil
            self?.installNextQueued(model: model)
        }
    }

    /// Lexique fourni plus récent que celui installé : proposé sans réseau, il est déjà dans le paquet.
    private func bundledUpdateAvailable(in model: DictionaryModel) -> Bool {
        guard let bundled = Self.bundledRevision,
              model.dictionaries.contains(where: { BundledLexicon.language(forTitle: $0.title) != nil }) else { return false }
        // Une autre langue est déjà installée : proposer la variante manquante, sans remplacer l'ancienne.
        return installedBundled(in: model)?.revision != bundled
    }

    /// Une fois par semaine au plus, en Wi-Fi : cherche de nouvelles versions et les propose. N'installe rien.
    /// La date n'est notée qu'après une réponse d'un site : une coupure ne repousse pas la vérification d'une semaine.
    func checkAutomaticallyIfDue(model: DictionaryModel) async {
        let defaults = UserDefaults.standard
        guard !checking, working == nil else { return }
        discardOtherLanguageOffers()
        // Le lexique fourni arrive avec l'app, sans réseau : il n'attend pas la vérification de la semaine.
        var ids: [String] = []
        if bundledUpdateAvailable(in: model), defaults.string(forKey: Self.bundledOfferedKey) != Self.bundledRevision {
            ids.append(BundledLexicon.resource)
            defaults.set(Self.bundledRevision, forKey: Self.bundledOfferedKey)
            Diagnostics.log("dictionnaires : nouveau lexique fourni proposé", "dictionnaire")
        }
        guard DictionaryUpdateSchedule.isDue(lastCheck: defaults.object(forKey: Self.lastAutomaticCheckKey) as? Date) else {
            offeredUpdates += ids.filter { !offeredUpdates.contains($0) }
            return
        }
        checking = true
        defer { checking = false }
        if await Self.isOnWiFi() {
            let (found, reached) = await publishedUpdates(model: model)
            updates = found
            ids += DictionaryCatalog.entries.filter { found[$0.id] != nil }.map(\.id)
            if reached { defaults.set(Date(), forKey: Self.lastAutomaticCheckKey) }
            Diagnostics.log("dictionnaires : vérification, \(found.count) mise(s) à jour, site joint : \(reached)", "dictionnaire")
        } else {
            Diagnostics.log("dictionnaires : vérification reportée, pas de Wi-Fi", "dictionnaire")
        }
        // Ce qui attend déjà une réponse reste proposé.
        offeredUpdates = offeredUpdates + ids.filter { !offeredUpdates.contains($0) }
    }

    /// Réponse de l'utilisateur à la proposition : les mises à jour s'installent l'une après l'autre.
    func installOfferedUpdates(model: DictionaryModel) {
        discardOtherLanguageOffers()
        queue = offeredUpdates
        offeredUpdates = []
        installNextQueued(model: model)
    }

    func dismissOfferedUpdates() { offeredUpdates = [] }

    /// Dictionnaires du catalogue pas encore installés.
    func missingEntries(in model: DictionaryModel) -> [CatalogEntry] {
        DictionaryCatalog.entries.filter { installed($0, in: model) == nil }
    }

    /// Tout le catalogue, l'un après l'autre. Un échec reste affiché sur sa ligne et n'arrête pas les suivants.
    func installAll(model: DictionaryModel) {
        queue = missingEntries(in: model).map(\.id)
        installsMissing = true
        installNextQueued(model: model)
    }

    func offeredNames(in model: DictionaryModel) -> [String] {
        offeredUpdates.map { id in
            id == BundledLexicon.resource ? BundledLexicon.name : DictionaryCatalog.entries.first { $0.id == id }?.name ?? id
        }
    }

    private func installNextQueued(model: DictionaryModel) {
        guard working == nil else { return }
        guard !queue.isEmpty else {
            installsMissing = false
            return
        }
        let id = queue.removeFirst()
        // Supprimé entre la proposition et la réponse : on ne le réinstalle pas.
        if id == BundledLexicon.resource, model.dictionaries.contains(where: { BundledLexicon.language(forTitle: $0.title) != nil }) {
            installBundled(model: model)
        } else if let entry = DictionaryCatalog.entries.first(where: { $0.id == id }), installsMissing || installed(entry, in: model) != nil {
            install(entry, model: model)
        } else {
            installNextQueued(model: model)
        }
    }

    private nonisolated static func isOnWiFi() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied && !path.isExpensive)
            }
            monitor.start(queue: DispatchQueue(label: "dictionnaires.wifi"))
        }
    }

    /// Index publiés des dictionnaires installés ; `reached` : au moins un site a répondu.
    private func publishedUpdates(model: DictionaryModel) async -> (found: [String: YomitanIndex], reached: Bool) {
        var found: [String: YomitanIndex] = [:]
        var reached = false
        for entry in DictionaryCatalog.entries {
            guard let installed = installed(entry, in: model),
                  let (data, _) = try? await URLSession.shared.data(from: entry.indexURL),
                  let index = try? YomitanIndex.decode(data) else { continue }
            reached = true
            if index.isNewer(thanInstalledTitle: installed.title, revision: installed.revision) { found[entry.id] = index }
        }
        return (found, reached)
    }

    /// Lit les index publiés des dictionnaires installés depuis le catalogue (sur demande seulement).
    func checkUpdates(model: DictionaryModel) {
        guard !checking else { return }
        discardOtherLanguageOffers()
        if bundledUpdateAvailable(in: model), !offeredUpdates.contains(BundledLexicon.resource) {
            offeredUpdates.append(BundledLexicon.resource)
        }
        checking = true
        Task {
            updates = await publishedUpdates(model: model).found
            checking = false
        }
    }

    /// Téléchargement avec progression ; refuse un fichier vide ou plus de 4 fois la taille attendue.
    private nonisolated static func download(_ url: URL, to target: URL, expected: Int64,
                                             progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = ProgressDelegate(expected: expected, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (temp, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let size = (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int64) ?? 0
        guard size > 0, size < max(expected, 1_000_000) * 4 else { throw URLError(.cannotDecodeContentData) }
        try FileManager.default.moveItem(at: temp, to: target)
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let expected: Int64
        let progress: @Sendable (Double) -> Void
        init(expected: Int64, progress: @escaping @Sendable (Double) -> Void) { self.expected = expected; self.progress = progress }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
            progress(min(1, Double(totalBytesWritten) / Double(max(total, 1))))
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}

/// Réglages > Dictionnaires > « Catalogue » : dictionnaires conseillés à télécharger, leur rôle, leur taille et
/// leur licence ; installer, mettre à jour.
struct DictionaryCatalogView: View {
    @EnvironmentObject private var model: DictionaryModel
    @ObservedObject private var service = DictionaryCatalogService.shared
    @State private var confirmInstallAll = false

    private var missing: [CatalogEntry] { service.missingEntries(in: model) }

    var body: some View {
        List {
            Section("Fourni avec l'app") { bundledRow }
            if !missing.isEmpty {
                Section {
                    Button { confirmInstallAll = true } label: {
                        Label("Tout installer (\(missing.count))", systemImage: "square.and.arrow.down.on.square")
                    }
                    .disabled(service.working != nil)
                } footer: {
                    Text("Environ \(ByteCountFormatter.string(fromByteCount: missing.reduce(0) { $0 + $1.approxBytes }, countStyle: .file)) à télécharger, plus la place une fois installés.")
                }
                .alert("Installer tout le catalogue ?", isPresented: $confirmInstallAll) {
                    Button("Tout installer") { service.installAll(model: model) }
                    Button("Annuler", role: .cancel) {}
                } message: {
                    Text("Les dictionnaires se téléchargent l'un après l'autre. Reste sur cet écran ou dans l'app, de préférence en Wi-Fi.")
                }
            }
            Section {
                ForEach(DictionaryCatalog.entries) { entry in row(entry) }
            } footer: {
                Text("Téléchargés depuis le site officiel de chaque projet, puis importés sur l'iPad. Rien d'autre ne part en ligne. Une fois par semaine en Wi-Fi, l'app regarde si une version plus récente existe et te la propose ; rien ne s'installe sans ton accord. Les dictionnaires ne sont pas dans la sauvegarde : on les retélécharge.")
            }
            Section {
                NavigationLink { DictionaryLicensesView() } label: {
                    Label("Sources et licences", systemImage: "doc.text")
                }
            }
            Section {
                Button { service.checkUpdates(model: model) } label: {
                    HStack {
                        Label("Rechercher des mises à jour", systemImage: "arrow.triangle.2.circlepath")
                        if service.checking { Spacer(); ProgressView() }
                    }
                }
                .disabled(service.checking || service.working != nil)
            }
        }
        .navigationTitle("Catalogue")
    }

    /// Lexique du design d'intérieur : déjà dans l'app, rien à télécharger.
    private var bundledRow: some View {
        let installed = service.installedBundled(in: model)
        let bundled = DictionaryCatalogService.bundledRevision
        let id = BundledLexicon.resource
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(BundledLexicon.name).font(.body.weight(.semibold))
                Text(BundledLexicon.selectedLanguage.rawValue.uppercased()).font(.caption2.weight(.bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Atelier.surfaceHigh, in: Capsule())
                Text("conseillé").font(.caption2.weight(.semibold)).foregroundStyle(.green)
            }
            Text(BundledLexicon.summary).font(.subheadline).foregroundStyle(.secondary)
            Text("Licence : \(BundledLexicon.license)").font(.caption2).foregroundStyle(.tertiary)
            if service.working?.id == id, case .importing(let f)? = service.working?.phase {
                HStack { ProgressView(value: f); Text("Import").font(.caption) }
            } else if bundled == nil {
                Text("Absent de cette version de l'app.").font(.caption).foregroundStyle(.secondary)
            } else if let installed {
                HStack {
                    Label("Installé · \(installed.revision)", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                    Spacer()
                    if let bundled, BundledLexicon.needsUpdate(installedRevision: installed.revision, bundledRevision: bundled) {
                        Button("Mettre à jour (\(bundled))") { service.installBundled(model: model) }
                            .font(.caption.weight(.semibold))
                            .disabled(service.working != nil)
                    }
                }
            } else {
                Button { service.installBundled(model: model) } label: { Label("Installer", systemImage: "plus.circle") }
                    .font(.subheadline.weight(.semibold))
                    .disabled(service.working != nil)
            }
            if let error = service.errors[id] {
                Text("Échec : \(error)").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 3)
    }

    private func row(_ entry: CatalogEntry) -> some View {
        let installed = service.installed(entry, in: model)
        let update = service.updates[entry.id]
        let mine = service.working?.id == entry.id
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.name).font(.body.weight(.semibold))
                Text(entry.language == .french ? "FR" : "EN").font(.caption2.weight(.bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Atelier.surfaceHigh, in: Capsule())
                if entry.recommended { Text("conseillé").font(.caption2.weight(.semibold)).foregroundStyle(.green) }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: entry.approxBytes, countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(entry.summary).font(.subheadline).foregroundStyle(.secondary)
            Text("Licence : \(entry.license)").font(.caption2).foregroundStyle(.tertiary)
            if mine, let phase = service.working?.phase {
                HStack {
                    switch phase {
                    case .index: ProgressView(); Text("Recherche de la dernière version…").font(.caption)
                    case .download(let f): ProgressView(value: f); Text("Téléchargement").font(.caption)
                    case .importing(let f): ProgressView(value: f); Text("Import").font(.caption)
                    }
                    Button("Annuler", role: .destructive) { service.cancel() }.font(.caption)
                }
            } else if let installed {
                HStack {
                    Label("Installé · \(installed.revision)", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                    Spacer()
                    if let update {
                        Button("Mettre à jour (\(update.version))") { service.install(entry, model: model) }
                            .font(.caption.weight(.semibold))
                            .disabled(service.working != nil)
                    }
                }
            } else {
                Button { service.install(entry, model: model) } label: { Label("Télécharger", systemImage: "arrow.down.circle") }
                    .font(.subheadline.weight(.semibold))
                    .disabled(service.working != nil)
            }
            if let error = service.errors[entry.id] {
                Text("Échec : \(error)").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Attribution demandée par les licences (CC BY-SA, EDRDG) : chaque dictionnaire installé, sa source et le texte
/// d'attribution fourni dans son `index.json`.
struct DictionaryLicensesView: View {
    @EnvironmentObject private var model: DictionaryModel

    var body: some View {
        List {
            ForEach(model.dictionaries) { d in
                let entry = DictionaryCatalog.entry(forInstalledTitle: d.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text(d.title).font(.subheadline.weight(.semibold))
                    if let license = entry?.license ?? (BundledLexicon.language(forTitle: d.title) != nil ? BundledLexicon.license : nil) {
                        Text("Licence : \(license)").font(.caption)
                    }
                    if let author = d.author, !author.isEmpty { Text("Auteur : \(author)").font(.caption).foregroundStyle(.secondary) }
                    if let a = d.attribution, !a.isEmpty { Text(a).font(.caption2).foregroundStyle(.secondary) }
                    if let url = d.url, !url.isEmpty { Text(url).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled) }
                }
                .padding(.vertical, 2)
            }
            Section {
                Text("JMdict, JMnedict et KANJIDIC sont la propriété de l'Electronic Dictionary Research and Development Group (edrdg.org), utilisés selon sa licence. Jitendex s'appuie sur JMdict et Tatoeba. Les dictionnaires sont téléchargés depuis leurs sites et restent sur l'iPad. Le lexique du design d'intérieur reprend des extraits du Wiktionnaire et de Wikipédia (CC BY-SA 4.0) ; chaque entrée donne l'adresse de sa page.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sources et licences")
    }
}
