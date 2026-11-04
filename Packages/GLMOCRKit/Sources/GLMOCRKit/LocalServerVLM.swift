// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation
import ImageIO
import OCRKit
import UniformTypeIdentifiers

/// Version Mac (#55, demande de NOxygen59 du 30/10/2026 : « l'app devient inutile sans Ovis ») : MLX n'existe pas sur
/// Mac Intel, mais le **même** modèle OvisOCR2 existe en GGUF pour llama.cpp. L'app embarque `llama-server` : il se lance
/// à la première lecture, reste un processus à part (sa mémoire est rendue d'un coup, 8 Go sur la machine visée) et
/// s'arrête après 5 minutes sans lecture. Rien ne sort du Mac : seule l'adresse locale est appelée.
public enum LocalServerVLM {
    public static var isInstalled: Bool { ModelStore.shared.isInstalled(.ovisocr2GGUF) }

    /// Lecture d'une page : consigne d'OvisOCR2 et image JPEG, réponse Markdown.
    static func read(prompt: String, image: CGImage, maxTokens: Int) async throws -> String {
        guard let jpeg = jpegData(image) else { throw OCRError.renderFailed }
        try await LocalOvisServer.shared.beginRead()
        defer { Task { await LocalOvisServer.shared.endRead() } }
        let body: [String: Any] = [
            "temperature": 0,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": [
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + jpeg.base64EncodedString()]],
                ["type": "text", "text": prompt],
            ]]],
        ]
        // Une page peut durer longtemps sur un processeur Intel à 1,4 GHz.
        var request = URLRequest(url: LocalOvisServer.base.appendingPathComponent("v1/chat/completions"), timeoutInterval: 3600)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw OCRError.engineFailed("Réponse inattendue du moteur OvisOCR2 : \(String(decoding: data.prefix(300), as: UTF8.self))")
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

/// Cycle de vie du processus `llama-server`. `Process` n'existe pas sous Mac Catalyst, d'où `posix_spawn`. Le binaire est
/// signé pour hériter du bac à sable de l'app (`App/LlamaServer-Mac.entitlements`).
actor LocalOvisServer {
    static let shared = LocalOvisServer()
    /// Port propre à l'app, pour ne pas croiser un autre serveur llama.cpp du Mac.
    static let base = URL(string: "http://127.0.0.1:18765")!
    private static let idleStop: UInt64 = 300_000_000_000
    private static let startTimeout: TimeInterval = 300

    private var pid: pid_t?
    private var reads = 0
    private var idleTask: Task<Void, Never>?

    func beginRead() async throws {
        idleTask?.cancel()
        reads += 1
        do { try await ensureRunning() } catch { reads -= 1; throw error }
    }

    func endRead() {
        reads -= 1
        guard reads == 0 else { return }
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.idleStop)
            guard !Task.isCancelled else { return }
            await self?.stopIfIdle()
        }
    }

    private func stopIfIdle() { if reads == 0 { stop() } }

    func stop() {
        guard let pid else { return }
        kill(pid, SIGTERM)
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        self.pid = nil
    }

    private func ensureRunning() async throws {
        if let pid, waitpid(pid, nil, WNOHANG) == pid { self.pid = nil }
        if await Self.isHealthy() { return }
        if pid == nil { pid = try Self.spawn() }
        let deadline = Date().addingTimeInterval(Self.startTimeout)
        while Date() < deadline {
            if let pid, waitpid(pid, nil, WNOHANG) == pid {
                self.pid = nil
                throw OCRError.engineFailed("Le moteur OvisOCR2 s'est arrêté au démarrage. Journal : \(Self.logFile.lastPathComponent)")
            }
            if await Self.isHealthy() { return }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        stop()
        throw OCRError.engineFailed("Le moteur OvisOCR2 n'a pas démarré à temps.")
    }

    private static func isHealthy() async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("health"), timeoutInterval: 2)
        request.httpMethod = "GET"
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private static var logFile: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("llama-server.log")
    }

    /// Fils de calcul : les cœurs physiques, soit la moitié des cœurs logiques sur un Intel à hyperthreading.
    static func arguments(model: String, vision: String, logicalCores: Int) -> [String] {
        ["llama-server", "-m", model, "--mmproj", vision, "--host", "127.0.0.1", "--port", "18765",
         "-t", String(max(1, logicalCores / 2)), "-c", "8192", "-ngl", "0"]
    }

    private static func spawn() throws -> pid_t {
        guard let binary = Bundle.main.url(forAuxiliaryExecutable: "llama-server") else {
            throw OCRError.engineFailed("Moteur OvisOCR2 absent de l'app.")
        }
        let store = ModelStore.shared, spec = ModelSpec.ovisocr2GGUF
        let arguments = arguments(model: store.url(spec, "model.gguf").path, vision: store.url(spec, "mmproj.gguf").path,
                                  logicalCores: ProcessInfo.processInfo.activeProcessorCount)
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 1, logFile.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var child: pid_t = 0
        let result = posix_spawn(&child, binary.path, &actions, nil, &argv, environ)
        guard result == 0 else {
            throw OCRError.engineFailed("Lancement du moteur OvisOCR2 impossible : \(String(cString: strerror(result)))")
        }
        return child
    }
}
