// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import CoreImage
import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import OCRKit

/// Modèle vision-langage (mlx-swift-lm) qui lit une page entière → Markdown dans l'ordre de lecture.
/// Utilisé à la demande (vérification de la double page, analyse du document entier). Un seul modèle MLX en
/// mémoire à la fois (`GLMModel`).
public struct PageVLMReader: Sendable {
    let spec: ModelSpec
    let prompt: String
    let context: [String: any Sendable]?
    let longSide: Int
    /// Mémoire libre exigée avant de charger le modèle (sinon erreur claire plutôt qu'un arrêt par iOS).
    let minimumFreeMemory: UInt64
    let store: ModelStore

    public var isAvailable: Bool { store.isInstalled(spec) }

    public func read(_ input: OCRInput, maxTokens: Int = 4096) async throws -> String {
        guard isAvailable else { throw OCRError.modelMissing(spec.title) }
        if let free = Self.availableMemory(), free < minimumFreeMemory {
            throw OCRError.engineFailed("Pas assez de mémoire libre pour \(spec.title) (\(free / 1_048_576) Mo libres, \(minimumFreeMemory / 1_048_576) Mo nécessaires). Ferme les autres apps et réessaie.")
        }
        let image: CGImage
        switch input {
        case .pdfPage(let url, let index): image = try PageRenderer.render(url: url, pageIndex: index, longSide: longSide)
        case .image(let cg): image = cg
        }
        let container = try await GLMModel.shared.container(directory: store.directory(spec), extraEOSTokens: [])
        let user = UserInput(chat: [.user(prompt, images: [.ciImage(CIImage(cgImage: image))])], additionalContext: context)
        return try await container.perform { context in
            let prepared = try await context.processor.prepare(input: user)
            let result = try MLXLMCommon.generate(
                input: prepared, parameters: GenerateParameters(maxTokens: maxTokens, temperature: 0), context: context
            ) { (_: [Int]) in Task.isCancelled ? .stop : .more }
            return result.output
        }
    }

    /// Libère ce modèle seulement (un autre, s'il est chargé, reste).
    public func unload() async { await GLMModel.shared.unload(directory: store.directory(spec)) }

    /// Mémoire encore disponible pour l'app (iOS), `nil` ailleurs.
    static func availableMemory() -> UInt64? {
        #if os(iOS)
        let value = os_proc_available_memory()
        return value > 0 ? UInt64(value) : nil
        #else
        return nil
        #endif
    }
}

/// OvisOCR2 (famille Qwen3.5) : spécialiste de l'OCR japonais, 0,9 milliard de paramètres.
public struct OvisOCR2Reader: Sendable {
    let base: PageVLMReader

    public init(store: ModelStore = .shared) {
        base = PageVLMReader(spec: .ovisocr2, prompt: Self.prompt, context: ["enable_thinking": false],
                             longSide: 1600, minimumFreeMemory: 1_800 * 1_048_576, store: store)
    }

    public var isAvailable: Bool { base.isAvailable }

    /// Consigne officielle du modèle (carte Hugging Face de la conversion MLX), sans réflexion.
    static let prompt = "Extract all readable content from the image in natural human reading order and output the result as a single Markdown document. For charts or images, represent them using an HTML image tag: <img src=\"images/bbox_{left}_{top}_{right}_{bottom}.jpg\" />, where left, top, right, bottom are bounding box coordinates scaled to [0, 1000). Format formulas as LaTeX. Format tables as HTML: <table>...</table>. Transcribe all other text as standard Markdown. Preserve the original text without translation or paraphrasing."

    public func read(_ input: OCRInput, maxTokens: Int = 4096) async throws -> String { try await base.read(input, maxTokens: maxTokens) }
    public func unload() async { await base.unload() }
}

/// Qwen3-VL-4B-Instruct (Alibaba, 4 milliards de paramètres, 4 bits) : le « gros » lecteur de l'analyse du
/// document entier. Comprend le sens : utile sur les termes techniques (manuels japonais d'architecture et de
/// design d'intérieur). Lourd : ≈ 3,5 Go de mémoire pendant la lecture.
public struct Qwen3VLReader: Sendable {
    let base: PageVLMReader

    public init(store: ModelStore = .shared) {
        base = PageVLMReader(spec: .qwen3vl4b, prompt: Self.prompt, context: nil,
                             longSide: 1400, minimumFreeMemory: 3_800 * 1_048_576, store: store)
    }

    public var isAvailable: Bool { base.isAvailable }

    static let prompt = """
    This is a page of a Japanese textbook about architecture and interior design (interior coordinator). \
    Transcribe ALL the Japanese text on the page exactly as printed, in natural reading order (vertical text: \
    right-to-left columns). Keep technical terms exactly (e.g. 天井, 照明器具, 建具, 野縁, 吊り木). \
    Output plain Markdown only: headings with #, tables as HTML. Do not translate, explain, summarize or correct.
    """

    public func read(_ input: OCRInput, maxTokens: Int = 4096) async throws -> String { try await base.read(input, maxTokens: maxTokens) }
    public func unload() async { await base.unload() }
}
