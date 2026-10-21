// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation
import ImageIO
import ONNXOCRKit
import UniformTypeIdentifiers

/// « Netteté des scans » : pages scannées repassées par DE-GAN (fond blanc, caractères noirs nets).
/// Seulement à la demande (réglage), page par page quand elle s'affiche ; résultat gardé en mémoire
/// (quelques pages) et sur le disque (Caches), pour ne jamais recalculer une page déjà faite.
enum ScanSharpening {
    static let storageKey = "reader.sharpenScans"
    /// Grand côté de l'image traitée : assez pour des kanji nets, sans exploser le temps de calcul.
    static let longSide: CGFloat = 2000

    static var enabled: Bool { UserDefaults.standard.bool(forKey: storageKey) }
    static var isInstalled: Bool { PageEnhancer.isInstalled() }

    static func key(documentId: String, page: Int) -> String { "\(documentId)-\(page)" }

    // MARK: Cache mémoire (lu par PDFKit depuis ses fils de dessin)

    private static let lock = NSLock()
    private static var images: [String: CGImage] = [:]
    private static var order: [String] = []
    private static let memoryLimit = 8

    static func image(for key: String) -> CGImage? {
        guard enabled else { return nil }
        return lock.withLock { images[key] }
    }

    private static func store(_ image: CGImage, for key: String) {
        lock.withLock {
            images[key] = image
            order.removeAll { $0 == key }
            order.append(key)
            while order.count > memoryLimit { images[order.removeFirst()] = nil }
        }
    }

    static func clearMemory() { lock.withLock { images = [:]; order = [] } }

    // MARK: Cache disque

    private static let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("Sharpened", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func file(_ key: String) -> URL { directory.appendingPathComponent(key + "-v1.png") }

    /// Supprime les pages nettoyées d'un document (livre supprimé).
    static func removeCache(documentId: String) {
        let prefix = documentId + "-"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in files where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        lock.withLock {
            images = images.filter { !$0.key.hasPrefix(prefix) }
            order.removeAll { $0.hasPrefix(prefix) }
        }
    }

    // MARK: Calcul

    /// Prépare la page (disque ou DE-GAN) hors du fil principal. `true` si une nouvelle image est prête.
    static func prepare(key: String, fileURL: URL, page: Int) throws -> Bool {
        if lock.withLock({ images[key] != nil }) { return false }
        let path = file(key)
        if let source = CGImageSourceCreateWithURL(path as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            store(image, for: key)
            return true
        }
        guard let (gray, width, height) = render(fileURL: fileURL, page: page) else { return false }
        try Task.checkCancellation()
        let clean = try PageEnhancer.enhance(gray: gray, width: width, height: height)
        guard let image = grayImage(clean, width: width, height: height) else { return false }
        store(image, for: key)
        if let dest = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
        return true
    }

    /// Page d'origine (cadre de rognage du fichier, sans rotation) en niveaux de gris, par Core Graphics
    /// (indépendant du document affiché par PDFKit).
    private static func render(fileURL: URL, page index: Int) -> ([UInt8], Int, Int)? {
        guard let document = CGPDFDocument(fileURL as CFURL), let page = document.page(at: index + 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = longSide / max(box.width, box.height)
        let width = Int((box.width * scale).rounded()), height = Int((box.height * scale).rounded())
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.interpolationQuality = .high
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.drawPDFPage(page)
            return true
        }
        return drawn ? (pixels, width, height) : nil
    }

    private static func grayImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
