// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import MorphologyKit
import OCRKit
import ReaderCore
import SwiftUI

/// MeCab + UniDic : téléchargement (Réglages → Modèles), chargement au lancement, branchement sur les furigana
/// (page et panneau). Sans lui, les lectures viennent de l'analyseur d'iOS.
@MainActor
final class MorphologyService: ObservableObject {
    static let shared = MorphologyService()

    enum State: Equatable { case absent, downloading(Double), unpacking, ready, failed(String) }

    @Published private(set) var state: State = .absent
    private(set) var mecab: MeCab?
    private var task: Task<Void, Never>?
    private var observation: NSKeyValueObservation?

    static var directory: URL { ModelStore.shared.root.appendingPathComponent("unidic", isDirectory: true) }

    var installedSize: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Au lancement : charge MeCab si le dictionnaire est là (hors du fil principal).
    func loadIfInstalled() {
        guard UniDic.isInstalled(at: Self.directory), mecab == nil else {
            if mecab == nil { state = .absent }
            return
        }
        let dir = Self.directory
        Task {
            let result = await Task.detached(priority: .utility) { Result { try MeCab(dictionary: dir) } }.value
            switch result {
            case .success(let m): install(m)
            case .failure(let e): state = .failed(e.localizedDescription)
            }
        }
    }

    private func install(_ m: MeCab) {
        mecab = m
        Furigana.analyzer = { text in m.tokens(text).map { ($0.range, $0.reading) } }
        // Furigana déjà calculés avec l'ancien analyseur : à refaire.
        FuriganaLayer.clearMemory()
        state = .ready
    }

    func download() {
        if case .downloading = state { return }
        state = .downloading(0)
        task = Task {
            do {
                let archive = try await fetch()
                state = .unpacking
                let dir = Self.directory
                try await Task.detached(priority: .userInitiated) {
                    defer { try? FileManager.default.removeItem(at: archive) }
                    guard try ModelStore.sha256(of: archive) == UniDic.archiveSHA256 else {
                        throw ModelStore.StoreError.badChecksum("unidic-lite-1.0.8.tar.gz")
                    }
                    try UniDic.extract(archive: archive, to: dir)
                }.value
                let m = try await Task.detached(priority: .userInitiated) { try MeCab(dictionary: dir) }.value
                try Task.checkCancellation()
                install(m)
            } catch {
                // Annulé (tâche ou téléchargement coupé) : pas d'erreur rouge, on revient à « à télécharger ».
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                    state = .absent
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        observation = nil
        state = .absent
    }

    func delete() {
        Furigana.analyzer = nil
        mecab = nil
        FuriganaLayer.clearMemory()
        try? FileManager.default.removeItem(at: Self.directory)
        state = .absent
    }

    private func fetch() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let download = URLSession.shared.downloadTask(with: UniDic.archiveURL) { temp, response, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let temp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                        continuation.resume(throwing: ModelStore.StoreError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0))
                        return
                    }
                    // Le fichier temporaire disparaît au retour : on le garde ailleurs.
                    let kept = FileManager.default.temporaryDirectory.appendingPathComponent("unidic-lite.tar.gz")
                    try? FileManager.default.removeItem(at: kept)
                    do { try FileManager.default.moveItem(at: temp, to: kept); continuation.resume(returning: kept) }
                    catch { continuation.resume(throwing: error) }
                }
                observation = download.progress.observe(\.fractionCompleted) { progress, _ in
                    let value = progress.fractionCompleted
                    Task { @MainActor in
                        if case .downloading = self.state { self.state = .downloading(value) }
                    }
                }
                currentDownload = download
                download.resume()
            }
        } onCancel: {
            Task { @MainActor in self.currentDownload?.cancel() }
        }
    }

    private var currentDownload: URLSessionDownloadTask?
}

/// Réglages → Modèles : analyseur japonais.
struct MorphologySection: View {
    @ObservedObject private var service = MorphologyService.shared

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("MeCab + UniDic-lite").font(.body.bold())
                    Text("Recommandé").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(Color.black).background(Color.green, in: Capsule())
                    Spacer()
                    if service.state == .ready {
                        Label("Installé", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green)
                    }
                }
                Text("Analyseur japonais : lectures des furigana selon le contexte (今日, 上手, 一日…) et découpage en mots. Remplace l'analyseur d'iOS dès qu'il est installé.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Licences : MeCab BSD, UniDic BSD (UniDic Consortium), unidic-lite MIT (Paul McCann)").font(.caption2).foregroundStyle(.tertiary)
                Link(destination: UniDic.homepage) { Label("github.com/polm/unidic-lite", systemImage: "link").font(.caption2) }
                switch service.state {
                case .downloading(let p):
                    HStack {
                        ProgressView(value: p)
                        Text("\(Int(p * 100)) %").font(.caption.monospacedDigit())
                        Button("Annuler") { service.cancel() }.buttonStyle(.borderless)
                    }
                case .unpacking:
                    HStack { ProgressView(); Text("Décompression…").font(.caption) }
                case .ready:
                    Button("Supprimer (\(ByteCountFormatter.string(fromByteCount: service.installedSize, countStyle: .file)))", role: .destructive) {
                        service.delete()
                    }
                    .buttonStyle(.borderless)
                case .absent, .failed:
                    Button { service.download() } label: {
                        Label("Télécharger (47 Mo, ≈ 260 Mo une fois installé)", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderless)
                }
                if case .failed(let message) = service.state { Text(message).font(.caption).foregroundStyle(.red) }
            }
            .padding(.vertical, 4)
        } header: {
            Text("2 · Furigana et découpage des mots")
        } footer: {
            Text("Conseillé. Sert partout où il y a des furigana (page, panneau Texte) et à la relecture de l'OCR. Téléchargé depuis PyPI (unidic-lite 1.0.8), empreinte SHA-256 vérifiée ; lu à la demande, peu de mémoire vive malgré sa taille.")
        }
    }
}
