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
        installed = Set((ModelSpec.all + [.degan, .ovisocr2GGUF] + ModelSpec.layoutModels).filter { store.isInstalled($0) }.map(\.id))
    }

    func start(_ spec: ModelSpec) {
        guard tasks[spec.id] == nil else { return }
        // Version Mac (#55) : ONNX seulement, sans MLX ; télécharger des Go de modèles inutilisables est refusé.
        guard spec.runsOnThisDevice else {
            errors[spec.id] = "Sur Mac, seuls les modèles ONNX fonctionnent : pour celui-ci, importe les documents en paquet .kyokasho avec leurs lectures."
            return
        }
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
/// Réglages → Modèles : un groupe par usage (à quoi ça sert, où ça se règle), « Recommandé » ou « Optionnel ».
struct OCRModelsSection: View {
    enum Group { case ocr, ai, layout, sharpen }

    let group: Group
    @ObservedObject private var downloads = ModelDownloads.shared
    @State private var deleting: ModelSpec?

    var body: some View {
        Section {
            switch group {
            case .ocr:
                row(.ndlocr, badge: String(localized: "Recommandé"))
                row(.ppocr5, badge: String(localized: "Optionnel"))
            case .ai:
                if localAIAvailable {
                    row(.glmocr, badge: String(localized: "Optionnel"))
                    row(.ovisocr2, badge: String(localized: "Optionnel"))
                    row(.qwen3vl4b, badge: String(localized: "Optionnel · lourd"))
                    row(.qwen35chat4b, badge: String(localized: "Optionnel · chat"))
                } else {
                    row(.ovisocr2GGUF, badge: String(localized: "Optionnel"))
                }
            case .layout:
                ForEach(ModelSpec.layoutModels) { spec in row(spec, badge: String(localized: "Optionnel")) }
            case .sharpen:
                row(.degan, badge: String(localized: "Optionnel"))
            }
        } header: {
            Text(ui: header)
        } footer: {
            Text(ui: footer)
        }
        .confirmationDialog("Supprimer ce modèle ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { if let deleting { downloads.delete(deleting) } }
        } message: {
            Text("Tu pourras le retélécharger. Les pages déjà lues restent en cache.")
        }
    }

    private var header: String {
        switch group {
        case .ocr: return String(localized: "1 · Lire le texte des scans (OCR)")
        case .ai: return localAIAvailable ? String(localized: "3 · Relire et vérifier avec l'IA") : String(localized: "3 · Lire les pages avec l'IA")
        case .layout: return String(localized: "4 · Mise en forme du texte extrait")
        case .sharpen: return String(localized: "5 · Nettoyer les scans")
        }
    }

    private var footer: String {
        switch group {
        case .ocr:
            return String(localized: "Sans modèle, Apple Vision lit déjà le japonais (moins bien). NDLOCR-Lite est fait pour les livres japonais (colonnes verticales). PP-OCRv5 sert aussi à placer chaque caractère pour le dictionnaire. Choix du moteur : Réglages → Lecture des scans, ou le bouton du moteur dans le panneau Texte.")
        case .ai:
            if !localAIAvailable { return String(localized: "Sur ce Mac, le chat et les gros modèles d'IA sont désactivés.") }
            return String(localized: "GLM-OCR relit les lignes douteuses ; OvisOCR2 lit chaque page du livre. Qwen3-VL participe à l'analyse et peut discuter. Qwen3.5-4B est réservé au chat du livre (≈ 3,1 Go à télécharger). Un seul modèle IA est chargé à la fois ; tout reste sur l'iPad.")
        case .layout:
            return String(localized: "Sans modèle, la mise en forme se fait par la géométrie des lignes. Avec un modèle : titres, colonnes, tableaux, légendes repérés sur l'image ; en-têtes et pieds de page écartés. Choix : panneau Texte, mode « Mis en forme » (bouton Géo / PP / YOLO).")
        case .sharpen:
            return String(localized: "Sans modèle, « Papier blanc » et « Noir et blanc net » marchent déjà. DE-GAN rend les caractères noirs et nets sur les vieux scans (moins bon sur les photos). Dans le lecteur : menu « … » → Affichage → Nettoyage des scans.")
        }
    }

    private func row(_ spec: ModelSpec, badge: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(spec.title).font(.body.bold())
                if let badge {
                    Text(badge).font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(badge == String(localized: "Recommandé") ? Atelier.onAccentInk : Color.secondary)
                        .background(badge == String(localized: "Recommandé") ? Color.green : Color.secondary.opacity(0.2), in: Capsule())
                }
                Spacer()
                if downloads.installed.contains(spec.id) {
                    Label("Installé", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                        .font(.caption.bold()).foregroundStyle(.green)
                }
            }
            Text(spec.summary).font(.footnote).foregroundStyle(.secondary)
            Text("Licence : \(spec.license)").font(.caption2).foregroundStyle(.tertiary)
            // Liens sous chaque modèle : projet d'origine et fichier téléchargé.
            if let home = spec.homepage {
                // Style explicite : sans lui, un clic n'importe où sur la ligne suit le lien, même sur un bouton grisé.
                Link(destination: home) { Label(Self.short(home), systemImage: "link").font(.caption2) }
                    .buttonStyle(.borderless)
            }
            // Mac (#55) : l'app télécharge elle-même ; pas de lien qui lance un téléchargement dans le navigateur.
            if localAIAvailable, let file = spec.mainDownload {
                Link(destination: file) { Label(Self.short(file), systemImage: "arrow.down.circle").font(.caption2).lineLimit(1) }
                    .buttonStyle(.borderless)
            }
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
                .disabled(!spec.runsOnThisDevice) // Mac (#55) : modèles MLX inutilisables, téléchargement grisé
                .buttonStyle(.borderless)
            }
            if let error = downloads.errors[spec.id] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    private static func short(_ url: URL) -> String { (url.host ?? "") + url.path }
}

/// Moteurs à proposer dans les menus « Moteur » : ceux qui marchent tout de suite + modèles installés.
enum OCREngineMenu {
    /// Icône du moteur (sélecteur du panneau d'étude).
    static func icon(_ id: String?) -> String {
        switch id {
        case OCREngineID.pdfText: return "doc.plaintext"
        case OCREngineID.vision: return "apple.logo"
        case OCREngineID.ndlocr: return "building.columns"
        case OCREngineID.ppocr5: return "text.viewfinder"
        case OCREngineID.glmocr: return "sparkles"
        default: return "cpu"
        }
    }

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

extension ModelSpec {
    /// MLX n'existe que sur iPad ; les modèles ONNX tournent partout, Mac compris (#55). Ils peuvent avoir des fichiers
    /// annexes (`dict.txt`, `NDLmoji.yaml`) : la présence d'un `.onnx` décide, pas la totalité des fichiers.
    var runsOnThisDevice: Bool { localAIAvailable || files.contains { $0.name.hasSuffix(".onnx") || $0.name.hasSuffix(".gguf") } }
}
