// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CryptoKit
import Foundation

/// Un modèle OCR téléchargeable (jamais dans l'app ni dans le dépôt : l'utilisateur le télécharge).
public struct ModelSpec: Identifiable, Sendable, Equatable {
    public struct File: Sendable, Equatable {
        public let name: String
        public let url: URL
        public let size: Int64
        /// SHA-256 publié par la source (vérifié après téléchargement), si connu.
        public let sha256: String?
    }

    public let id: String
    public let title: String
    public let summary: String
    public let license: String
    public let files: [File]

    public var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    /// Page du projet d'origine (affichée sous le modèle).
    public var homepage: URL? {
        switch id {
        case "ppocr5": return URL(string: "https://github.com/PaddlePaddle/PaddleOCR")
        case "ndlocr": return URL(string: "https://github.com/ndl-lab/ndlocr-lite")
        case "glmocr": return URL(string: "https://huggingface.co/zai-org/GLM-OCR")
        case "degan": return URL(string: "https://github.com/dali92002/DE-GAN")
        case "ppdoclayout": return URL(string: "https://github.com/PaddlePaddle/PaddleOCR")
        case "doclayoutyolo": return URL(string: "https://github.com/opendatalab/DocLayout-YOLO")
        default: return nil
        }
    }

    /// Fichier principal téléchargé (le plus gros), pour afficher son adresse.
    public var mainDownload: URL? { files.max { $0.size < $1.size }?.url }
}

public extension ModelSpec {
    /// PP-OCRv5 mobile (PaddleOCR, Apache-2.0), version ONNX de RapidOCR. Chinois, japonais, anglais.
    static let ppocr5 = ModelSpec(
        id: "ppocr5", title: "PP-OCRv5 (PaddleOCR)",
        summary: "Petit et rapide. Japonais, chinois, anglais, horizontal et vertical.",
        license: "Apache-2.0 (PaddlePaddle, RapidAI)",
        files: [
            File(name: "det.onnx",
                 url: URL(string: "https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0/onnx/PP-OCRv5/det/ch_PP-OCRv5_det_mobile.onnx")!,
                 size: 4_819_576, sha256: "4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae"),
            File(name: "rec.onnx",
                 url: URL(string: "https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0/onnx/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile.onnx")!,
                 size: 16_631_306, sha256: "5825fc7ebf84ae7a412be049820b4d86d77620f204a041697b0494669b1742c5"),
            File(name: "dict.txt",
                 url: URL(string: "https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/a38c087bcb2579f9ccc2068aea02ec893b1c2311/ppocr/utils/dict/ppocrv5_dict.txt")!,
                 size: 74_012, sha256: "d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b"),
        ])

    /// NDLOCR-Lite (Bibliothèque nationale de la Diète, CC-BY-4.0) : livres japonais, vertical.
    static let ndlocr = ModelSpec(
        id: "ndlocr", title: "NDLOCR-Lite (Bibliothèque nationale du Japon)",
        summary: "Fait pour les livres japonais : mise en page, colonnes verticales, furigana.",
        license: "CC-BY-4.0 (National Diet Library, Japon)",
        files: [
            File(name: "deim.onnx", url: ndl("src/model/deim-s-1024x1024.onnx"),
                 size: 40_256_763, sha256: "c156ce0c4e704bc3bf7e4016d0a87b949cffa8b3724f4b4cc696b8284c3c7373"),
            File(name: "parseq30.onnx", url: ndl("src/model/parseq-ndl-24x256-30-tiny-189epoch-tegaki3-r8data-202604.onnx"),
                 size: 36_457_393, sha256: "9e651bae4c1a4d5254da1127e86e82e21ef62d5339b37e62d4a3d3d30831772d"),
            File(name: "parseq50.onnx", url: ndl("src/model/parseq-ndl-24x384-50-tiny-300epoch-tegaki3-r8data-202604.onnx"),
                 size: 37_808_553, sha256: "49cea9db4552f19eb05c8ee202fcf74714977749b2f4c9376b127fde41b07a99"),
            File(name: "parseq100.onnx", url: ndl("src/model/parseq-ndl-24x768-100-tiny-153epoch-tegaki3-r8data-202604.onnx"),
                 size: 42_588_187, sha256: "06462b0dbd5b0b8508545c8c3d485cf20dbf4ffa652fe145e69c9e7457080602"),
            File(name: "NDLmoji.yaml", url: ndl("src/config/NDLmoji.yaml"),
                 size: 42_434, sha256: "f6ad5a2de444b495155866af811cf1a98309dcae3225db802767ea531a2dc529"),
        ])

    /// GLM-OCR (Zhipu AI, MIT), version MLX 4 bits : modèle IA qui relit les lignes (lent, précis).
    static let glmocr = ModelSpec(
        id: "glmocr", title: "GLM-OCR (IA, précis et lent)",
        summary: "Petit modèle IA (0,9 milliard de paramètres) qui relit chaque ligne. Plusieurs secondes par page.",
        license: "MIT (Zhipu AI) — conversion MLX : mlx-community",
        files: ["config.json", "generation_config.json", "model.safetensors.index.json", "preprocessor_config.json",
                "processor_config.json", "tokenizer.json", "tokenizer_config.json", "chat_template.jinja"]
            .map { File(name: $0, url: glm($0), size: 0, sha256: nil) }
            + [File(name: "model.safetensors", url: glm("model.safetensors"),
                    size: 1_247_191_941, sha256: "089e0339fcbc0fbf2225c3bd1cd94c6b4d49fdb3b1adfbb35ea22eb60b2afc95")])

    static let all: [ModelSpec] = [.ndlocr, .ppocr5, .glmocr]

    /// PP-DocLayout v3 (PaddleOCR / PP-Structure, Apache-2.0), version ONNX de RapidLayout :
    /// zones de la page (titre, texte, tableau, légende…) **et ordre de lecture**.
    static let ppdoclayout = ModelSpec(
        id: "ppdoclayout", title: "PP-DocLayout v3 (mise en page)",
        summary: "Repère titres, paragraphes, colonnes, tableaux et légendes, avec l'ordre de lecture. Pour le texte mis en forme.",
        license: "Apache-2.0 (PaddlePaddle) — conversion ONNX : RapidAI/RapidLayout",
        files: [File(name: "layout.onnx", url: URL(string: "https://www.modelscope.cn/models/RapidAI/RapidLayout/resolve/v1.2.0/onnx/pp_doc_layout/pp_doc_layoutv3.onnx")!,
                     size: 130_502_330, sha256: "250dbad1dfb9e4983fab75e1bf5085cd56ec3f41d5c7d0f8623ec74856e7aa67")])

    /// DocLayout-YOLO DocStructBench (OpenDataLab, modèle de mise en page de MinerU), version ONNX de RapidLayout.
    static let doclayoutyolo = ModelSpec(
        id: "doclayoutyolo", title: "DocLayout-YOLO (mise en page de MinerU)",
        summary: "Repère titres, texte, tableaux, figures et légendes ; écarte en-têtes et pieds de page. Pour le texte mis en forme.",
        license: "AGPL-3.0 (OpenDataLab) — conversion ONNX : RapidAI/RapidLayout",
        files: [File(name: "layout.onnx", url: URL(string: "https://www.modelscope.cn/models/RapidAI/RapidLayout/resolve/v1.2.0/onnx/doclayout/doclayout_yolo_docstructbench_imgsz1024.onnx")!,
                     size: 75_324_621, sha256: "3b452baef10ecabd615491bc82cc4d49475fbc2cd7a8e535044f2c6bb28fb9fe")])

    static let layoutModels: [ModelSpec] = [.ppdoclayout, .doclayoutyolo]

    /// DE-GAN (Souibgui & Kessentini, GPL-3.0) : poids « binarisation » du dépôt d'origine convertis en ONNX
    /// (tuiles 256×256) par `tools/degan_to_onnx.py`, publiés (avec la licence) sur le dépôt public
    /// NOxygen59/kyokasho-models (release `degan-v1`).
    static let degan = ModelSpec(
        id: "degan", title: "DE-GAN (netteté des scans)",
        summary: "Nettoie le fond (taches, jaunissement) et rend les caractères noirs et nets sur les pages scannées.",
        license: "GPL-3.0 (M. A. Souibgui, Y. Kessentini) — conversion ONNX : tools/degan_to_onnx.py",
        files: [File(name: "degan-binarize.onnx",
                     url: URL(string: "https://github.com/NOxygen59/kyokasho-models/releases/download/degan-v1/degan-binarize.onnx")!,
                     size: 124_131_855, sha256: "b75e185e92c98e77b314f979ef339121a63fec9ac3a500f8b3b7e717ffe996c8")])

    private static func ndl(_ path: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/ndl-lab/ndlocr-lite/d001dad2013ceabb5736ff8d637474e443eb73c2/" + path)!
    }

    private static func glm(_ name: String) -> URL {
        URL(string: "https://huggingface.co/mlx-community/GLM-OCR-4bit/resolve/97f587506984cc92fa69b2694b4128e53db6b081/" + name)!
    }
}

/// Modèles installés dans `Application Support/Kyokasho/Models/<id>`.
/// Téléchargement à la demande, reprise si coupé, empreinte SHA-256 vérifiée.
public final class ModelStore: @unchecked Sendable {
    public static let shared = ModelStore(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Kyokasho/Models", isDirectory: true))

    public let root: URL
    private let lock = NSLock()
    private var resumeData: [URL: Data] = [:]

    public enum StoreError: LocalizedError {
        case badChecksum(String), httpStatus(Int)
        public var errorDescription: String? {
            switch self {
            case .badChecksum(let name): return "Fichier abîmé (\(name)) : empreinte différente. Relance le téléchargement."
            case .httpStatus(let code): return "Le serveur a répondu \(code)."
            }
        }
    }

    public init(root: URL) {
        self.root = root
    }

    public func directory(_ spec: ModelSpec) -> URL { root.appendingPathComponent(spec.id, isDirectory: true) }

    public func url(_ spec: ModelSpec, _ file: String) -> URL { directory(spec).appendingPathComponent(file) }

    /// Tous les fichiers sont là (un fichier n'est rangé qu'une fois vérifié).
    public func isInstalled(_ spec: ModelSpec) -> Bool {
        spec.files.allSatisfy { FileManager.default.fileExists(atPath: url(spec, $0.name).path) }
    }

    /// Place occupée sur le disque.
    public func installedSize(_ spec: ModelSpec) -> Int64 {
        spec.files.reduce(0) { total, file in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url(spec, file.name).path)
            return total + ((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    public func delete(_ spec: ModelSpec) throws {
        let dir = directory(spec)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }

    /// Télécharge les fichiers manquants. `progress(octets reçus, total)` ; annulable (la reprise est gardée).
    public func download(_ spec: ModelSpec, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory(spec), withIntermediateDirectories: true)
        let total = spec.totalSize
        var done: Int64 = 0
        for file in spec.files {
            let destination = url(spec, file.name)
            if FileManager.default.fileExists(atPath: destination.path) {
                done += file.size
                progress(done, total)
                continue
            }
            let base = done
            let temp = try await fetch(file.url) { received in progress(base + received, total) }
            if let expected = file.sha256 {
                guard try Self.sha256(of: temp) == expected else {
                    try? FileManager.default.removeItem(at: temp)
                    throw StoreError.badChecksum(file.name)
                }
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
            done += file.size
            progress(done, total)
        }
    }

    /// Téléchargement d'un fichier vers un fichier temporaire à nous (reprise si une partie existe).
    private func fetch(_ remote: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let previous = lock.withLock { resumeData.removeValue(forKey: remote) }
        let task = previous.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: remote)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                delegate.completion = { [weak self] result in
                    if case .failure(let error) = result,
                       let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                        self?.lock.withLock { self?.resumeData[remote] = data }
                    }
                    continuation.resume(with: result)
                }
                task.resume()
            }
        } onCancel: {
            task.cancel { [weak self] data in
                if let data { self?.lock.withLock { self?.resumeData[remote] = data } }
            }
        }
    }

    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Int64) -> Void
    var completion: ((Result<URL, Error>) -> Void)?

    init(progress: @escaping @Sendable (Int64) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(ModelStore.StoreError.httpStatus(http.statusCode)))
            return
        }
        // Le fichier du système disparaît à la sortie de cette méthode : on le déplace tout de suite.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("model-" + UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            finish(.success(kept))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        completion?(result)
        completion = nil
    }
}
