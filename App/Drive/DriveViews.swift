// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
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
                NavigationLink { DriveFolderView(location: .folder(id: "root", name: String(localized: "Mon Drive"))) } label: {
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
        .searchable(text: $search, prompt: String(localized: "Chercher dans Drive"))
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
    @State private var pendingImport: GoogleDrive.File?
    @State private var importLanguage: OCRTargetLanguage = .japanese

    private var title: String {
        switch location {
        case .folder(_, let name): return name
        case .sharedWithMe: return String(localized: "Partagés avec moi")
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
                    Button {
                        if model.documents.contains(where: { $0.driveFileId == file.id }) {
                            download(file)
                        } else {
                            importLanguage = .japanese
                            pendingImport = file
                        }
                    } label: { row(file) }
                        .buttonStyle(.plain)
                        .disabled(downloading[file.id] != nil)
                }
            }
        }
        .navigationTitle(title)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $pendingImport) { file in
            NavigationStack {
                Form {
                    Section {
                        Picker("Langue du document", selection: $importLanguage) {
                            ForEach(OCRTargetLanguage.allCases, id: \.self) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                    } footer: {
                        Text("Ce choix guide la lecture IA lancée après l'import. Les chiffres et formules restent tels qu'ils figurent sur la page.")
                    }
                    Section {
                        Button("Importer « \(file.name) »") {
                            let language = importLanguage
                            pendingImport = nil
                            download(file, language: language)
                        }
                    }
                }
                .navigationTitle("Importer depuis Drive")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { pendingImport = nil } } }
            }
        }
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
                Text(imported.driveRevision == file.revision ? String(localized: "Importé") : String(localized: "Mise à jour"))
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

    private func download(_ file: GoogleDrive.File, language: OCRTargetLanguage? = nil) {
        downloading[file.id] = 0
        Task {
            do {
                let url = try await GoogleDrive.shared.download(file) { value in
                    Task { @MainActor in downloading[file.id] = value }
                }
                try await model.importFromDrive(url: url, file: file, language: language)
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
            Image(systemName: "externaldrive.badge.icloud").font(Atelier.font(52)).foregroundStyle(.secondary)
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

/// Assistant de configuration de Google Drive : 4 étapes dans le navigateur, puis on colle
/// l'identifiant ici. Une seule fois, aucune recompilation.
struct DriveSetupHelp: View {
    @ObservedObject private var drive = GoogleDrive.shared
    @Environment(\.openURL) private var openURL
    @State private var pasted = ""
    @State private var done: Set<Int> = []

    private let steps: [(String, String, String)] = [
        (String(localized: "Crée un projet"), String(localized: "Nom : Kyokasho. Un seul projet suffit, c'est gratuit."),
         "https://console.cloud.google.com/projectcreate"),
        (String(localized: "Active l'API Google Drive"), String(localized: "Bouton « Activer »."),
         "https://console.cloud.google.com/apis/library/drive.googleapis.com"),
        (String(localized: "Écran de connexion"), String(localized: "Nom de l'app : Kyokasho, ton e-mail. Audience : Externe, puis « Publier l'application » (sinon Google te déconnecte tous les 7 jours)."),
         "https://console.cloud.google.com/auth/branding"),
        (String(localized: "Crée l'identifiant"), String(localized: "Type : iOS. ID de bundle : fr.noxygen59.kyokasho. Copie l'« ID client »."),
         "https://console.cloud.google.com/auth/clients/create"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    AtelierLabel(String(localized: "Google Drive · une seule fois"), tint: Atelier.Tint.cloud)
                    Text("Relie ton Drive en 5 minutes").font(Atelier.display(26)).foregroundStyle(Atelier.textPrimary)
                    Text("Google demande que chaque app ait son identifiant. Ouvre chaque étape, fais-la, coche, puis colle l'identifiant en bas.")
                        .foregroundStyle(Atelier.textSecondary)
                }
                ForEach(steps.indices, id: \.self) { i in
                    let step = steps[i]
                    HStack(alignment: .top, spacing: 14) {
                        Button {
                            if done.contains(i) { done.remove(i) } else { done.insert(i) }
                        } label: {
                            ZStack {
                                Circle().fill(done.contains(i) ? Atelier.Tint.cloud : Atelier.surfaceHigh).frame(width: 34, height: 34)
                                if done.contains(i) {
                                    Image(systemName: "checkmark").font(Atelier.font(14, weight: .bold)).foregroundStyle(Atelier.onAccentInk.opacity(0.85))
                                } else {
                                    Text("\(i + 1)").font(Atelier.mono).foregroundStyle(Atelier.textPrimary)
                                }
                            }
                        }
                        .buttonStyle(PressScale())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.0).font(Atelier.font(16, weight: .semibold)).foregroundStyle(Atelier.textPrimary)
                            Text(step.1).font(Atelier.font(14)).foregroundStyle(Atelier.textSecondary)
                        }
                        Spacer()
                        Button {
                            if let url = URL(string: step.2) { openURL(url) }
                            done.insert(i)
                        } label: { Label("Ouvrir", systemImage: "arrow.up.forward.square") }
                            .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.cloud))
                    }
                    .padding(14)
                    .background(Atelier.surfaceHigh.opacity(0.5), in: RoundedRectangle(cornerRadius: Atelier.corner(14), style: .continuous))
                }
                VStack(alignment: .leading, spacing: 10) {
                    AtelierLabel(String(localized: "5 · Colle l'identifiant"), tint: Atelier.Tint.cloud)
                    HStack {
                        TextField("xxxx.apps.googleusercontent.com", text: $pasted)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(Atelier.mono)
                            .padding(12)
                            .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
                        Button {
                            pasted = UIPasteboard.general.string ?? pasted
                        } label: { Label("Coller", systemImage: "doc.on.clipboard") }
                            .buttonStyle(AtelierButtonStyle(tint: Atelier.textSecondary))
                    }
                    if !pasted.isEmpty && !GoogleDrive.isValidClientId(pasted) {
                        Text("Ça ne ressemble pas à un ID client (il finit par .apps.googleusercontent.com).")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    Button { drive.setClientId(pasted) } label: { Label("Enregistrer et continuer", systemImage: "checkmark") }
                        .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.cloud))
                        .disabled(!GoogleDrive.isValidClientId(pasted))
                }
                Text("Pas envie ? Le bouton « Fichiers » marche aussi avec Google Drive si l'app Google Drive est installée sur l'iPad.")
                    .font(.footnote).foregroundStyle(Atelier.textTertiary)
            }
            .padding(28)
        }
        .background(Atelier.canvas)
        .navigationTitle("Google Drive")
        .onAppear { pasted = drive.isConfigured ? drive.clientId : "" }
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
                    NavigationLink("Configurer Google Drive") { DriveSetupHelp() }
                } else if drive.isSignedIn {
                    LabeledContent("Connecté", value: drive.accountEmail ?? String(localized: "compte Google"))
                    Button("Se déconnecter", role: .destructive) { drive.signOut() }
                    NavigationLink("Changer d'identifiant Google") { DriveSetupHelp() }
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
    func importFromDrive(url: URL, file: GoogleDrive.File, language: OCRTargetLanguage? = nil) async throws {
        let importer = importer
        let existing = documents.first { $0.driveFileId == file.id }
        let targetLanguage = language ?? existing.map { OCRTargetLanguage.forDocument($0.id) } ?? .japanese
        // C2.3 : empreinte et métriques du nouveau PDF calculées AVANT le journal, pour qu'une bascule
        // interrompue puisse être finie au lancement suivant depuis le journal seul. Calcul **strict**
        // (revue R2, P2 n°1) : une erreur de fichier refuse la mise à jour au lieu de replacer
        // silencieusement sans journal (revu : un remplacement sans journal ne peut ni effacer l'OCR
        // ni suivre les données). `plan = nil` désigne un seul cas : le même fichier (empreinte
        // identique), un simple changement de révision sans bascule.
        let plan: PageShift.DriveReplacement?
        if let existing {
            plan = try await Task.detached(priority: .userInitiated) {
                let hash = try DocumentImporter.sha256(of: url)
                guard hash != existing.id else { return nil } // même fichier : simple changement de révision
                let (pageCount, _) = try DocumentImporter.inspect(url)
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                guard pageCount > 0, size > 0 else {
                    throw ImportError.unreadable(String(localized: "La nouvelle version du PDF est illisible : mise à jour refusée.", bundle: .main))
                }
                return PageShift.DriveReplacement(source: url, newDocumentId: hash, pageCount: pageCount,
                                                  fileSize: size, driveRevision: file.revision)
            }.value
        } else {
            plan = nil
        }
        let perform = { () async throws -> (document: LibraryDocument, isNew: Bool) in
            try await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                if let existing {
                    // P2 n°1 (revue R2) : l'import attend l'identifiant calculé ci-dessus, et le même
                    // fichier quand `plan` est nil. Un fichier qui change entre les deux calculs (télé
                    // -chargement modifié sous nos pieds) s'arrête ici : jamais de bascule de base
                    // (rekey) sans journal.
                    let updated = try importer.replace(documentId: existing.id, withFileAt: url,
                                                       driveRevision: file.revision,
                                                       replacingInto: plan?.newDocumentId ?? existing.id)
                    return (updated, false)
                }
                let imported = try importer.importFile(at: url, displayName: url.lastPathComponent,
                                                       driveFileId: file.id, driveRevision: file.revision)
                return (imported.document, imported.isNew)
            }.value
        }
        let result: (document: LibraryDocument, isNew: Bool)
        if let existing {
            result = try await PageShift.withDriveReplacement(self, documentId: existing.id,
                                                              replacement: plan, operation: perform)
        } else {
            result = try await perform()
        }
        let document = result.document
        if result.isNew || existing != nil { OCRTargetLanguage.set(targetLanguage, forDocument: document.id) }
        if let existing, existing.id != document.id { OCRTargetLanguage.forget(existing.id) }
        thumbnails.removeAll(for: existing?.id ?? document.id)
        DocumentScan.start(document, url: storage.url(for: document.id), ocr: ocr)
    }

    /// Compare chaque document importé de Drive avec sa version en ligne, télécharge ceux qui ont changé.
    func checkDriveUpdates() async -> String {
        let linked = documents.filter { $0.driveFileId != nil }
        guard !linked.isEmpty else { return String(localized: "Aucun document importé depuis Google Drive.") }
        var updated: [String] = []
        var failures: [String] = []
        // P2 n°4 (revue R2) : les conflits « cible déjà présente » sont visibles dans ce rapport ;
        // les données de l'ancienne version sont mises de côté dans « Conflits-remplacement ».
        var conflicts: [String] = []
        for document in linked {
            guard let fileId = document.driveFileId else { continue }
            do {
                let file = try await GoogleDrive.shared.metadata(fileId: fileId)
                guard file.revision != document.driveRevision else { continue }
                let url = try await GoogleDrive.shared.download(file) { _ in }
                try await importFromDrive(url: url, file: file)
                updated.append(document.title)
                let keptAside = PageShift.consumeReplacementConflicts(for: document.id)
                if keptAside > 0 {
                    conflicts.append(String(localized: "Conflits de remplacement : des données de l'ancienne version de « \(document.title) » (\(keptAside) élément(s)) sont gardées dans « Conflits-remplacement »."))
                }
            } catch {
                failures.append("\(document.title) : \(error.localizedDescription)")
            }
        }
        var lines: [String] = []
        lines.append(updated.isEmpty ? String(localized: "Tout est à jour (\(linked.count) document(s)).") : String(localized: "Mis à jour : ") + updated.joined(separator: ", "))
        if !failures.isEmpty { lines.append(String(localized: "Erreurs : ") + failures.joined(separator: " ; ")) }
        if !conflicts.isEmpty { lines.append(conflicts.joined(separator: " ; ")) }
        return lines.joined(separator: "\n")
    }
}
