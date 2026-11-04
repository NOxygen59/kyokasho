// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Traduction DeepL (option). Clé API dans le Trousseau ; une requête ne part que quand tu
/// touches « Traduire ». Clés gratuites (finissant par « :fx ») → api-free.deepl.com.
@MainActor
final class DeepLService: ObservableObject {
    static let shared = DeepLService()

    @Published private(set) var hasKey: Bool
    /// Dernier quota connu (menu « … » du lecteur), à titre d'information.
    @Published private(set) var lastUsage: (used: Int, limit: Int)?
    private let keychain = KeychainItem(service: "fr.noxygen59.kyokasho.deepl", account: "api_key")
    /// Traductions déjà faites (texte source → traduction), pour ne jamais payer deux fois.
    private var cache: [String: String] = [:]

    enum DeepLError: LocalizedError {
        case noKey, http(Int), badResponse

        var errorDescription: String? {
            switch self {
            case .noKey: return String(localized: "Ajoute ta clé DeepL dans Réglages → Traduction.")
            case .http(403): return String(localized: "Clé DeepL refusée (vérifie-la dans Réglages → Traduction).")
            case .http(456): return String(localized: "Quota DeepL du mois atteint.")
            case .http(let code): return String(localized: "Erreur DeepL (\(code)).")
            case .badResponse: return String(localized: "Réponse inattendue de DeepL.")
            }
        }
    }

    private init() {
        hasKey = keychain.read() != nil
    }

    var maskedKey: String? {
        guard let key = keychain.read() else { return nil }
        return String(key.prefix(4)) + "…" + String(key.suffix(4))
    }

    func setKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { keychain.delete() } else { keychain.write(trimmed) }
        hasKey = keychain.read() != nil
        cache.removeAll()
    }

    /// Traduit du japonais (détecté automatiquement si absent) vers le français.
    func translate(_ text: String, target: String = "FR") async throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "" }
        if let hit = cache[target + "|" + source] { return hit }
        guard let key = keychain.read() else { throw DeepLError.noKey }
        let host = key.hasSuffix(":fx") ? "https://api-free.deepl.com" : "https://api.deepl.com"
        var request = URLRequest(url: URL(string: host + "/v2/translate")!)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { let text: [String]; let target_lang: String; let preserve_formatting: Bool }
        request.httpBody = try JSONEncoder().encode(Body(text: [source], target_lang: target, preserve_formatting: true))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeepLError.badResponse }
        guard http.statusCode == 200 else { throw DeepLError.http(http.statusCode) }
        struct Reply: Decodable { struct T: Decodable { let text: String }; let translations: [T] }
        guard let result = try JSONDecoder().decode(Reply.self, from: data).translations.first?.text else {
            throw DeepLError.badResponse
        }
        cache[target + "|" + source] = result
        Task { await refreshUsage() }
        return result
    }

    @MainActor
    func refreshUsage() async {
        guard hasKey else { lastUsage = nil; return }
        if let u = try? await usage() { lastUsage = u }
    }

    /// « 12 345 / 500 000 caractères ce mois-ci ».
    var usageText: String? {
        guard let u = lastUsage else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "fr_FR")
        func n(_ v: Int) -> String { f.string(from: NSNumber(value: v)) ?? "\(v)" }
        return String(localized: "\(n(u.used)) / \(n(u.limit)) caractères ce mois-ci")
    }

    /// Quota du mois (caractères utilisés / limite).
    func usage() async throws -> (used: Int, limit: Int) {
        guard let key = keychain.read() else { throw DeepLError.noKey }
        let host = key.hasSuffix(":fx") ? "https://api-free.deepl.com" : "https://api.deepl.com"
        var request = URLRequest(url: URL(string: host + "/v2/usage")!)
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeepLError.badResponse }
        guard http.statusCode == 200 else { throw DeepLError.http(http.statusCode) }
        struct U: Decodable { let character_count: Int; let character_limit: Int }
        let u = try JSONDecoder().decode(U.self, from: data)
        return (u.character_count, u.character_limit)
    }
}
