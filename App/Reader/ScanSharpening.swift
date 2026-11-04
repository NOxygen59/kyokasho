// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation
import ImageIO
import OCRKit
import ONNXOCRKit
import UniformTypeIdentifiers

/// « Nettoyage des scans » : pages scannées / photographiées repassées par `PageCleaner` (papier blanc sans
/// ombre, encre renforcée ; couleurs ou noir et blanc) ou par DE-GAN (modèle). Seulement à la demande,
/// page par page quand elle s'affiche ; résultat gardé en mémoire (quelques pages) et sur le disque (Caches).
enum ScanSharpening {
    enum Method: String, CaseIterable, Identifiable {
        case off, color, mono, degan
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: return String(localized: "Aucun")
            case .color: return String(localized: "Papier blanc (couleurs gardées)")
            case .mono: return String(localized: "Noir et blanc net")
            case .degan: return String(localized: "DE-GAN (modèle)")
            }
        }
    }

    static let storageKey = "reader.scanCleaning"
    /// Grand côté de l'image traitée : assez pour des kanji nets, sans exploser le temps de calcul.
    static let longSide: CGFloat = 2000

    static var method: Method {
        if let raw = UserDefaults.standard.string(forKey: storageKey), let m = Method(rawValue: raw) { return m }
        // Ancien réglage (DE-GAN seul) : activé → nettoyage « papier blanc », bien meilleur sur les photos.
        return UserDefaults.standard.bool(forKey: "reader.sharpenScans") ? .color : .off
    }
    static var enabled: Bool { method != .off && (method != .degan || isInstalled) }
    static var isInstalled: Bool { PageEnhancer.isInstalled() }

    static func key(documentId: String, page: Int) -> String { "\(documentId)-\(page)" }

    // MARK: Cache mémoire (lu par PDFKit depuis ses fils de dessin)

    private static let lock = NSLock()
    private static var images: [String: CGImage] = [:]
    private static var order: [String] = []
    private static let memoryLimit = 8

    static func image(for key: String) -> CGImage? {
        guard enabled else { return nil }
        let full = key + "-" + method.rawValue
        return lock.withLock { images[full] }
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

    private static func file(_ key: String) -> URL { directory.appendingPathComponent(key + "-v2.png") }

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
    static func prepare(key pageKey: String, fileURL: URL, page: Int) throws -> Bool {
        let chosen = Self.method
        guard chosen != .off else { return false }
        // Une image par page et par méthode.
        let key = pageKey + "-" + chosen.rawValue
        if lock.withLock({ images[key] != nil }) { return false }
        let path = file(key)
        if let source = CGImageSourceCreateWithURL(path as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            store(image, for: key)
            return true
        }
        let image: CGImage
        if chosen == .degan {
            guard let (gray, width, height) = render(fileURL: fileURL, page: page, color: false) else { return false }
            try Task.checkCancellation()
            let clean = try PageEnhancer.enhance(gray: gray, width: width, height: height)
            guard let made = makeImage(clean, width: width, height: height, color: false) else { return false }
            image = made
        } else {
            guard let (rgb, width, height) = render(fileURL: fileURL, page: page, color: true) else { return false }
            try Task.checkCancellation()
            let clean = PageCleaner.clean(rgb, width: width, height: height, mode: chosen == .mono ? .mono : .color)
            guard let made = makeImage(clean, width: width, height: height, color: true) else { return false }
            image = made
        }
        store(image, for: key)
        if let dest = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
        return true
    }

    /// Page d'origine (cadre de rognage du fichier, sans rotation) en niveaux de gris, par Core Graphics
    /// (indépendant du document affiché par PDFKit).
    private static func render(fileURL: URL, page index: Int, color: Bool) -> ([UInt8], Int, Int)? {
        guard let document = CGPDFDocument(fileURL as CFURL), let page = document.page(at: index + 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = longSide / max(box.width, box.height)
        let width = Int((box.width * scale).rounded()), height = Int((box.height * scale).rounded())
        let channels = color ? 4 : 1
        var pixels = [UInt8](repeating: 255, count: width * height * channels)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * channels,
                                      space: color ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: color ? CGImageAlphaInfo.noneSkipLast.rawValue : 0) else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.interpolationQuality = .high
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.drawPDFPage(page)
            return true
        }
        guard drawn else { return nil }
        guard color else { return (pixels, width, height) }
        // RGBA → RGB (format de `PageCleaner`).
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            rgb[i * 3] = pixels[i * 4]; rgb[i * 3 + 1] = pixels[i * 4 + 1]; rgb[i * 3 + 2] = pixels[i * 4 + 2]
        }
        return (rgb, width, height)
    }

    /// Octets gris (1 par pixel) ou RGB (3 par pixel) → image.
    private static func makeImage(_ pixels: [UInt8], width: Int, height: Int, color: Bool) -> CGImage? {
        let data: Data
        if color {
            var rgba = [UInt8](repeating: 255, count: width * height * 4)
            for i in 0..<(width * height) {
                rgba[i * 4] = pixels[i * 3]; rgba[i * 4 + 1] = pixels[i * 3 + 1]; rgba[i * 4 + 2] = pixels[i * 3 + 2]
            }
            data = Data(rgba)
        } else {
            data = Data(pixels)
        }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: color ? 32 : 8,
                       bytesPerRow: width * (color ? 4 : 1),
                       space: color ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: color ? CGImageAlphaInfo.noneSkipLast.rawValue : 0),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
