// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import CoreImage
import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import OCRKit

/// OvisOCR2 (famille Qwen3.5, reconnue par mlx-swift-lm) : une page entière → Markdown dans l'ordre de lecture.
/// Utilisé seulement à la demande, pour vérifier le texte OCR (`OCRReferenceDiff`). Jamais testé sur le Mac
/// (choix de l'utilisateur) : premier essai réel sur l'iPad.
public struct OvisOCR2Reader: Sendable {
    let store: ModelStore

    public init(store: ModelStore = .shared) { self.store = store }

    /// Libère OvisOCR2 seulement (GLM-OCR, s'il est chargé, reste).
    public func unload() async { await GLMModel.shared.unload(directory: store.directory(.ovisocr2)) }

    public var isAvailable: Bool { store.isInstalled(.ovisocr2) }

    /// Consigne officielle du modèle (carte Hugging Face de la conversion MLX), sans réflexion.
    static let prompt = "Extract all readable content from the image in natural human reading order and output the result as a single Markdown document. For charts or images, represent them using an HTML image tag: <img src=\"images/bbox_{left}_{top}_{right}_{bottom}.jpg\" />, where left, top, right, bottom are bounding box coordinates scaled to [0, 1000). Format formulas as LaTeX. Format tables as HTML: <table>...</table>. Transcribe all other text as standard Markdown. Preserve the original text without translation or paraphrasing."

    /// Page PDF (repère tourné comme les autres moteurs) → Markdown. Long côté 1600 px : assez pour du texte de
    /// manuel, sans exploser le nombre de jetons d'image (mémoire de l'iPad).
    public func read(_ input: OCRInput, longSide: Int = 1600, maxTokens: Int = 4096) async throws -> String {
        guard isAvailable else { throw OCRError.modelMissing(ModelSpec.ovisocr2.title) }
        let image: CGImage
        switch input {
        case .pdfPage(let url, let index): image = try PageRenderer.render(url: url, pageIndex: index, longSide: longSide)
        case .image(let cg): image = cg
        }
        let container = try await GLMModel.shared.container(directory: store.directory(.ovisocr2), extraEOSTokens: [])
        let user = UserInput(chat: [.user(Self.prompt, images: [.ciImage(CIImage(cgImage: image))])],
                             additionalContext: ["enable_thinking": false])
        return try await container.perform { context in
            let prepared = try await context.processor.prepare(input: user)
            let result = try MLXLMCommon.generate(
                input: prepared, parameters: GenerateParameters(maxTokens: maxTokens, temperature: 0), context: context
            ) { (_: [Int]) in Task.isCancelled ? .stop : .more }
            return result.output
        }
    }
}
