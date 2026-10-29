// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import Foundation
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
    private var task: Task<Void, Never>?

    func installed(_ entry: CatalogEntry, in model: DictionaryModel) -> DictionaryInfo? {
        model.dictionaries.first { DictionaryCatalog.baseTitle($0.title) == entry.titlePrefix }
    }

    func install(_ entry: CatalogEntry, model: DictionaryModel) {
        guard working == nil, let database = model.database else { return }
        errors[entry.id] = nil
        let previous = installed(entry, in: model)
        working = (entry.id, .index)
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
                    Task { @MainActor in self?.working = (entry.id, .download(fraction)) }
                }
                try Task.checkCancellation()
                self?.working = (entry.id, .importing(0))
                var last = Date.distantPast
                _ = try await Task.detached(priority: .userInitiated) {
                    try DictionaryImporter(database: database).importDictionary(at: zip) { p in
                        guard Date().timeIntervalSince(last) > 0.1 || p.fraction >= 1 else { return }
                        last = Date()
                        Task { @MainActor in self?.working = (entry.id, .importing(p.fraction)) }
                    }
                }.value
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
            } catch {
                self?.errors[entry.id] = error.localizedDescription
                Diagnostics.log("dictionnaires : échec « \(entry.name) » — \(error.localizedDescription)", "dictionnaire")
            }
            model.reload()
            model.applyFirstLanguage()
            self?.working = nil
            self?.task = nil
        }
    }

    func cancel() { task?.cancel() }

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
        }
    }

    /// Lit les index publiés des dictionnaires installés depuis le catalogue (sur demande seulement).
    func checkUpdates(model: DictionaryModel) {
        guard !checking else { return }
        checking = true
        Task {
            var found: [String: YomitanIndex] = [:]
            for entry in DictionaryCatalog.entries {
                guard let installed = installed(entry, in: model),
                      let (data, _) = try? await URLSession.shared.data(from: entry.indexURL),
                      let index = try? YomitanIndex.decode(data),
                      index.isNewer(thanInstalledTitle: installed.title, revision: installed.revision) else { continue }
                found[entry.id] = index
            }
            updates = found
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

    var body: some View {
        List {
            Section("Fourni avec l'app") { bundledRow }
            Section {
                ForEach(DictionaryCatalog.entries) { entry in row(entry) }
            } footer: {
                Text("Téléchargés depuis le site officiel de chaque projet, puis importés sur l'iPad. Rien d'autre ne part en ligne. Les dictionnaires ne sont pas dans la sauvegarde : on les retélécharge.")
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
                Text("FR").font(.caption2.weight(.bold))
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
                    if let license = entry?.license ?? (d.title == BundledLexicon.title ? BundledLexicon.license : nil) {
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
