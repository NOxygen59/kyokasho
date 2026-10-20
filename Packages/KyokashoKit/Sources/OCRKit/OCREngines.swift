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
    func recognize(_ input: OCRInput) async throws -> OCRPage
}

// MARK: - Rendu d'une page de PDF en image

public enum PageRenderer {
    /// Rend la `cropBox` d'origine de la page en niveaux de gris (OCR : la couleur n'aide pas et
    /// coûte 4× plus de mémoire), côté le plus long ≈ `longSide` pixels.
    public static func render(url: URL, pageIndex: Int, longSide: Int = 2400) throws -> CGImage {
        guard let pdf = CGPDFDocument(url as CFURL), let page = pdf.page(at: pageIndex + 1) else {
            throw OCRError.pageUnavailable
        }
        let box = page.getBoxRect(.cropBox)
        let rotation = ((page.rotationAngle % 360) + 360) % 360
        let rotated = rotation == 90 || rotation == 270
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        let scale = Double(longSide) / max(size.width, size.height, 1)
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw OCRError.renderFailed
        }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        // Transformation de CoreGraphics qui tient compte de la rotation intrinsèque de la page.
        let transform = page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height),
                                                 rotate: 0, preserveAspectRatio: true)
        ctx.concatenate(transform)
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

    /// La page a-t-elle assez de texte intégré pour se passer d'OCR ?
    public static func hasTextLayer(url: URL, pageIndex: Int) -> Bool {
        guard let page = PDFDocument(url: url)?.page(at: pageIndex), let s = page.string else { return false }
        return s.unicodeScalars.lazy.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count >= 8
    }

    public func recognize(_ input: OCRInput) async throws -> OCRPage {
        let start = Date()
        guard case .pdfPage(let url, let index) = input else { throw OCRError.noTextLayer }
        guard let document = PDFDocument(url: url), let page = document.page(at: index) else { throw OCRError.pageUnavailable }
        guard let string = page.string, Self.hasTextLayer(url: url, pageIndex: index) else { throw OCRError.noTextLayer }
        let box = page.bounds(for: .cropBox)
        let ns = string as NSString
        var lines: [OCRLine] = []
        var text = ""
        var boxes: [NormBox] = []

        func normalized(_ r: CGRect) -> NormBox {
            NormBox(x: (r.minX - box.minX) / box.width, y: (box.maxY - r.maxY) / box.height,
                    w: r.width / box.width, h: r.height / box.height)
        }
        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            defer { text = ""; boxes = [] }
            guard !trimmed.isEmpty, !boxes.isEmpty, boxes.count == text.count else { return }
            let union = boxes.dropFirst().reduce(boxes[0].rect) { $0.union($1.rect) }
            let lineBox = NormBox(union)
            let vertical = CharacterLayout.isVertical(lineBox, imageAspect: box.width / box.height, characters: text.count)
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
