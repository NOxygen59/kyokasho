// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation
import PDFKit
import Vision

/// Ce qu'on donne à un moteur : une page de PDF, ou une image (banc d'essai).
public enum OCRInput: @unchecked Sendable {
    case pdfPage(url: URL, index: Int)
    case image(CGImage)
}

/// Un moteur OCR : entrée → lignes de texte avec boîtes (ligne + caractères).
public protocol OCREngine: Sendable {
    var id: String { get }
    /// Faux tant que le modèle n'est pas téléchargé.
    var isAvailable: Bool { get }
    func recognize(_ input: OCRInput) async throws -> OCRPage
}

public extension OCREngine {
    var isAvailable: Bool { true }
}

// MARK: - Rendu d'une page de PDF en image

public enum PageRenderer {
    /// Rend la `cropBox` d'origine de la page en niveaux de gris (OCR : la couleur n'aide pas et
    /// coûte 4× plus de mémoire), côté le plus long ≈ `longSide` pixels.
    public static func render(url: URL, pageIndex: Int, longSide: Int = 3000) throws -> CGImage {
        try render(url: url, pageIndex: pageIndex, gray: true) { size in Double(longSide) / max(size.width, size.height, 1) }
    }

    /// Miniature en couleur, `width` pixels de large (bibliothèque, bande des pages).
    public static func thumbnail(document: CGPDFDocument, pageIndex: Int, width: Int) throws -> CGImage {
        try render(document, pageIndex: pageIndex, gray: false) { size in Double(width) / max(size.width, 1) }
    }

    private static func render(url: URL, pageIndex: Int, gray: Bool, scale: (CGSize) -> Double) throws -> CGImage {
        // Document partagé (`PDFPool`) : un gros PDF n'est pas relu en entier à chaque page.
        // Rendu sous le verrou : Core Graphics ne promet rien si deux fils dessinent le même document.
        try PDFPool.withCGDocument(url) { try render($0, pageIndex: pageIndex, gray: gray, scale: scale) }
    }

    private static func render(_ pdf: CGPDFDocument, pageIndex: Int, gray: Bool, scale: (CGSize) -> Double) throws -> CGImage {
        guard let page = pdf.page(at: pageIndex + 1) else { throw OCRError.pageUnavailable }
        let box = page.getBoxRect(.cropBox)
        let rotation = ((page.rotationAngle % 360) + 360) % 360
        let rotated = rotation == 90 || rotation == 270
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        let factor = scale(size)
        let width = max(1, Int((size.width * factor).rounded()))
        let height = max(1, Int((size.height * factor).rounded()))
        guard let ctx = gray
            ? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            : CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw OCRError.renderFailed
        }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        // Pas de `getDrawingTransform` : il n'agrandit jamais (la page resterait petite au centre).
        // Mise à l'échelle, rotation intrinsèque de la page, puis origine de la cropBox.
        ctx.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
        switch rotation {
        case 90: ctx.translateBy(x: 0, y: box.width); ctx.rotate(by: -.pi / 2)
        case 180: ctx.translateBy(x: box.width, y: box.height); ctx.rotate(by: .pi)
        case 270: ctx.translateBy(x: box.height, y: 0); ctx.rotate(by: .pi / 2)
        default: break
        }
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.clip(to: box)
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { throw OCRError.renderFailed }
        return image
    }
}

// MARK: - Apple Vision

/// Apple Vision, japonais + anglais, niveau `.accurate` (le seul qui lit le japonais).
public struct VisionOCREngine: OCREngine {
    public let id = OCREngineID.vision
    public var languages = ["ja-JP", "en-US"]

    public init() {}

    public func recognize(_ input: OCRInput) async throws -> OCRPage {
        let start = Date()
        let image: CGImage
        switch input {
        case .pdfPage(let url, let index): image = try PageRenderer.render(url: url, pageIndex: index)
        case .image(let cg): image = cg
        }
        try Task.checkCancellation()
        let lines = try Self.run(image, languages: languages)
        return OCRPage(engine: id, lines: lines, durationMs: Int(Date().timeIntervalSince(start) * 1000))
    }

    static func run(_ image: CGImage, languages: [String]) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        // Par défaut Vision ignore le texte de moins de 1/32 de la hauteur de l'image : les petits
        // caractères et les furigana d'un manuel passaient à la trappe.
        request.minimumTextHeight = 0.004
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let aspect = Double(image.width) / Double(max(image.height, 1))
        var lines: [OCRLine] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let box = NormBox.fromVision(observation.boundingBox)
            let count = text.count
            let vertical = CharacterLayout.isVertical(box, imageAspect: aspect, characters: count)
            // Boîtes par caractère mesurées par Vision, gardées si cohérentes.
            var measured: [NormBox?] = []
            measured.reserveCapacity(count)
            var index = text.startIndex
            while index < text.endIndex {
                let next = text.index(after: index)
                let rect = (try? candidate.boundingBox(for: index..<next))?.boundingBox
                measured.append(rect.map(NormBox.fromVision))
                index = next
            }
            let ok = CharacterLayout.validate(measured, count: count, vertical: vertical)
            let charBoxes = ok ? measured.compactMap { $0 } : CharacterLayout.proportional(text, in: box, vertical: vertical)
            lines.append(OCRLine(text: text, box: box, charBoxes: charBoxes, measuredCharBoxes: ok,
                                 vertical: vertical, confidence: Double(candidate.confidence)))
        }
        // Ordre de lecture approximatif : de haut en bas, puis de gauche à droite.
        lines.sort { abs($0.box.y - $1.box.y) > 0.01 ? $0.box.y < $1.box.y : $0.box.x < $1.box.x }
        return lines
    }
}

// MARK: - Texte intégré au PDF

/// Texte déjà présent dans le PDF (cours numériques) : exact, instantané, boîtes par caractère
/// fournies par PDFKit. Ne marche pas sur les scans (page = image).
public struct PDFTextEngine: OCREngine {
    public let id = OCREngineID.pdfText

    public init() {}

    /// La page a-t-elle assez de texte intégré pour se passer d'OCR ? (Réponse gardée en mémoire.)
    public static func hasTextLayer(url: URL, pageIndex: Int) -> Bool {
        PDFPool.hasTextLayer(url: url, pageIndex: pageIndex) { document in
            guard let s = document.page(at: pageIndex)?.string else { return false }
            return Self.isEnoughText(s)
        }
    }

    static func isEnoughText(_ s: String) -> Bool {
        s.unicodeScalars.lazy.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count >= 8
    }

    public func recognize(_ input: OCRInput) async throws -> OCRPage {
        let start = Date()
        guard case .pdfPage(let url, let index) = input else { throw OCRError.noTextLayer }
        return try PDFPool.withDocument(url) { document in
            guard let page = document.page(at: index) else { throw OCRError.pageUnavailable }
            return try Self.extract(page, start: start, engine: id)
        }
    }

    private static func extract(_ page: PDFPage, start: Date, engine id: String) throws -> OCRPage {
        guard let string = page.string, isEnoughText(string) else { throw OCRError.noTextLayer }
        let box = page.bounds(for: .cropBox)
        let ns = string as NSString
        var lines: [OCRLine] = []
        var text = ""
        var boxes: [NormBox] = []

        // Même repère que le rendu OCR (rotation intrinsèque comprise), voir `PageFrame`.
        let frame = PageFrame(box: box, rotation: page.rotation)
        func normalized(_ r: CGRect) -> NormBox {
            let a = frame.normalized(CGPoint(x: r.minX, y: r.minY)), b = frame.normalized(CGPoint(x: r.maxX, y: r.maxY))
            return NormBox(x: min(a.x, b.x), y: min(a.y, b.y), w: abs(b.x - a.x), h: abs(b.y - a.y))
        }
        let aspect = frame.rotation % 180 == 0 ? box.width / box.height : box.height / box.width
        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            defer { text = ""; boxes = [] }
            guard !trimmed.isEmpty, !boxes.isEmpty, boxes.count == text.count else { return }
            let union = boxes.dropFirst().reduce(boxes[0].rect) { $0.union($1.rect) }
            let lineBox = NormBox(union)
            let vertical = CharacterLayout.isVertical(lineBox, imageAspect: aspect, characters: text.count)
            lines.append(OCRLine(text: text, box: lineBox, charBoxes: boxes, measuredCharBoxes: true,
                                 vertical: vertical, confidence: 1))
        }

        var i = 0
        var previous: CGRect?
        while i < ns.length {
            let range = ns.rangeOfComposedCharacterSequence(at: i)
            let piece = ns.substring(with: range)
            i = NSMaxRange(range)
            if piece == "\n" || piece == "\r" || piece == "\r\n" { flush(); previous = nil; continue }
            let r = page.characterBounds(at: range.location)
            // Saut de ligne implicite : le caractère n'est plus sur la même ligne visuelle.
            if let p = previous, !r.isEmpty, abs(r.midY - p.midY) > max(r.height, p.height) * 0.8,
               abs(r.midX - p.midX) > max(r.width, p.width) * 0.8 {
                flush()
            }
            text += piece
            boxes.append(r.isEmpty ? (boxes.last ?? normalized(CGRect(x: box.minX, y: box.minY, width: 0, height: 0))) : normalized(r))
            if !r.isEmpty { previous = r }
        }
        flush()
        return OCRPage(engine: id, lines: lines, durationMs: Int(Date().timeIntervalSince(start) * 1000))
    }
}

// MARK: - Documents PDF partagés

/// Un seul document ouvert gardé par type (PDFKit pour le texte, Core Graphics pour le rendu) :
/// l'OCR de tout un livre ne relit plus le fichier entier à chaque page. PDFKit n'aime pas être
/// utilisé par plusieurs fils à la fois : tout accès passe par le verrou.
public enum PDFPool {
    private static let lock = NSRecursiveLock()
    private nonisolated(unsafe) static var kit: (url: URL, document: PDFDocument)?
    private nonisolated(unsafe) static var cg: (url: URL, document: CGPDFDocument)?
    private nonisolated(unsafe) static var textLayer: [String: Bool] = [:]

    public static func withDocument<T>(_ url: URL, _ body: (PDFDocument) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        if kit?.url != url {
            guard let document = PDFDocument(url: url) else { throw OCRError.pageUnavailable }
            kit = (url, document)
        }
        return try body(kit!.document)
    }

    public static func withCGDocument<T>(_ url: URL, _ body: (CGPDFDocument) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        if cg?.url != url { cg = CGPDFDocument(url as CFURL).map { (url, $0) } }
        guard let document = cg?.document else { throw OCRError.pageUnavailable }
        return try body(document)
    }

    static func hasTextLayer(url: URL, pageIndex: Int, check: (PDFDocument) -> Bool) -> Bool {
        let key = "\(url.path)#\(pageIndex)"
        lock.lock(); defer { lock.unlock() }
        if let known = textLayer[key] { return known }
        // Fichier illisible pour l'instant : réponse « non » sans la retenir.
        guard let value = try? withDocument(url, check) else { return false }
        if textLayer.count > 20_000 { textLayer.removeAll() }
        textLayer[key] = value
        return value
    }

    /// Libère les documents (lecteur fermé, document supprimé, manque de mémoire).
    /// Peut attendre la fin d'un OCR en cours : à appeler hors du fil principal.
    public static func release(_ url: URL? = nil) {
        lock.lock(); defer { lock.unlock() }
        if url == nil || kit?.url == url { kit = nil }
        if url == nil || cg?.url == url { cg = nil }
        if let url { textLayer = textLayer.filter { !$0.key.hasPrefix(url.path + "#") } }
    }
}
