// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import CoreImage
import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import OCRKit
import ONNXOCRKit

/// GLM-OCR (Zhipu AI, MIT), modèle IA de 0,9 milliard de paramètres, version MLX 4 bits.
/// Il ne donne pas la position du texte : les lignes viennent de PP-OCRv5 (ou d'Apple Vision),
/// puis l'IA relit chaque ligne (« Text Recognition: »). Précis, mais plusieurs secondes par page.
public struct GLMOCREngine: OCREngine {
    public let id = OCREngineID.glmocr
    let store: ModelStore

    public init(store: ModelStore = .shared) {
        self.store = store
    }

    public var isAvailable: Bool { store.isInstalled(.glmocr) }

    public func recognize(_ input: OCRInput) async throws -> OCRPage {
        guard isAvailable else { throw OCRError.modelMissing(ModelSpec.glmocr.title) }
        let start = Date()
        let image: CGImage
        switch input {
        case .pdfPage(let url, let index, let rotation):
            image = try PageRenderer.render(url: url, pageIndex: index, longSide: 3000, additionalRotation: rotation)
        case .image(let cg): image = cg
        }
        // 1. Où sont les lignes (et un premier texte, gardé si l'IA ne répond rien).
        let detector = PPOCREngine(store: store)
        let base = detector.isAvailable ? try await detector.recognize(.image(image))
                                        : try await VisionOCREngine().recognize(.image(image))
        // 2. Relecture de chaque ligne par l'IA.
        let lines: [OCRLine] = try await GLMModel.using(directory: store.directory(.glmocr)) { model in
        var lines: [OCRLine] = []
        // FDR-7 : une génération par ligne → grouper 3-5 lignes voisines par image, découper la réponse par \n. Voir § 6 étape 7.
        for line in base.lines {
            try Task.checkCancellation()
            guard let crop = Self.crop(image, line.box, margin: line.vertical ? 0.5 : 0.15) else { lines.append(line); continue }
            let read = try await GLMModel.read(crop, container: model, maxTokens: max(24, line.text.count * 3 + 8))
            let text = Self.clean(read)
            guard !text.isEmpty else { lines.append(line); continue }
            let charBoxes = text.count == line.text.count && line.charBoxes.count == text.count
                ? line.charBoxes : CharacterLayout.proportional(text, in: line.box, vertical: line.vertical)
            lines.append(OCRLine(text: text, box: line.box, charBoxes: charBoxes, measuredCharBoxes: false,
                                 vertical: line.vertical, confidence: line.confidence))
        }
        return lines
        }
        return OCRPage(engine: id, lines: lines, durationMs: Int(Date().timeIntervalSince(start) * 1000))
    }

    /// Relit par l'IA **seulement** les lignes données d'un résultat existant (lignes douteuses) ; les autres
    /// restent telles quelles. Une ligne relue n'est plus douteuse.
    public func reread(_ page: OCRPage, lines indices: [Int], input: OCRInput) async throws -> OCRPage {
        guard isAvailable else { throw OCRError.modelMissing(ModelSpec.glmocr.title) }
        let image: CGImage
        switch input {
        case .pdfPage(let url, let index, let rotation):
            image = try PageRenderer.render(url: url, pageIndex: index, longSide: 3000, additionalRotation: rotation)
        case .image(let cg): image = cg
        }
        return try await GLMModel.using(directory: store.directory(.glmocr)) { model in
        var page = page
        for i in indices where page.lines.indices.contains(i) {
            try Task.checkCancellation()
            let line = page.lines[i]
            guard let crop = Self.crop(image, line.box, margin: line.vertical ? 0.5 : 0.15) else { continue }
            let text = Self.clean(try await GLMModel.read(crop, container: model, maxTokens: max(24, line.text.count * 3 + 8)))
            guard !text.isEmpty else { continue }
            if text != line.text {
                page.lines[i].text = text
                if text.count != line.charBoxes.count {
                    page.lines[i].charBoxes = CharacterLayout.proportional(text, in: line.box, vertical: line.vertical)
                    page.lines[i].measuredCharBoxes = false
                }
            }
            page.lines[i].doubt = []
        }
        page.reread = true
        return page
        }
    }

    /// Ligne découpée avec une marge (l'IA lit mieux avec de l'air autour ; plus large pour les colonnes).
    static func crop(_ image: CGImage, _ box: NormBox, margin fraction: Double) -> CGImage? {
        let w = Double(image.width), h = Double(image.height)
        let margin = min(box.w * w, box.h * h) * fraction + 2
        let rect = CGRect(x: box.x * w - margin, y: box.y * h - margin, width: box.w * w + 2 * margin, height: box.h * h + 2 * margin)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard rect.width >= 4, rect.height >= 4 else { return nil }
        return image.cropping(to: rect)
    }

    /// Texte brut : sans balises du modèle, sans mise en forme Markdown, sur une ligne.
    static func clean(_ s: String) -> String {
        var t = s
        for tag in ["<|end_of_box|>", "<|begin_of_box|>", "<|endoftext|>", "<|user|>", "<|assistant|>"] {
            t = t.replacingOccurrences(of: tag, with: "")
        }
        // Le modèle ouvre parfois un bloc de code Markdown après le texte : on coupe là.
        if let fence = t.range(of: "```") { t = String(t[..<fence.lowerBound]) }
        t = t.replacingOccurrences(of: "\n", with: "").trimmingCharacters(in: .whitespaces)
        while let first = t.first, "#*>-".contains(first) { t.removeFirst(); t = t.trimmingCharacters(in: .whitespaces) }
        return t.replacingOccurrences(of: "**", with: "")
    }

    /// Libère la mémoire (≈ 1,5 Go) : avertissement mémoire, modèle supprimé.
    public static func unload() async { await GLMModel.shared.unload() }

    /// État des modèles MLX (un seul chargé à la fois).
    public static func status() async -> AIModelStatus { await GLMModel.shared.status() }

    /// Libère ce modèle s'il est chargé (bouton « Décharger » des Réglages).
    public static func unload(directory: URL) async { await GLMModel.shared.unload(directory: directory) }

    /// Libère le modèle seulement si aucune lecture n'est en cours (retour à la bibliothèque, app en arrière-plan).
    public static func unloadIfIdle() async { await GLMModel.shared.unloadIfIdle() }
}

public struct AIModelStatus: Sendable {
    public let loaded: URL?
    public let loading: URL?
    /// Une lecture (ou le chat) s'en sert en ce moment.
    public let inUse: Bool
    public let lastUse: [URL: Date]
    /// Mémoire du GPU tenue par MLX (poids et calculs) et cache de travail, en Mo.
    public let gpuActiveMB: Int
    public let gpuCacheMB: Int
}

/// Modèle chargé à la demande (chargement ≈ quelques secondes), libéré après `idleDelay` sans lecture.
actor GLMModel {
    static let shared = GLMModel()
    /// Sans lecture pendant ce temps, le modèle est libéré (≈ 1,5 à 3 Go rendus à l'iPad).
    static let idleDelay: Duration = .seconds(45)
    private var loaded: (URL, ModelContainer)?
    /// Lectures en cours : jamais de libération pour inactivité tant qu'il y en a une.
    private var users = 0
    private var idleTask: Task<Void, Never>?
    /// Dernière utilisation de chaque modèle (page de chaque IA dans les Réglages).
    private var lastUse: [URL: Date] = [:]
    /// Chargement en cours : un second appel pour le même modèle attend celui-ci (jamais deux chargements).
    private var loading: (URL, Task<ModelContainer, Error>)?

    /// Un seul modèle en mémoire à la fois (GLM-OCR ou OvisOCR2) : changer de dossier libère l'autre.
    func container(directory: URL, extraEOSTokens: Set<String> = ["<|endoftext|>", "<|user|>", "<|observation|>"]) async throws -> ModelContainer {
        if let loaded, loaded.0 == directory { return loaded.1 }
        if let loading, loading.0 == directory { return try await loading.1.value }
        loading?.1.cancel()
        if loaded != nil { loaded = nil; MLX.GPU.clearCache() }
        // Mémoire GPU de travail limitée : l'iPad garde de la place pour le reste de l'app.
        MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)
        let task = Task {
            try await VLMModelFactory.shared.loadContainer(
                from: LocalOnly(), using: TransformersTokenizerLoader(),
                // Fin de réponse GLM : <|endoftext|> (59246) et <|user|> (59253), cf. `eos_token_id` du modèle.
                configuration: ModelConfiguration(directory: directory, extraEOSTokens: extraEOSTokens))
        }
        loading = (directory, task)
        let container = try await task.value
        // Pendant le chargement, un autre modèle a pu être demandé ou la mémoire libérée : on ne garde pas celui-ci.
        guard loading?.0 == directory, !task.isCancelled else { return container }
        loading = nil
        loaded = (directory, container)
        return container
    }

    /// Prête le modèle à `body` le temps d'une lecture : compté comme utilisé, puis cache GPU vidé et libération
    /// programmée après `idleDelay` si plus personne ne s'en sert.
    static func using<T>(directory: URL, extraEOSTokens: Set<String> = ["<|endoftext|>", "<|user|>", "<|observation|>"],
                         _ body: (ModelContainer) async throws -> T) async throws -> T {
        let container = try await shared.acquire(directory: directory, extraEOSTokens: extraEOSTokens)
        do {
            let result = try await body(container)
            await shared.release()
            return result
        } catch {
            await shared.release()
            throw error
        }
    }

    func acquire(directory: URL, extraEOSTokens: Set<String>) async throws -> ModelContainer {
        users += 1
        lastUse[directory] = Date()
        idleTask?.cancel()
        idleTask = nil
        do { return try await container(directory: directory, extraEOSTokens: extraEOSTokens) } catch {
            release()
            throw error
        }
    }

    func release() {
        users = max(0, users - 1)
        // Mémoire de travail de la lecture (images, cache clé-valeur) rendue tout de suite.
        MLX.GPU.clearCache()
        guard users == 0 else { return }
        idleTask?.cancel()
        idleTask = Task {
            try? await Task.sleep(for: Self.idleDelay)
            guard !Task.isCancelled else { return }
            self.unloadIfIdle()
        }
    }

    func unloadIfIdle() {
        guard users == 0, loaded != nil || loading != nil else { return }
        unload()
    }

    func status() -> AIModelStatus {
        AIModelStatus(loaded: loaded?.0, loading: loading?.0, inUse: users > 0, lastUse: lastUse,
                      gpuActiveMB: MLX.GPU.activeMemory / 1_048_576, gpuCacheMB: MLX.GPU.cacheMemory / 1_048_576)
    }

    /// Libère le modèle (tous, ou seulement s'il s'agit de `directory`).
    func unload(directory: URL? = nil) {
        if let directory, loaded?.0 != directory, loading?.0 != directory { return }
        loading?.1.cancel()
        loading = nil
        loaded = nil
        MLX.GPU.clearCache()
    }

    /// Une ligne d'image → texte (décodage glouton, température 0).
    static func read(_ image: CGImage, container: ModelContainer, maxTokens: Int) async throws -> String {
        // `UserInput(prompt:images:)` de la 2.29.3 perd les images : on passe par `chat`.
        let input = UserInput(chat: [.user("Text Recognition:", images: [.ciImage(CIImage(cgImage: image))])])
        // Erreur MLX pendant la lecture → erreur Swift (pas d'arrêt de l'app).
        return try await withError { try await container.perform { context in
            let prepared = try await context.processor.prepare(input: input)
            let result = try MLXLMCommon.generate(
                input: prepared, parameters: GenerateParameters(maxTokens: maxTokens, temperature: 0), context: context
            ) { (_: [Int]) in Task.isCancelled ? .stop : .more }
            return result.output
        } }
    }
}
