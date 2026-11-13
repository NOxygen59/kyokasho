// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import SwiftUI
import UniformTypeIdentifiers

/// Réglage propriétaire (PLAN-MODLOC-001, E2 ; DEC-02 = A) : importer un modèle MLX choisi dans Fichiers, le voir et le
/// supprimer. Affiché seulement en mode propriétaire déverrouillé. Vérification, déplacement (copie si iOS l'impose) et
/// tout-ou-rien : `LocalModels` (testé sur Mac). Travail sur le disque hors du fil principal.
struct LocalModelsSection: View {
    @State private var models: [LocalModels.Info] = []
    @State private var choosing = false
    @State private var working = false
    @State private var message: String?
    @State private var deleting: LocalModels.Info?

    private var root: URL { ModelStore.shared.root }

    var body: some View {
        Section {
            ForEach(models) { info in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: info.name)
                    Text(verbatim: "\(info.modelType) · \(ByteCountFormatter.string(fromByteCount: info.size, countStyle: .file))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button(role: .destructive) { deleting = info } label: { Label("Supprimer", systemImage: "trash") }
                }
                .contextMenu {
                    Button(role: .destructive) { deleting = info } label: { Label("Supprimer", systemImage: "trash") }
                }
            }
            Button { choosing = true } label: {
                Label(working ? String(localized: "Import en cours…") : String(localized: "Importer un modèle MLX…"),
                      systemImage: "square.and.arrow.down")
            }
            .disabled(working)
            if working { ProgressView() }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Modèles importés")
        } footer: {
            Text("Choisis le dossier d'un modèle MLX de la famille Qwen3.5. Il est vérifié, puis déplacé dans l'app (pas de double place) ; copié seulement si iOS refuse le déplacement. Il apparaît ensuite dans le chat.")
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { Task { await importFolder(url) } }
        }
        .confirmationDialog(String(localized: "Supprimer ce modèle ?"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { if let deleting { Task { await delete(deleting) } } }
        } message: {
            Text("Ses fichiers sont effacés de l'iPad. Les conversations sont gardées.")
        }
        .task { await reload(cleaning: true) }
    }

    private func importFolder(_ url: URL) async {
        working = true
        message = nil
        defer { working = false }
        let root = root
        let result = await Task.detached(priority: .userInitiated) { () -> Result<(LocalModels.Info, LocalModels.Method), Error> in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            return Result { try LocalModels.install(url, into: root) }
        }.value
        switch result {
        case .success(let (info, method)):
            message = method == .moved
                ? String(localized: "« \(info.name) » importé (déplacé dans l'app).")
                : String(localized: "« \(info.name) » importé (copié : iOS n'a pas permis de le déplacer ; tu peux effacer l'original).")
        case .failure(let error):
            message = String(localized: "Import refusé : \(error.localizedDescription)")
        }
        await reload(cleaning: false)
    }

    private func delete(_ info: LocalModels.Info) async {
        let root = root
        // Comme pour un modèle officiel : déchargé avant d'effacer ses fichiers.
        await GLMOCREngine.unload(directory: root.appendingPathComponent(info.id, isDirectory: true))
        do { try LocalModels.delete(info.id, in: root) } catch { message = error.localizedDescription }
        await reload(cleaning: false)
    }

    private func reload(cleaning: Bool) async {
        let root = root
        let (recovered, list) = await Task.detached(priority: .utility) {
            // Nettoyage d'abord (une préparation récupérée n'est pas un modèle), puis la liste.
            (cleaning ? LocalModels.removeLeftovers(in: root) : [], LocalModels.installed(in: root))
        }.value
        models = list
        // Le chat et les réglages lisent la liste des modèles installés : elle suit l'import et la suppression (E3).
        ModelDownloads.shared.refresh()
        if !recovered.isEmpty {
            message = String(localized: "Import interrompu retrouvé : dossier gardé dans « \(recovered.map(\.lastPathComponent).joined(separator: ", ")) ».")
        }
    }
}

