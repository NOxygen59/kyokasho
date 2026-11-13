// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import MLX
import MLXLMCommon
import OCRKit
import ReaderCore

/// Conversation avec Qwen3-VL-4B (le seul de nos modèles fait pour discuter ; OvisOCR2 et GLM-OCR ne font que lire).
/// `start` charge le modèle et le **garde** tant que la conversation est ouverte (compté comme utilisé : jamais
/// libéré pour inactivité) ; `stop` le rend et le décharge. Historique repris au démarrage.
public final class QwenChat: @unchecked Sendable {
    public struct Message: Codable, Sendable, Equatable {
        public enum Role: String, Codable, Sendable { case user, assistant }
        public var role: Role
        public var text: String
        /// Pages source consultées pour cette réponse (base 0) et version de mise en page du document à ce moment
        /// (#49, R4) : après une suppression ou une restauration, les liens suivent leur page ou se désactivent.
        /// Absents des messages enregistrés avant : ceux-là gardent leurs liens seulement si les pages n'ont pas changé.
        public var pages: [Int]? = nil
        public var layoutVersion: Int? = nil
        public init(role: Role, text: String) { self.role = role; self.text = text }
    }

    public static let instructions = """
        Tu aides l'utilisateur à comprendre le document qu'il consulte. Réponds à sa question actuelle en français, \
        clairement et brièvement. Ne suppose pas le sujet du document ni celui de la question. Quand des extraits \
        sont fournis, appuie chaque affirmation sur eux et cite les pages. Pour un mot japonais, donne sa lecture \
        en hiragana et son sens seulement si tu peux les établir. Si les extraits ne répondent pas à la question, \
        dis-le, puis réponds avec tes connaissances générales en le signalant clairement (T2, 10/11/2026) ; n'invente \
        jamais de page ni de référence. Si la demande porte uniquement sur des mots-clés de recherche, renvoie uniquement ces mots-clés.
        """

    /// Lexique du domaine (terme → sens) et lectures sûres (terme → kana), fournis par l'app (lexique modifiable).
    public var glossary: [(String, String)] = Qwen3VLReader.defaultGlossary
    public var readings: [String: String] = [:]

    private let store: ModelStore
    private let model: ModelSpec
    private var session: ChatSession?
    private var holding = false

    public init(store: ModelStore = .shared, model: ModelSpec = .qwen3vl4b) {
        self.store = store
        self.model = model
    }

    public var isAvailable: Bool { store.isInstalled(model) }

    /// `settings` : consigne et paramètres choisis pour ce modèle (#37, #45) ; par défaut, ceux d'avant.
    public func start(history: [Message], grounded: Bool = false, settings: AIChatSettings = AIChatSettings()) async throws {
        guard session == nil else { return }
        guard model.id == ModelSpec.qwen3vl4b.id || ModelSpec.isQwen35Family(model.id) else {
            throw OCRError.engineFailed(String(localized: "Ce modèle ne sait pas discuter.", bundle: .main))
        }
        guard isAvailable else { throw OCRError.modelMissing(model.title) }
        // Revue R2 MODLOC E3 (n°9) : un autre modèle resté chargé sans travail est d'abord rendu, puis on remesure.
        if let free = PageVLMReader.availableMemory(), free < 3_800 * 1_048_576 { await GLMModel.shared.unloadIfIdle() }
        if let free = PageVLMReader.availableMemory(), free < 3_800 * 1_048_576 {
            throw OCRError.engineFailed(String(localized: "Pas assez de mémoire libre pour \(model.title) (\(free / 1_048_576) Mo libres). Ferme les autres apps et réessaie.", bundle: .main))
        }
        let container = try await GLMModel.shared.acquire(directory: store.directory(model), extraEOSTokens: [])
        holding = true
        let past: [Chat.Message] = history.map { $0.role == .user ? .user($0.text) : .assistant($0.text) }
        let parameters = GenerateParameters(maxTokens: settings.maxTokens,
                                            temperature: Float(settings.effectiveTemperature(grounded: grounded)),
                                            topP: Float(settings.topP), topK: settings.topK,
                                            repetitionPenalty: settings.repetitionPenalty.map { Float($0) })
        session = ChatSession(container, instructions: settings.effectiveInstructions(default: Self.instructions), history: past,
                              generateParameters: parameters,
                              additionalContext: ModelSpec.isQwen35Family(model.id) ? ["enable_thinking": settings.thinking] : nil)
    }

    /// Aide fiable ajoutée à la question (le modèle de 4 milliards invente souvent les lectures, ex. 天井 « あまね ») :
    /// lectures de l'analyseur japonais de l'app (MeCab si installé) et termes du glossaire du manuel présents.
    public static func hints(for prompt: String, glossary: [(String, String)] = Qwen3VLReader.defaultGlossary,
                             knownReadings: [String: String] = [:]) -> String? {
        var readings: [String] = []
        // Lectures du lexique d'abord (plus sûres que l'analyseur pour les termes du métier).
        for (term, kana) in knownReadings where prompt.contains(term) { readings.append("\(term) = \(kana)") }
        for ruby in Furigana.rubies(for: prompt) {
            let chars = Array(prompt)
            guard ruby.range.upperBound <= chars.count else { continue }
            let word = String(chars[ruby.range])
            let line = "\(word) = \(ruby.reading)"
            if !readings.contains(line), !readings.contains(where: { $0.hasPrefix(word + " = ") }) { readings.append(line) }
        }
        let terms = glossary.filter { prompt.contains($0.0) }.map { "\($0.0) = \($0.1)" }
        guard !readings.isEmpty || !terms.isEmpty else { return nil }
        var text = "(Informations fiables à utiliser telles quelles"
        if !readings.isEmpty { text += " — lectures : " + readings.joined(separator: ", ") }
        if !terms.isEmpty { text += " — sens dans ce manuel : " + terms.joined(separator: ", ") }
        return text + ")"
    }

    /// Réponse en morceaux, au fil de l'écriture. Une erreur MLX devient une erreur Swift (pas d'arrêt de l'app).
    public func stream(_ prompt: String, context: String? = nil) -> AsyncThrowingStream<String, Error> {
        var prompt = Self.hints(for: prompt, glossary: glossary, knownReadings: readings).map { prompt + "\n\n" + $0 } ?? prompt
        if let context { prompt += "\n\n" + context }
        guard let session else {
            return AsyncThrowingStream { $0.finish(throwing: OCRError.engineFailed(String(localized: "Conversation pas démarrée.", bundle: .main))) }
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await withError {
                        for try await chunk in session.streamResponse(to: prompt) {
                            try Task.checkCancellation()
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Nouvelle conversation (le modèle reste chargé).
    public func reset() async { await session?.clear() }

    /// Écran quitté : modèle rendu et déchargé (la mémoire revient à l'iPad).
    public func stop() async {
        session = nil
        guard holding else { return }
        holding = false
        await GLMModel.shared.release()
        await GLMModel.shared.unload(directory: store.directory(model))
    }
}
