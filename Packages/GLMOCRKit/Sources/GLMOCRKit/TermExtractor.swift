// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import MLX
import MLXLMCommon
import OCRKit
import ReaderCore

/// Relevé des termes du métier dans une page déjà lue (lexique du design d'intérieur, #50 lot D4) : une ligne
/// « terme | lecture en hiragana | sens » par terme. Au choix de NOxygen59 (recette 1.3.2 (67), D8) : le modèle
/// (Qwen3-VL ou Qwen3.5) et la langue des sens. La consigne est écrite **dans la langue voulue**, avec un exemple :
/// avec une consigne anglaise, Qwen répondait en anglais même quand on demandait le français. Résultat : une
/// proposition, toujours validée par NOxygen59.
public enum TermExtractor {
    public enum Language: String, CaseIterable, Sendable { case french = "fr", english = "en" }

    /// Modèles capables de cette tâche (texte seul).
    public static let models: [ModelSpec] = [.qwen3vl4b, .qwen35chat4b]

    public static func isAvailable(_ model: ModelSpec, store: ModelStore = .shared) -> Bool { store.isInstalled(model) }

    /// Consigne de la tâche, dans la langue de sortie (exposée pour les tests).
    public static func prompt(markdown: String, known: [String], language: Language) -> String {
        let skip = known.filter { markdown.contains($0) }.prefix(80).joined(separator: "、")
        switch language {
        case .french:
            return """
            Voici une page d'un manuel japonais de design d'intérieur et de construction (coordinateur d'intérieur).
            Relève les termes techniques du métier présents sur la page (matériaux, éléments, méthodes de construction, outils, styles).
            Une ligne par terme, exactement : terme | lecture en hiragana | sens court EN FRANÇAIS
            Exemple : 框 | かまち | cadre (montants et traverses)
            Règles : seulement des termes écrits sur la page ; pas de mots courants ; 25 lignes au plus ; le sens toujours en français, jamais en anglais ; aucun autre texte.
            \(skip.isEmpty ? "" : "Déjà connus, ne pas lister : " + skip + "\n")
            Page :
            \(markdown)
            """
        case .english:
            return """
            This is a page of a Japanese textbook on interior design and building (interior coordinator).
            List the technical terms of the trade that appear on the page (materials, parts, construction methods, tools, styles).
            One line per term, exactly: term | reading in hiragana | short English meaning
            Example: 框 | かまち | frame (stiles and rails)
            Rules: only terms written on the page; no common everyday words; at most 25 lines; no other text.
            \(skip.isEmpty ? "" : "Already known, do not list: " + skip + "\n")
            Page:
            \(markdown)
            """
        }
    }

    public static func extract(markdown: String, known: [String] = [], language: Language, model: ModelSpec,
                               store: ModelStore = .shared, maxTokens: Int = 1200) async throws -> String {
        guard models.contains(where: { $0.id == model.id }) else { throw OCRError.engineFailed("Ce modèle ne sait pas relever des termes.") }
        guard store.isInstalled(model) else { throw OCRError.modelMissing(model.title) }
        if let free = PageVLMReader.availableMemory(), free < 3_800 * 1_048_576 {
            throw OCRError.engineFailed("Pas assez de mémoire libre pour \(model.title) (\(free / 1_048_576) Mo libres).")
        }
        // Qwen3.5 : pas de « réflexion » affichée, réponse directe.
        let context: [String: any Sendable]? = model.id == ModelSpec.qwen35chat4b.id ? ["enable_thinking": false] : nil
        let user = UserInput(chat: [.user(prompt(markdown: markdown, known: known, language: language))], additionalContext: context)
        return try await GLMModel.using(directory: store.directory(model), extraEOSTokens: []) { container in
            try await withError {
                try await container.perform { ctx in
                    let prepared = try await ctx.processor.prepare(input: user)
                    let result = try MLXLMCommon.generate(
                        input: prepared, parameters: GenerateParameters(maxTokens: maxTokens, temperature: 0), context: ctx
                    ) { (_: [Int]) in Task.isCancelled ? .stop : .more }
                    return result.output
                }
            }
        }
    }
}
