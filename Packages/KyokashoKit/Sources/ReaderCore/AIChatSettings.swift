// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Réglages du chat d'un modèle d'IA locale (RET-022 / RET-030, #37 et #45), à la manière de Locally sur Mac :
/// consigne générale (prompt système) et paramètres de génération, propres à chaque modèle.
///
/// Les valeurs sont bornées au décodage et à l'écriture : une valeur hors limite (préférence abîmée, ancienne
/// version) ne peut ni bloquer la génération ni remplir la mémoire.
public struct AIChatSettings: Codable, Equatable, Sendable {
    public static let temperatureRange = 0.0...1.5
    public static let topPRange = 0.05...1.0
    public static let topKRange = 0...200
    public static let maxTokensRange = 128...4096
    public static let repetitionRange = 1.0...1.5

    /// Consigne générale ; `nil` : celle de l'app (`QwenChat.instructions`).
    public var instructions: String? { didSet { instructions = Self.clean(instructions) } }
    /// `nil` : automatique (0 sur un livre, pour coller aux extraits ; 0,3 en discussion libre).
    public var temperature: Double? { didSet { temperature = temperature.map { Self.clamp($0, Self.temperatureRange) } } }
    public var topP: Double = 1 { didSet { topP = Self.clamp(topP, Self.topPRange) } }
    /// 0 : pas de limite.
    public var topK: Int = 0 { didSet { topK = Self.clamp(topK, Self.topKRange) } }
    public var maxTokens: Int = 1024 { didSet { maxTokens = Self.clamp(maxTokens, Self.maxTokensRange) } }
    /// `nil` : aucune pénalité.
    public var repetitionPenalty: Double? { didSet { repetitionPenalty = repetitionPenalty.map { Self.clamp($0, Self.repetitionRange) } } }
    /// Qwen3.5 seulement : laisser le modèle réfléchir avant de répondre (plus long ; la réflexion s'affiche).
    public var thinking = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instructions = Self.clean(try c.decodeIfPresent(String.self, forKey: .instructions))
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature).map { Self.clamp($0, Self.temperatureRange) }
        topP = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .topP) ?? 1, Self.topPRange)
        topK = Self.clamp(try c.decodeIfPresent(Int.self, forKey: .topK) ?? 0, Self.topKRange)
        maxTokens = Self.clamp(try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 1024, Self.maxTokensRange)
        repetitionPenalty = try c.decodeIfPresent(Double.self, forKey: .repetitionPenalty).map { Self.clamp($0, Self.repetitionRange) }
        thinking = try c.decodeIfPresent(Bool.self, forKey: .thinking) ?? false
    }

    private enum CodingKeys: String, CodingKey { case instructions, temperature, topP, topK, maxTokens, repetitionPenalty, thinking }

    /// Température réellement utilisée.
    public func effectiveTemperature(grounded: Bool) -> Double { temperature ?? (grounded ? 0 : 0.3) }

    /// Consigne réellement utilisée.
    public func effectiveInstructions(default fallback: String) -> String { instructions ?? fallback }

    /// Consigne vide ou faite d'espaces : retour à celle de l'app ; au plus 4 000 caractères (contexte du modèle).
    static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(4000))
    }

    static func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T { min(max(value, range.lowerBound), range.upperBound) }
}

/// Préréglages proposés (#45) : une consigne et des paramètres de départ, modifiables ensuite.
public enum AIChatPreset: String, CaseIterable, Identifiable, Sendable {
    case standard, summary, formulas, teacher, translation
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Consigne de l'app"
        case .summary: return "Résumer"
        case .formulas: return "Expliquer les formules"
        case .teacher: return "Professeur de japonais"
        case .translation: return "Traduction mot à mot"
        }
    }

    public var summary: String {
        switch self {
        case .standard: return "Réponses brèves, appuyées sur les pages, sans invention."
        case .summary: return "Résumé structuré d'une page ou d'un passage, points clés en liste."
        case .formulas: return "Chaque formule expliquée pas à pas : symboles, unités, exemple chiffré."
        case .teacher: return "Lectures, sens, grammaire et exemples, adaptés à un francophone."
        case .translation: return "Phrase découpée, chaque mot traduit, puis une traduction naturelle."
        }
    }

    /// `nil` : la consigne de l'app.
    public var instructions: String? {
        switch self {
        case .standard: return nil
        case .summary: return """
            Tu résumes en français le texte japonais que l'utilisateur consulte (pages d'un manuel scanné). \
            Commence par une phrase qui dit de quoi parle le passage, puis 3 à 7 points clés en liste. \
            Garde les termes techniques japonais importants avec leur lecture en hiragana entre parenthèses. \
            Cite les pages sous la forme [p. N]. N'ajoute rien qui ne soit pas dans le texte.
            """
        case .formulas: return """
            Tu expliques en français les formules mathématiques ou techniques du texte consulté. Pour chaque formule : \
            ce qu'elle calcule, le sens de chaque symbole avec son unité, les conditions d'emploi, puis un petit \
            exemple chiffré pas à pas. Écris les formules en texte simple (ex. A = L × l). Si une formule semble mal \
            lue par l'OCR, signale-le au lieu de deviner. Cite les pages [p. N].
            """
        case .teacher: return """
            Tu es un professeur de japonais patient pour un francophone. Pour chaque mot ou phrase demandé : lecture \
            en hiragana, sens en français, nature du mot, point de grammaire utile et un exemple simple traduit. \
            Si tu n'es pas sûr d'une lecture, dis-le. Réponds en français.
            """
        case .translation: return """
            Tu traduis du japonais vers le français pour un apprenant. Découpe la phrase en mots ou groupes de mots ; \
            pour chacun, donne la lecture en hiragana et le sens. Termine par une traduction française naturelle. \
            N'invente aucun mot absent du texte.
            """
        }
    }

    /// Paramètres de départ du préréglage, appliqués sur les réglages actuels (la longueur et la consigne changent,
    /// le reste est gardé sauf la température quand le préréglage en demande une).
    public func applied(to settings: AIChatSettings) -> AIChatSettings {
        var s = settings
        s.instructions = instructions
        switch self {
        case .standard: s.temperature = nil; s.maxTokens = 1024
        case .summary: s.temperature = 0.2; s.maxTokens = 1024
        case .formulas: s.temperature = 0.1; s.maxTokens = 2048
        case .teacher: s.temperature = 0.4; s.maxTokens = 1536
        case .translation: s.temperature = 0.1; s.maxTokens = 1536
        }
        return s
    }
}
