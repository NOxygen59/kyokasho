// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import ONNXOCRKit
import SwiftUI

/// Téléchargements des modèles OCR (à la demande, jamais dans l'app).
@MainActor
final class ModelDownloads: ObservableObject {
    static let shared = ModelDownloads()

    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var installed: Set<String> = []
    private var tasks: [String: Task<Void, Never>] = [:]
    let store = ModelStore.shared

    private init() { refresh() }

    func refresh() {
        installed = Set((ModelSpec.all + [.degan]).filter { store.isInstalled($0) }.map(\.id))
    }

    func start(_ spec: ModelSpec) {
        guard tasks[spec.id] == nil else { return }
        errors[spec.id] = nil
        progress[spec.id] = 0
        let store = store
        let percent = PercentGate()
        tasks[spec.id] = Task {
            do {
                try await store.download(spec) { done, total in
                    let fraction = total > 0 ? Double(done) / Double(total) : 0
                    // Écran mis à jour à chaque % gagné, pas à chaque paquet reçu.
                    guard percent.advance(to: Int(fraction * 100)) else { return }
                    Task { @MainActor in
                        // Valeur arrivée après la fin : ignorée (pas de barre fantôme).
                        guard ModelDownloads.shared.tasks[spec.id] != nil else { return }
                        ModelDownloads.shared.progress[spec.id] = fraction
                    }
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                errors[spec.id] = error.localizedDescription
            }
            tasks[spec.id] = nil
            progress[spec.id] = nil
            refresh()
        }
    }

    func cancel(_ spec: ModelSpec) { tasks[spec.id]?.cancel() }

    func delete(_ spec: ModelSpec) {
        ONNXEngines.unload()
        Task { await GLMOCREngine.unload() }
        try? store.delete(spec)
        refresh()
    }
}

/// Réglages → OCR → Modèles.
struct OCRModelsSection: View {
    @ObservedObject private var downloads = ModelDownloads.shared
    @State private var deleting: ModelSpec?

    var body: some View {
        Section {
            ForEach(ModelSpec.all) { spec in row(spec) }
        } header: {
            Text("Modèles à télécharger")
        } footer: {
            Text("Les modèles restent sur l'iPad (Application Support), hors de l'app. Le téléchargement reprend s'il est coupé ; chaque fichier est vérifié (empreinte SHA-256). GLM-OCR utilise PP-OCRv5 (ou Apple Vision) pour trouver les lignes, puis relit chacune avec l'IA.")
        }
        Section {
            row(.degan)
        } header: {
            Text("Netteté des scans")
        } footer: {
            Text("Après le téléchargement : dans le lecteur, menu de la page → « Netteté des scans ». Seulement les pages scannées, une page à la fois quand elle s'affiche ; le résultat est gardé.")
        }
        .confirmationDialog("Supprimer ce modèle ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { if let deleting { downloads.delete(deleting) } }
        } message: {
            Text("Tu pourras le retélécharger. Les pages déjà lues restent en cache.")
        }
    }

    private func row(_ spec: ModelSpec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(spec.title).font(.body.bold())
                Spacer()
                if downloads.installed.contains(spec.id) {
                    Label("Installé", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                        .font(.caption.bold()).foregroundStyle(.green)
                }
            }
            Text(spec.summary).font(.footnote).foregroundStyle(.secondary)
            Text("Licence : \(spec.license)").font(.caption2).foregroundStyle(.tertiary)
            if let p = downloads.progress[spec.id] {
                HStack {
                    ProgressView(value: p)
                    Text("\(Int(p * 100)) %").font(.caption.monospacedDigit())
                    Button("Annuler") { downloads.cancel(spec) }.buttonStyle(.borderless)
                }
            } else if downloads.installed.contains(spec.id) {
                Button("Supprimer (\(size(downloads.store.installedSize(spec))))", role: .destructive) { deleting = spec }
                    .buttonStyle(.borderless)
            } else {
                Button { downloads.start(spec) } label: {
                    Label("Télécharger (\(size(spec.totalSize)))", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
            }
            if let error = downloads.errors[spec.id] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

/// Moteurs à proposer dans les menus « Moteur » : ceux qui marchent tout de suite + modèles installés.
enum OCREngineMenu {
    static var extra: [String] {
        [OCREngineID.ndlocr, OCREngineID.ppocr5, OCREngineID.glmocr].filter { OCRService.engine($0)?.isAvailable == true }
    }
}

/// Laisse passer une valeur seulement quand le pourcentage change (appelé depuis le fil du téléchargement).
private final class PercentGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1

    func advance(to value: Int) -> Bool {
        lock.withLock {
            guard value != last else { return false }
            last = value
            return true
        }
    }
}
