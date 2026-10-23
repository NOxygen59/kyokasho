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
        public init(role: Role, text: String) { self.role = role; self.text = text }
    }

    public static let instructions = """
        Tu es un assistant qui aide un francophone à étudier un manuel japonais de design d'intérieur \
        (coordinateur d'intérieur). Réponds en français, clairement et brièvement. Pour un mot japonais, donne la \
        lecture en hiragana et le sens. Si tu n'es pas sûr, dis-le.
        """

    /// Lexique du domaine (terme → sens) et lectures sûres (terme → kana), fournis par l'app (lexique modifiable).
    public var glossary: [(String, String)] = Qwen3VLReader.defaultGlossary
    public var readings: [String: String] = [:]

    private let reader: Qwen3VLReader
    private var session: ChatSession?
    private var holding = false

    public init(store: ModelStore = .shared) { reader = Qwen3VLReader(store: store) }

    public var isAvailable: Bool { reader.isAvailable }

    public func start(history: [Message], grounded: Bool = false) async throws {
        guard session == nil else { return }
        guard reader.isAvailable else { throw OCRError.modelMissing(ModelSpec.qwen3vl4b.title) }
        if let free = PageVLMReader.availableMemory(), free < reader.base.minimumFreeMemory {
            throw OCRError.engineFailed("Pas assez de mémoire libre pour Qwen3-VL (\(free / 1_048_576) Mo libres). Ferme les autres apps et réessaie.")
        }
        let container = try await GLMModel.shared.acquire(directory: reader.base.store.directory(reader.base.spec), extraEOSTokens: [])
        holding = true
        let past: [Chat.Message] = history.map { $0.role == .user ? .user($0.text) : .assistant($0.text) }
        session = ChatSession(container, instructions: Self.instructions, history: past,
                              generateParameters: GenerateParameters(maxTokens: 1024, temperature: grounded ? 0 : 0.3))
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
            return AsyncThrowingStream { $0.finish(throwing: OCRError.engineFailed("Conversation pas démarrée.")) }
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
        await GLMModel.shared.unload(directory: reader.base.store.directory(reader.base.spec))
    }
}
