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
/// s'arrête après 5 minutes sans lecture. Rien ne sort du Mac : seule une adresse locale est appelée, sans redirection.
public enum LocalServerVLM {
    public static var isInstalled: Bool { ModelStore.shared.isInstalled(.ovisocr2GGUF) }

    static let process = LocalEngineProcess(driver: .init(
        launch: { try LocalOvisEngine.launch() },
        isAlive: { LocalOvisEngine.isAlive($0) },
        terminate: { LocalOvisEngine.terminate($0) },
        isReady: { await LocalOvisEngine.isReady($0) },
        startTimeout: 300, idleDelay: 300))

    /// Pour le bouton Supprimer et le changement de modèle.
    public static func stop() async { await process.stop() }

    /// À la fermeture de l'app, où rien d'asynchrone n'a le temps de finir.
    public static func stopAtTermination() { LocalOvisEngine.killRecordedProcess() }

    /// Lecture d'une page : consigne d'OvisOCR2 et image JPEG, réponse Markdown.
    static func read(prompt: String, image: CGImage, maxTokens: Int) async throws -> String {
        guard let jpeg = jpegData(image) else { throw OCRError.renderFailed }
        let engine: LocalEngineProcess.Instance
        do {
            engine = try await process.beginRead()
        } catch LocalEngineProcess.Failure.exitedDuringStart {
            throw OCRError.engineFailed("Le moteur OvisOCR2 s'est arrêté au démarrage. Voir le fichier llama-server.log du dossier temporaire de l'app.")
        } catch LocalEngineProcess.Failure.startTimedOut {
            throw OCRError.engineFailed("Le moteur OvisOCR2 n'a pas démarré à temps.")
        }
        defer { Task { await process.endRead() } }
        let body: [String: Any] = [
            "temperature": 0,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": [
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + jpeg.base64EncodedString()]],
                ["type": "text", "text": prompt],
            ]]],
        ]
        // Une page peut durer longtemps sur un processeur Intel à 1,4 GHz.
        var request = LocalOvisEngine.request(engine, path: "v1/chat/completions", timeout: 3600)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await LocalOnlyHTTP.session.data(for: request)
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

/// Lancement réel de `llama-server`. `Process` n'existe pas sous Mac Catalyst, d'où `posix_spawn`. Le binaire est signé
/// pour hériter du bac à sable de l'app (`App/LlamaServer-Mac.entitlements`). Port libre et jeton tirés à chaque lancement :
/// la lecture ne peut viser qu'une instance que l'app a lancée elle-même.
enum LocalOvisEngine {
    private static var logFile: URL { FileManager.default.temporaryDirectory.appendingPathComponent("llama-server.log") }
    private static var pidFile: URL { FileManager.default.temporaryDirectory.appendingPathComponent("llama-server.pid") }

    /// Fils de calcul : les cœurs physiques, soit la moitié des cœurs logiques sur un Intel à hyperthreading.
    static func arguments(model: String, vision: String, port: Int, token: String, logicalCores: Int) -> [String] {
        ["llama-server", "-m", model, "--mmproj", vision, "--host", "127.0.0.1", "--port", String(port), "--api-key", token,
         "-t", String(max(1, logicalCores / 2)), "-c", "8192", "-ngl", "0"]
    }

    static func request(_ engine: LocalEngineProcess.Instance, path: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(engine.port)/\(path)")!, timeoutInterval: timeout)
        request.setValue("Bearer \(engine.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func isReady(_ engine: LocalEngineProcess.Instance) async -> Bool {
        guard let (_, response) = try? await LocalOnlyHTTP.session.data(for: request(engine, path: "v1/models", timeout: 2)) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    static func isAlive(_ pid: Int32) -> Bool { waitpid(pid, nil, WNOHANG) == 0 }

    static func terminate(_ pid: Int32) {
        kill(pid, SIGTERM)
        try? FileManager.default.removeItem(at: pidFile)
        // Essai du 04/11/2026 : un moteur en plein travail peut ignorer SIGTERM et garder 2 Go ; il est alors forcé.
        DispatchQueue.global(qos: .utility).async {
            for _ in 0..<50 {
                if waitpid(pid, nil, WNOHANG) != 0 { return }
                usleep(100_000)
            }
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
        }
    }

    /// Fermeture normale de l'app, ou reste d'un plantage : le moteur ne garde pas 2 Go en mémoire sans parent.
    static func killRecordedProcess() {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(text),
              commandName(pid) == "llama-server" else { return }
        // Pas de `waitpid` possible sur le reste d'un ancien lancement : arrêt forcé, le travail en cours est déjà perdu.
        kill(pid, SIGKILL)
        try? FileManager.default.removeItem(at: pidFile)
    }

    /// Nom du processus, pour ne jamais tuer un autre programme qui aurait repris ce numéro.
    private static func commandName(_ pid: Int32) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return withUnsafePointer(to: &info.kp_proc.p_comm) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
        }
    }

    private static func freePort() throws -> Int {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw OCRError.engineFailed("Aucun port local disponible pour le moteur OvisOCR2.") }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, size) }
        }
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &size) }
        }
        guard bound == 0, named == 0 else { throw OCRError.engineFailed("Aucun port local disponible pour le moteur OvisOCR2.") }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    static func launch() throws -> LocalEngineProcess.Instance {
        killRecordedProcess()
        guard let binary = Bundle.main.url(forAuxiliaryExecutable: "llama-server") else {
            throw OCRError.engineFailed("Moteur OvisOCR2 absent de l'app.")
        }
        let port = try freePort()
        let token = UUID().uuidString
        let store = ModelStore.shared, spec = ModelSpec.ovisocr2GGUF
        let arguments = arguments(model: store.url(spec, "model.gguf").path, vision: store.url(spec, "mmproj.gguf").path,
                                  port: port, token: token, logicalCores: ProcessInfo.processInfo.activeProcessorCount)
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
        try? String(child).write(to: pidFile, atomically: true, encoding: .utf8)
        return .init(pid: child, port: port, token: token)
    }
}
