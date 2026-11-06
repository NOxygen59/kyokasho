// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import CoreImage
import Foundation
#if canImport(MLXVLM)
import MLX
import MLXLMCommon
import MLXVLM
#endif
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
            throw OCRError.engineFailed(String(localized: "Pas assez de mémoire libre pour \(spec.title) (\(free / 1_048_576) Mo libres, \(minimumFreeMemory / 1_048_576) Mo nécessaires). Ferme les autres apps et réessaie.", bundle: .main))
        }
        let image: CGImage
        switch input {
        case .pdfPage(let url, let index, let rotation):
            image = try PageRenderer.render(url: url, pageIndex: index, longSide: longSide, additionalRotation: rotation)
        case .image(let cg): image = cg
        }
        #if canImport(MLXVLM)
        let user = UserInput(chat: [.user(prompt, images: [.ciImage(CIImage(cgImage: image))])], additionalContext: context)
        // Une erreur MLX (mémoire, noyau Metal) pendant la lecture devient une erreur Swift : la page est notée en
        // erreur au lieu d'arrêter l'app.
        return try await GLMModel.using(directory: store.directory(spec), extraEOSTokens: []) { container in
        try await withError {
            try await container.perform { context in
                let prepared = try await context.processor.prepare(input: user)
                let result = try MLXLMCommon.generate(
                    input: prepared, parameters: GenerateParameters(maxTokens: maxTokens, temperature: 0), context: context
                ) { (_: [Int]) in Task.isCancelled ? .stop : .more }
                return result.output
            }
        }
        }
        #else
        _ = image
        throw localAIUnavailableOnMac
        #endif
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

    public init(store: ModelStore = .shared, language: OCRTargetLanguage = .japanese) {
        let instruction = language == .japanese
            ? " The document language is Japanese. For Japanese words, use Japanese orthography (for example 図表, not 图表). Preserve Latin letters, numbers, mathematical symbols, formulas, and any genuinely non-Japanese text exactly as printed."
            : ""
        base = PageVLMReader(spec: .ovisocr2, prompt: Self.prompt + instruction, context: ["enable_thinking": false],
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

    public init(store: ModelStore = .shared, language: OCRTargetLanguage = .japanese) {
        base = PageVLMReader(spec: .qwen3vl4b, prompt: language == .japanese ? Self.prompt : Self.automaticPrompt, context: nil,
                             longSide: 1400, minimumFreeMemory: 3_800 * 1_048_576, store: store)
    }

    public var isAvailable: Bool { base.isAvailable }

    static let prompt = """
    This is a page of a Japanese textbook about architecture and interior design (interior coordinator). \
    Transcribe ALL the Japanese text on the page exactly as printed, in natural reading order (vertical text: \
    right-to-left columns). Keep technical terms exactly (e.g. 天井, 照明器具, 建具, 野縁, 吊り木). \
    Output plain Markdown only: headings with #, tables as HTML. Do not translate, explain, summarize or correct.
    """

    static let automaticPrompt = """
    Transcribe all readable text on this page exactly as printed, in natural reading order.
    Preserve each language's writing system, all numbers, technical symbols and formulas.
    Output plain Markdown only: headings with #, tables as HTML. Do not translate, explain, summarize or correct.
    """

    public func read(_ input: OCRInput, maxTokens: Int = 4096) async throws -> String { try await base.read(input, maxTokens: maxTokens) }
    public func unload() async { await base.unload() }

    /// Glossaire de départ du domaine (manuel japonais de design d'intérieur) : termes traduits toujours pareil.
    /// Sert à préremplir le lexique modifiable de l'app (`DomainLexicon`), qui le remplace ensuite.
    public static let defaultGlossary: [(String, String)] = [
        ("天井", "plafond"), ("天井裏", "plénum (espace au-dessus du plafond)"), ("小屋裏", "comble"),
        ("小屋組", "charpente de toit"), ("野縁", "tasseau de plafond"), ("野縁受け", "lambourde porteuse de tasseaux"),
        ("吊り木", "suspente en bois"), ("吊りボルト", "tige filetée de suspension"), ("天井板", "panneau de plafond"),
        ("下地材", "matériau d'ossature"), ("軽鉄", "ossature métallique légère"), ("点検口", "trappe de visite"),
        ("照明器具", "luminaire"), ("空調機器", "équipement de climatisation"), ("配管", "tuyauterie"), ("配線", "câblage"),
        ("建具", "menuiserie (portes et fenêtres)"), ("障子", "shōji"), ("襖", "fusuma"), ("和室", "pièce de style japonais"),
        ("引き戸", "porte coulissante"), ("格子戸", "porte à claire-voie"), ("框戸", "porte à cadre et panneaux"),
        ("鏡板戸", "porte à panneau plein"), ("フラッシュ戸", "porte isoplane"), ("外部建具", "menuiserie extérieure"),
        ("舞良戸", "porte mairado (à lattes horizontales)"), ("ガラリ戸", "porte à persiennes"), ("ガラリ", "persiennes"),
        ("ルーバードア", "porte à persiennes (louvre)"), ("フランス戸", "porte-fenêtre"), ("板戸", "porte en planches"),
        ("雨戸", "volet (amado)"), ("鏡板", "panneau plein"), ("連子格子", "claire-voie à lattes (renji)"),
        ("木連格子", "claire-voie en treillis (kitsure)"), ("桟", "traverse"), ("組子", "baguettes du treillis (kumiko)"),
        ("框", "cadre (montants et traverses)"), ("腰板", "soubassement"), ("欄間", "imposte ajourée (ranma)"),
        ("鴨居", "linteau rainuré (kamoi)"), ("敷居", "seuil rainuré (shikii)"), ("床の間", "alcôve (tokonoma)"),
        ("畳", "tatami"), ("押入れ", "placard japonais (oshiire)"), ("縁側", "véranda (engawa)"),
    ]

    /// Traduit le Markdown d'une page en gardant sa structure (voir `PageVLMReader.translate`).
    public func translate(markdown: String, into language: TranslationLanguage = .french,
                          glossary: [(String, String)] = defaultGlossary, maxTokens: Int? = nil) async throws -> String {
        try await base.translate(markdown: markdown, into: language, glossary: glossary, maxTokens: maxTokens)
    }
}

extension PageVLMReader {
    /// Traduit le Markdown d'une page (texte seul, pas d'image) en français ou en anglais, **structure gardée** :
    /// mêmes titres, listes, tableaux et balises `<img>` ; glossaire imposé (il est en français : l'app n'en passe
    /// pas pour l'anglais). Même modèle que la lecture (déjà téléchargé).
    func translate(markdown: String, into language: TranslationLanguage,
                   glossary: [(String, String)], maxTokens: Int? = nil) async throws -> String {
        guard isAvailable else { throw OCRError.modelMissing(spec.title) }
        if let free = PageVLMReader.availableMemory(), free < minimumFreeMemory {
            throw OCRError.engineFailed(String(localized: "Pas assez de mémoire libre pour \(spec.title) (\(free / 1_048_576) Mo libres). Ferme les autres apps et réessaie.", bundle: .main))
        }
        let terms = glossary.filter { markdown.contains($0.0) }.map { "- \($0.0) → \($0.1)" }.joined(separator: "\n")
        let prompt = """
        Translate this page of a Japanese textbook on interior design (interior coordinator) into \(language.englishName).
        Rules:
        - Keep EXACTLY the same structure: same Markdown headings (#), lists, paragraph breaks, HTML <table> rows and cells, and copy every <img ...> tag unchanged.
        - Translate only the text, naturally and precisely, in a technical textbook register. Keep numbers, figure references (図表 → Figure) and units.
        - Output only the \(language.englishName) page, nothing else.
        \(terms.isEmpty ? "" : "Glossary (always use these translations):\n" + terms + "\n")
        Page:
        \(markdown)
        """
        #if canImport(MLXVLM)
        let user = UserInput(chat: [.user(prompt)], additionalContext: context)
        let budget = maxTokens ?? min(6000, max(512, markdown.count * 3 + 256))
        return try await GLMModel.using(directory: store.directory(spec), extraEOSTokens: []) { container in
        try await withError {
            try await container.perform { context in
                let prepared = try await context.processor.prepare(input: user)
                let result = try MLXLMCommon.generate(
                    input: prepared, parameters: GenerateParameters(maxTokens: budget, temperature: 0), context: context
                ) { (_: [Int]) in Task.isCancelled ? .stop : .more }
                return result.output
            }
        }
        }
        #else
        _ = prompt
        throw localAIUnavailableOnMac
        #endif
    }
}


/// Traducteur des pages. Mac à puce Apple : Qwen3.5-9B s'il est installé (texte seul, plus juste que le 4B ; demande
/// de NOxygen59 du 06/11/2026), sinon Qwen3-VL-4B, comme sur l'iPad.
public struct PageTranslator: Sendable {
    let base: PageVLMReader

    public init(store: ModelStore = .shared) {
        #if targetEnvironment(macCatalyst)
        if store.isInstalled(.qwen35chat9b) {
            base = PageVLMReader(spec: .qwen35chat9b, prompt: "", context: ["enable_thinking": false], longSide: 0,
                                 minimumFreeMemory: ModelSpec.chatMemoryNeeded(.qwen35chat9b), store: store)
            return
        }
        #endif
        base = Qwen3VLReader(store: store).base
    }

    public var isAvailable: Bool { base.isAvailable }
    public var spec: ModelSpec { base.spec }
    /// Nom court affiché (« Qwen3.5-9B », « Qwen3-VL »).
    public var name: String { base.spec.id == ModelSpec.qwen3vl4b.id ? "Qwen3-VL" : "Qwen3.5-9B" }
    /// Modèle à télécharger pour traduire sur cet appareil.
    public static var preferredName: String {
        #if targetEnvironment(macCatalyst)
        return "Qwen3.5-9B"
        #else
        return "Qwen3-VL"
        #endif
    }

    public func translate(markdown: String, into language: TranslationLanguage,
                          glossary: [(String, String)], maxTokens: Int? = nil) async throws -> String {
        try await base.translate(markdown: markdown, into: language, glossary: glossary, maxTokens: maxTokens)
    }

    public func unload() async { await base.unload() }
}

/// Langue des traductions de pages (Qwen3-VL, hors ligne). `rawValue` = nom du lecteur dans `DocumentAITextStore`
/// (`fr-<page>.md`, `en-<page>.md`) : les deux traductions d'une page coexistent.
public enum TranslationLanguage: String, CaseIterable, Sendable, Identifiable {
    case french = "fr", english = "en", chinese = "zh"
    public var id: String { rawValue }
    /// Nom donné au modèle dans la consigne (écrite en anglais).
    public var englishName: String {
        switch self {
        case .french: return "French"
        case .english: return "English"
        case .chinese: return "Simplified Chinese"
        }
    }
    /// Nom affiché dans l'app (dans sa propre langue).
    public var title: String {
        switch self {
        case .french: return "Français"
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
    /// Nom dans une phrase de l'interface (« Traduire en français »).
    public var localizedName: String {
        switch self {
        case .french: return String(localized: "français", bundle: .main)
        case .english: return String(localized: "anglais", bundle: .main)
        case .chinese: return String(localized: "chinois", bundle: .main)
        }
    }
    /// Langues proposées : le chinois sur la version Mac seulement (pas de chinois sur l'iPad, décision du 04/11/2026).
    public static var available: [TranslationLanguage] {
        #if targetEnvironment(macCatalyst)
        return allCases
        #else
        return [.french, .english]
        #endif
    }
}
