// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import OCRKit
import UIKit

/// Miniatures de pages : cache mémoire limité (vidé automatiquement en cas de manque de mémoire)
/// + cache disque JPEG. Génération hors du fil principal, une à la fois, sans doublons.
final class ThumbnailCache: @unchecked Sendable {
    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let queue = DispatchQueue(label: "kyokasho.thumbnails", qos: .utility)
    private let lock = NSLock()
    private var waiting: [String: [(UIImage?) -> Void]] = [:]
    /// Dernier PDF ouvert pour le rendu (n'est touché que depuis `queue`) : évite de rouvrir le
    /// fichier pour chaque miniature d'un même document. Core Graphics, bien plus léger que PDFKit.
    private var openDocument: (url: URL, document: CGPDFDocument)?

    init(directory: URL) {
        self.directory = directory
        memory.totalCostLimit = 32 << 20 // ~32 Mo de miniatures décodées au maximum
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func key(_ documentId: String, _ page: Int, _ width: Int) -> String {
        "\(documentId)-\(page)-\(width)"
    }

    /// Image déjà en mémoire (appel instantané, pour l'affichage immédiat).
    func cached(documentId: String, page: Int, width: Int) -> UIImage? {
        memory.object(forKey: key(documentId, page, width) as NSString)
    }

    /// Fournit la miniature (mémoire → disque → rendu), rappel sur le fil principal.
    func thumbnail(documentId: String, fileURL: URL, page: Int, width: Int, completion: @escaping (UIImage?) -> Void) {
        let k = key(documentId, page, width)
        if let image = memory.object(forKey: k as NSString) {
            completion(image)
            return
        }
        lock.lock()
        if waiting[k] != nil {
            waiting[k]!.append(completion)
            lock.unlock()
            return
        }
        waiting[k] = [completion]
        lock.unlock()

        queue.async { [self] in
            let image = autoreleasepool { load(k: k, fileURL: fileURL, page: page, width: width) }
            if let image { memory.setObject(image, forKey: k as NSString, cost: image.cost) }
            lock.lock()
            let callbacks = waiting.removeValue(forKey: k) ?? []
            lock.unlock()
            DispatchQueue.main.async { callbacks.forEach { $0(image) } }
        }
    }

    private func load(k: String, fileURL: URL, page: Int, width: Int) -> UIImage? {
        let activity = ActivityCenter.shared.begin(.thumbnails)
        defer { ActivityCenter.shared.end(activity) }
        let diskURL = directory.appendingPathComponent(k).appendingPathExtension("jpg")
        if let data = try? Data(contentsOf: diskURL), let image = UIImage(data: data) {
            return image.preparingForDisplay() ?? image
        }
        let document: CGPDFDocument
        if let open = openDocument, open.url == fileURL {
            document = open.document
        } else {
            guard let opened = CGPDFDocument(fileURL as CFURL) else { return nil }
            openDocument = (fileURL, opened)
            document = opened
        }
        guard let cg = try? PageRenderer.thumbnail(document: document, pageIndex: page, width: width) else { return nil }
        let image = UIImage(cgImage: cg)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: diskURL, options: .atomic)
        }
        return image.preparingForDisplay() ?? image
    }

    func removeAll(for documentId: String) {
        queue.async { [directory] in
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for file in files where file.hasPrefix(documentId + "-") {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
        }
        memory.removeAllObjects()
    }

    /// Libère la mémoire (alerte mémoire, passage en arrière-plan).
    func trim() {
        memory.removeAllObjects()
        queue.async { [self] in openDocument = nil }
    }
}

private extension UIImage {
    var cost: Int {
        guard let cg = cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }
}
