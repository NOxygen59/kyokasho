// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation
import ImageIO
import OCRKit
import UniformTypeIdentifiers

/// Version Mac (#55, demande de NOxygen59 du 30/10/2026 : « l'app devient inutile sans Ovis ») : MLX n'existe pas sur
/// Mac Intel, mais le **même** modèle OvisOCR2 (ATH-MaaS/OvisOCR2) existe converti en GGUF pour llama.cpp, qui tourne
/// sur un processeur Intel. L'app envoie la page au serveur `llama-server` lancé sur ce Mac (API compatible OpenAI,
/// `http://127.0.0.1:8080` par défaut). Rien ne sort du Mac : seule l'adresse locale est appelée.
public enum LocalServerVLM {
    public static let enabledKey = "mac.localVLM.enabled"
    public static let urlKey = "mac.localVLM.url"
    public static let defaultURL = "http://127.0.0.1:8080"

    public static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var base: URL? {
        URL(string: UserDefaults.standard.string(forKey: urlKey) ?? defaultURL)
    }

    /// Lecture d'une page : consigne d'OvisOCR2 et image JPEG, réponse Markdown.
    static func read(prompt: String, image: CGImage, maxTokens: Int) async throws -> String {
        guard enabled, let base, let host = base.host, ["127.0.0.1", "localhost", "::1"].contains(host) else {
            throw OCRError.engineFailed("OvisOCR2 sur Mac : active « OvisOCR2 par serveur local » dans Réglages > Modèles (adresse locale seulement).")
        }
        guard let jpeg = jpegData(image) else { throw OCRError.renderFailed }
        let body: [String: Any] = [
            "temperature": 0,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": [
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + jpeg.base64EncodedString()]],
                ["type": "text", "text": prompt],
            ]]],
        ]
        var request = URLRequest(url: base.appendingPathComponent("v1/chat/completions"), timeoutInterval: 900)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch {
            throw OCRError.engineFailed("Serveur OvisOCR2 injoignable (\(base.absoluteString)) : lance llama-server sur ce Mac. \(error.localizedDescription)")
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw OCRError.engineFailed("Réponse inattendue du serveur OvisOCR2 : \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        return text
    }

    static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
