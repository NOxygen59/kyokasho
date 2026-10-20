// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Navigation dans Google Drive et import des PDF (ou Slides/Docs exportés en PDF).
struct DriveBrowserView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var drive = GoogleDrive.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if !drive.isConfigured {
                    DriveSetupHelp()
                } else if !drive.isSignedIn {
                    DriveSignIn()
                } else {
                    DriveHome()
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }
}

private struct DriveHome: View {
    @State private var search = ""

    var body: some View {
        List {
            Section {
                NavigationLink { DriveFolderView(location: .folder(id: "root", name: "Mon Drive")) } label: {
                    Label("Mon Drive", systemImage: "externaldrive")
                }
                NavigationLink { DriveFolderView(location: .sharedWithMe) } label: {
                    Label("Partagés avec moi", systemImage: "person.2")
                }
            }
            Section {
                NavigationLink("Mises à jour et compte") { DriveAccountView() }
            }
        }
        .searchable(text: $search, prompt: "Chercher dans Drive")
        .navigationDestination(isPresented: Binding(get: { !submitted.isEmpty }, set: { if !$0 { submitted = "" } })) {
            DriveFolderView(location: .search(submitted))
        }
        .onSubmit(of: .search) { submitted = search }
        .navigationTitle("Google Drive")
    }

    @State private var submitted = ""
}

struct DriveFolderView: View {
    @EnvironmentObject private var model: AppModel
    let location: GoogleDrive.Location
    @State private var files: [GoogleDrive.File] = []
    @State private var loading = true
    @State private var error: String?
    @State private var downloading: [String: Double] = [:]

    private var title: String {
        switch location {
        case .folder(_, let name): return name
        case .sharedWithMe: return "Partagés avec moi"
        case .search(let text): return "« \(text) »"
        }
    }

    var body: some View {
        List {
            if loading { HStack { ProgressView(); Text("Chargement…").foregroundStyle(.secondary) } }
            if let error { Text(error).foregroundStyle(.red) }
            if !loading && files.isEmpty && error == nil { Text("Aucun PDF ni dossier ici.").foregroundStyle(.secondary) }
            ForEach(files) { file in
                if file.isFolder {
                    NavigationLink { DriveFolderView(location: .folder(id: file.id, name: file.name)) } label: {
                        Label(file.name, systemImage: "folder.fill")
                    }
                } else {
                    Button { download(file) } label: { row(file) }
                        .buttonStyle(.plain)
                        .disabled(downloading[file.id] != nil)
                }
            }
        }
        .navigationTitle(title)
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder
    private func row(_ file: GoogleDrive.File) -> some View {
        let imported = model.documents.first { $0.driveFileId == file.id }
        HStack {
            Image(systemName: file.isPDF ? "doc.richtext" : "rectangle.on.rectangle")
                .foregroundStyle(file.isPDF ? Color.red : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).lineLimit(2)
                HStack(spacing: 8) {
                    if let size = file.byteSize { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
                    if file.isGoogleExportable { Text("exporté en PDF") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let progress = downloading[file.id] {
                ProgressView(value: progress).frame(width: 80)
            } else if let imported {
                Text(imported.driveRevision == file.revision ? "Importé" : "Mise à jour")
                    .font(.caption.bold())
                    .foregroundStyle(imported.driveRevision == file.revision ? Color.secondary : Color.accentColor)
            } else {
                Image(systemName: "arrow.down.circle").foregroundStyle(Color.accentColor)
            }
        }
    }

    private func load() async {
        loading = true
        error = nil
        do { files = try await GoogleDrive.shared.list(location) } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func download(_ file: GoogleDrive.File) {
        downloading[file.id] = 0
        Task {
            do {
                let url = try await GoogleDrive.shared.download(file) { value in
                    Task { @MainActor in downloading[file.id] = value }
                }
                try await model.importFromDrive(url: url, file: file)
            } catch {
                self.error = error.localizedDescription
            }
            downloading[file.id] = nil
        }
    }
}

private struct DriveSignIn: View {
    @ObservedObject private var drive = GoogleDrive.shared
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.icloud").font(.system(size: 52)).foregroundStyle(.secondary)
            Text("Connecte ton compte Google").font(.title2.bold())
            Text("Accès en lecture seule à ton Drive, pour importer tes cours et récupérer leurs nouvelles versions.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            Button {
                busy = true
                Task {
                    do { try await drive.signIn() } catch { self.error = error.localizedDescription }
                    busy = false
                }
            } label: { Label("Se connecter avec Google", systemImage: "person.crop.circle.badge.checkmark") }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            if let error { Text(error).foregroundStyle(.red).multilineTextAlignment(.center) }
        }
        .padding(40)
        .navigationTitle("Google Drive")
    }
}

private struct DriveSetupHelp: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Google Drive n'est pas encore configuré").font(.title2.bold())
                Text("Il faut un identifiant client OAuth (gratuit) créé avec ton compte Google, puis recompiler l'app. Les étapes sont dans le README, section « Google Drive ».")
                Text("En attendant, tu peux importer depuis Drive avec le bouton « + » : choisis Google Drive dans le sélecteur Fichiers (l'app Google Drive doit être installée).")
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        }
        .navigationTitle("Google Drive")
    }
}

struct DriveAccountView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var drive = GoogleDrive.shared
    @State private var checking = false
    @State private var report: String?

    var body: some View {
        Form {
            Section("Compte") {
                if !drive.isConfigured {
                    Text("Non configuré (voir README).").foregroundStyle(.secondary)
                } else if drive.isSignedIn {
                    LabeledContent("Connecté", value: drive.accountEmail ?? "compte Google")
                    Button("Se déconnecter", role: .destructive) { drive.signOut() }
                } else {
                    DriveSignIn()
                }
            }
            Section {
                Button {
                    checking = true
                    Task {
                        report = await model.checkDriveUpdates()
                        checking = false
                    }
                } label: {
                    HStack { Text("Vérifier les mises à jour des cours"); if checking { Spacer(); ProgressView() } }
                }
                .disabled(!drive.isSignedIn || checking)
                if let report { Text(report).font(.footnote) }
            } footer: {
                Text("Si un cours importé depuis Drive a changé, la nouvelle version remplace l'ancienne. Tes surlignages, dessins, signets et commentaires sont gardés (rattachés aux mêmes numéros de page).")
            }
        }
        .navigationTitle("Google Drive")
    }
}

// MARK: - Import et mises à jour

extension AppModel {
    func importFromDrive(url: URL, file: GoogleDrive.File) async throws {
        let importer = importer
        let existing = documents.first { $0.driveFileId == file.id }
        let id: String = try await Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            if let existing {
                return try importer.replace(documentId: existing.id, withFileAt: url, driveRevision: file.revision).id
            }
            return try importer.importFile(at: url, displayName: url.lastPathComponent,
                                           driveFileId: file.id, driveRevision: file.revision).document.id
        }.value
        thumbnails.removeAll(for: existing?.id ?? id)
        _ = id
    }

    /// Compare chaque document importé de Drive avec sa version en ligne, télécharge ceux qui ont changé.
    func checkDriveUpdates() async -> String {
        let linked = documents.filter { $0.driveFileId != nil }
        guard !linked.isEmpty else { return "Aucun document importé depuis Google Drive." }
        var updated: [String] = []
        var failures: [String] = []
        for document in linked {
            guard let fileId = document.driveFileId else { continue }
            do {
                let file = try await GoogleDrive.shared.metadata(fileId: fileId)
                guard file.revision != document.driveRevision else { continue }
                let url = try await GoogleDrive.shared.download(file) { _ in }
                try await importFromDrive(url: url, file: file)
                updated.append(document.title)
            } catch {
                failures.append("\(document.title) : \(error.localizedDescription)")
            }
        }
        var lines: [String] = []
        lines.append(updated.isEmpty ? "Tout est à jour (\(linked.count) document(s))." : "Mis à jour : " + updated.joined(separator: ", "))
        if !failures.isEmpty { lines.append("Erreurs : " + failures.joined(separator: " ; ")) }
        return lines.joined(separator: "\n")
    }
}
