// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import CoreImage
import Foundation
import Hub
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
        case .pdfPage(let url, let index): image = try PageRenderer.render(url: url, pageIndex: index, longSide: 3000)
        case .image(let cg): image = cg
        }
        // 1. Où sont les lignes (et un premier texte, gardé si l'IA ne répond rien).
        let detector = PPOCREngine(store: store)
        let base = detector.isAvailable ? try await detector.recognize(.image(image))
                                        : try await VisionOCREngine().recognize(.image(image))
        // 2. Relecture de chaque ligne par l'IA.
        let model = try await GLMModel.shared.container(directory: store.directory(.glmocr))
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
        return OCRPage(engine: id, lines: lines, durationMs: Int(Date().timeIntervalSince(start) * 1000))
    }

    /// Relit par l'IA **seulement** les lignes données d'un résultat existant (lignes douteuses) ; les autres
    /// restent telles quelles. Une ligne relue n'est plus douteuse.
    public func reread(_ page: OCRPage, lines indices: [Int], input: OCRInput) async throws -> OCRPage {
        guard isAvailable else { throw OCRError.modelMissing(ModelSpec.glmocr.title) }
        let image: CGImage
        switch input {
        case .pdfPage(let url, let index): image = try PageRenderer.render(url: url, pageIndex: index, longSide: 3000)
        case .image(let cg): image = cg
        }
        let model = try await GLMModel.shared.container(directory: store.directory(.glmocr))
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
}

/// Modèle chargé une fois, gardé tant que l'app tourne (chargement ≈ quelques secondes).
actor GLMModel {
    static let shared = GLMModel()
    private var loaded: (URL, ModelContainer)?
    private var registered = false

    func container(directory: URL) async throws -> ModelContainer {
        if let loaded, loaded.0 == directory { return loaded.1 }
        if !registered {
            // GLM-OCR n'est pas dans la liste de mlx-swift-lm 2.29.3 : on l'ajoute (portage local).
            await VLMTypeRegistry.shared.registerModelType("glm_ocr") { url in
                GlmOcr(try JSONDecoder().decode(GlmOcrConfiguration.self, from: Data(contentsOf: url)))
            }
            for name in ["Glm46VProcessor", "GlmOcrProcessor"] {
                await VLMProcessorTypeRegistry.shared.registerProcessorType(name) { url, tokenizer in
                    GlmOcrProcessor(try JSONDecoder().decode(GlmOcrProcessorConfiguration.self, from: Data(contentsOf: url)),
                                    tokenizer: tokenizer)
                }
            }
            registered = true
        }
        // Mémoire GPU de travail limitée : l'iPad garde de la place pour le reste de l'app.
        MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)
        let hub = HubApi(downloadBase: directory.deletingLastPathComponent())
        let container = try await VLMModelFactory.shared.loadContainer(
            hub: hub,
            // Fin de réponse : <|endoftext|> (59246) et <|user|> (59253), cf. `eos_token_id` du modèle.
            configuration: ModelConfiguration(directory: directory, extraEOSTokens: ["<|endoftext|>", "<|user|>", "<|observation|>"]))
        loaded = (directory, container)
        return container
    }

    func unload() {
        loaded = nil
        MLX.GPU.clearCache()
    }

    /// Une ligne d'image → texte (décodage glouton, température 0).
    static func read(_ image: CGImage, container: ModelContainer, maxTokens: Int) async throws -> String {
        // `UserInput(prompt:images:)` de la 2.29.3 perd les images : on passe par `chat`.
        let input = UserInput(chat: [.user("Text Recognition:", images: [.ciImage(CIImage(cgImage: image))])])
        return try await container.perform { context in
            let prepared = try await context.processor.prepare(input: input)
            let result = try MLXLMCommon.generate(
                input: prepared, parameters: GenerateParameters(maxTokens: maxTokens, temperature: 0), context: context
            ) { (_: [Int]) in .more }
            return result.output
        }
    }
}
