// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Accelerate
import CoreGraphics
import Foundation

// Briques communes aux moteurs à réseaux de neurones (PP-OCRv5, NDLOCR-Lite) :
// image → tenseur, détection des lignes, décodage des caractères, ordre de lecture.
// Écrit pour Kyōkasho d'après la description publique des modèles (aucun code repris).

// MARK: - Image RGB en mémoire

/// Image RGB 8 bits (pixels entrelacés R, G, B), origine en haut à gauche.
public struct RGBImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 3)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: UInt8 = 0) {
        self.init(width: width, height: height, pixels: [UInt8](repeating: fill, count: width * height * 3))
    }

    /// Depuis une image Core Graphics (gris ou couleur).
    public init?(_ image: CGImage) {
        guard let rgba = Self.draw(image, width: image.width, height: image.height) else { return nil }
        self = rgba
    }

    public var cgImage: CGImage? {
        guard width > 0, height > 0 else { return nil }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeBytes { src in
            rgba.withUnsafeMutableBytes { Self.convert(src.baseAddress!, rgba: false, to: $0.baseAddress!, width: width, height: height) }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Redimensionne (Core Graphics, interpolation haute qualité : bonne réduction des grandes pages).
    public func resized(width w: Int, height h: Int) -> RGBImage {
        guard w > 0, h > 0, w != width || h != height, let cg = cgImage,
              let out = Self.draw(cg, width: w, height: h) else { return w == width && h == height ? self : RGBImage(width: max(1, w), height: max(1, h), fill: 255) }
        return out
    }

    /// Partie de l'image (pixels, bornée à l'image).
    public func cropped(x: Int, y: Int, width w: Int, height h: Int) -> RGBImage {
        let x0 = max(0, min(width - 1, x)), y0 = max(0, min(height - 1, y))
        let x1 = max(x0 + 1, min(width, x + w)), y1 = max(y0 + 1, min(height, y + h))
        let cw = x1 - x0, ch = y1 - y0
        var out = [UInt8](repeating: 0, count: cw * ch * 3)
        for row in 0..<ch {
            let src = ((y0 + row) * width + x0) * 3
            out.replaceSubrange(row * cw * 3..<(row + 1) * cw * 3, with: pixels[src..<src + cw * 3])
        }
        return RGBImage(width: cw, height: ch, pixels: out)
    }

    /// Rotation de 90° dans le sens inverse des aiguilles (une colonne verticale devient une ligne).
    public func rotatedCounterClockwise() -> RGBImage {
        var out = [UInt8](repeating: 0, count: pixels.count)
        // (x, y) → (y, width - 1 - x) dans une image de taille height × width.
        for y in 0..<height {
            for x in 0..<width {
                let s = (y * width + x) * 3
                let d = ((width - 1 - x) * height + y) * 3
                out[d] = pixels[s]; out[d + 1] = pixels[s + 1]; out[d + 2] = pixels[s + 2]
            }
        }
        return RGBImage(width: height, height: width, pixels: out)
    }

    /// Image posée en haut à gauche d'un fond `fill` de taille `w × h` (le reste est rogné).
    public func padded(width w: Int, height h: Int, fill: UInt8 = 0) -> RGBImage {
        var out = RGBImage(width: w, height: h, fill: fill)
        let cw = min(w, width), ch = min(h, height)
        for row in 0..<ch {
            let src = row * width * 3
            out.pixels.replaceSubrange(row * w * 3..<row * w * 3 + cw * 3, with: pixels[src..<src + cw * 3])
        }
        return out
    }

    /// Tenseur 1 × 3 × H × W en Float32 : `(pixel × scale − mean) / std`, canaux RGB ou BGR.
    public func chw(mean: [Float], std: [Float], scale: Float = 1 / 255, bgr: Bool = false) -> [Float] {
        let plane = width * height
        var out = [Float](repeating: 0, count: plane * 3)
        guard plane > 0 else { return out }
        // Accelerate : octets entrelacés (pas de 3) → plan Float, puis × (scale / std) + (−mean / std).
        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for c in 0..<3 {
                    let channel = bgr ? 2 - c : c
                    let plane0 = dst.baseAddress! + c * plane
                    vDSP_vfltu8(src.baseAddress! + channel, 3, plane0, 1, vDSP_Length(plane))
                    var a = scale / std[c], b = -mean[c] / std[c]
                    vDSP_vsmsa(plane0, 1, &a, &b, plane0, 1, vDSP_Length(plane))
                }
            }
        }
        return out
    }

    private static func draw(_ image: CGImage, width: Int, height: Int) -> RGBImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var pixels = [UInt8](repeating: 0, count: width * height * 3)
        // `ctx` gardé vivant pendant la lecture de sa mémoire.
        withExtendedLifetime(ctx) {
            pixels.withUnsafeMutableBytes { convert(data, rgba: true, to: $0.baseAddress!, width: width, height: height) }
        }
        return RGBImage(width: width, height: height, pixels: pixels)
    }

    /// RGBA (4 octets) ↔ RGB (3 octets) avec vImage, au lieu d'une boucle pixel par pixel.
    private static func convert(_ src: UnsafeRawPointer, rgba: Bool, to dst: UnsafeMutableRawPointer, width: Int, height: Int) {
        var input = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: src), height: vImagePixelCount(height),
                                  width: vImagePixelCount(width), rowBytes: width * (rgba ? 4 : 3))
        var output = vImage_Buffer(data: dst, height: vImagePixelCount(height), width: vImagePixelCount(width),
                                   rowBytes: width * (rgba ? 3 : 4))
        if rgba {
            vImageConvert_RGBA8888toRGB888(&input, &output, vImage_Flags(kvImageNoFlags))
        } else {
            vImageConvert_RGB888toRGBA8888(&input, nil, 255, &output, false, vImage_Flags(kvImageNoFlags))
        }
    }
}

// MARK: - Détection de lignes « DB » (PP-OCR)

/// Post-traitement d'une carte de probabilité « texte » (sortie du détecteur DB) :
/// seuil, dilatation 2×2, composantes connexes, score moyen, agrandissement de la boîte.
public enum DBPostprocess {
    public struct Box: Equatable, Sendable {
        public var rect: CGRect
        public var score: Float
    }

    /// `map` : H × W probabilités. Boîtes rendues dans le repère `outputSize` (image d'origine).
    public static func boxes(map: [Float], width: Int, height: Int, outputSize: CGSize,
                             threshold: Float = 0.3, boxThreshold: Float = 0.5,
                             unclipRatio: Double = 1.6, minSide: Double = 3) -> [Box] {
        precondition(map.count == width * height)
        // Seuil + dilatation 2×2 (relie les morceaux d'un même mot).
        var mask = [Bool](repeating: false, count: map.count)
        for y in 0..<height {
            for x in 0..<width where map[y * width + x] > threshold {
                mask[y * width + x] = true
                if x + 1 < width { mask[y * width + x + 1] = true }
                if y + 1 < height {
                    mask[(y + 1) * width + x] = true
                    if x + 1 < width { mask[(y + 1) * width + x + 1] = true }
                }
            }
        }
        var seen = [Bool](repeating: false, count: map.count)
        var stack: [Int] = []
        var result: [Box] = []
        let sx = Double(outputSize.width) / Double(width), sy = Double(outputSize.height) / Double(height)
        for start in 0..<map.count where mask[start] && !seen[start] {
            var minX = width, minY = height, maxX = 0, maxY = 0
            stack.append(start)
            seen[start] = true
            while let i = stack.popLast() {
                let x = i % width, y = i / width
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let j = ny * width + nx
                        if mask[j] && !seen[j] { seen[j] = true; stack.append(j) }
                    }
                }
            }
            let w = Double(maxX - minX + 1), h = Double(maxY - minY + 1)
            guard min(w, h) >= minSide else { continue }
            // Score « rapide » : moyenne des probabilités dans la boîte.
            var sum: Float = 0
            for y in minY...maxY { for x in minX...maxX { sum += map[y * width + x] } }
            let score = sum / Float(w * h)
            guard score >= boxThreshold else { continue }
            // Agrandissement : distance = aire × ratio / périmètre (la carte DB rétrécit le texte).
            let d = w * h * unclipRatio / (2 * (w + h))
            let r = CGRect(x: Double(minX) - d, y: Double(minY) - d, width: w + 2 * d, height: h + 2 * d)
            let scaled = CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)
                .intersection(CGRect(origin: .zero, size: outputSize))
            guard !scaled.isNull, scaled.width > minSide, scaled.height > minSide else { continue }
            result.append(Box(rect: scaled, score: score))
        }
        return result
    }
}

// MARK: - Décodage des caractères

public enum SequenceDecoder {
    /// CTC glouton (PP-OCR) : classe 0 = blanc, doublons consécutifs fusionnés.
    /// `charset` sans le blanc. Renvoie le texte, la confiance et la position (pas de temps) de chaque caractère.
    public static func ctc(_ logits: [Float], steps: Int, classes: Int, charset: [String])
        -> (text: String, confidence: Double, positions: [Int]) {
        var text = "", positions: [Int] = [], probs: [Float] = []
        var previous = -1
        for t in 0..<steps {
            let row = t * classes
            var best = 0, bestValue = -Float.infinity
            for c in 0..<classes where logits[row + c] > bestValue { bestValue = logits[row + c]; best = c }
            defer { previous = best }
            guard best != 0, best != previous, best - 1 < charset.count else { continue }
            text += charset[best - 1]
            positions.append(t)
            probs.append(bestValue)
        }
        let confidence = probs.isEmpty ? 0 : Double(probs.reduce(0, +)) / Double(probs.count)
        return (text, confidence, positions)
    }

    /// PARSeq glouton (NDLOCR) : classe 0 = fin de texte, sinon `charset[classe − 1]`.
    public static func parseq(_ logits: [Float], steps: Int, classes: Int, charset: [String]) -> String {
        var text = ""
        for t in 0..<steps {
            let row = t * classes
            var best = 0, bestValue = -Float.infinity
            for c in 0..<classes where logits[row + c] > bestValue { bestValue = logits[row + c]; best = c }
            if best == 0 { break }
            if best - 1 < charset.count { text += charset[best - 1] }
        }
        return text
    }

    /// Liste de caractères du fichier `NDLmoji.yaml` (`charset_train`), un par point de code (comme Python).
    public static func ndlCharset(yaml: String) -> [String]? {
        guard let line = yaml.split(separator: "\n").first(where: { $0.hasPrefix("  charset_train:") }),
              let first = line.firstIndex(of: "\""), let last = line.lastIndex(of: "\""), first < last else { return nil }
        var body = String(line[line.index(after: first)..<last])
        // Échappements YAML entre guillemets utilisés par le fichier : \" et \\.
        body = body.replacingOccurrences(of: "\\\\", with: "\u{0}").replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\u{0}", with: "\\")
        return body.unicodeScalars.map { String($0) }
    }

    /// Dictionnaire PP-OCR (une entrée par ligne) + l'espace ajoutée à la fin, comme PaddleOCR.
    public static func paddleCharset(dict: String) -> [String] {
        var lines = dict.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        if lines.last == "" { lines.removeLast() }
        return lines + [" "]
    }
}

// MARK: - Boîtes de caractères et ordre de lecture

public enum NeuralLayout {
    /// Boîtes de caractères à partir de leur centre le long de la ligne (fractions 0…1 de la longueur).
    public static func characterBoxes(count: Int, centers: [Double], in box: NormBox, vertical: Bool) -> [NormBox] {
        guard count > 0, centers.count == count else { return [] }
        var out: [NormBox] = []
        for i in 0..<count {
            let previous = i > 0 ? (centers[i - 1] + centers[i]) / 2 : max(0, centers[i] - (count > 1 ? (centers[1] - centers[0]) / 2 : 0.5))
            let next = i + 1 < count ? (centers[i] + centers[i + 1]) / 2 : min(1, centers[i] + (count > 1 ? (centers[i] - centers[i - 1]) / 2 : 0.5))
            let a = max(0, min(1, previous)), b = max(a, min(1, next))
            out.append(vertical
                ? NormBox(x: box.x, y: box.y + a * box.h, w: box.w, h: (b - a) * box.h)
                : NormBox(x: box.x + a * box.w, y: box.y, w: (b - a) * box.w, h: box.h))
        }
        return out
    }

    /// Ordre de lecture. Page surtout verticale : blocs de haut en bas, dans un bloc les colonnes
    /// de droite à gauche. Sinon : de haut en bas, puis de gauche à droite.
    public static func readingOrder(_ lines: [OCRLine]) -> [OCRLine] {
        let verticalCount = lines.filter(\.vertical).count
        guard verticalCount * 2 > lines.count else {
            return lines.sorted { abs($0.box.y - $1.box.y) > min($0.box.h, $1.box.h) * 0.5 ? $0.box.y < $1.box.y : $0.box.x < $1.box.x }
        }
        // Blocs : lignes dont les bandes verticales se chevauchent d'au moins la moitié.
        var blocks: [(top: Double, bottom: Double, lines: [OCRLine])] = []
        for line in lines.sorted(by: { $0.box.y < $1.box.y }) {
            let top = line.box.y, bottom = line.box.y + line.box.h
            if let i = blocks.firstIndex(where: { b in
                let overlap = min(b.bottom, bottom) - max(b.top, top)
                return overlap > min(b.bottom - b.top, bottom - top) * 0.5
            }) {
                blocks[i].top = min(blocks[i].top, top)
                blocks[i].bottom = max(blocks[i].bottom, bottom)
                blocks[i].lines.append(line)
            } else {
                blocks.append((top, bottom, [line]))
            }
        }
        return blocks.sorted { $0.top < $1.top }.flatMap { block in
            block.lines.sorted { a, b in
                let ax = a.box.x + a.box.w / 2, bx = b.box.x + b.box.w / 2
                return abs(ax - bx) > min(a.box.w, b.box.w) * 0.5 ? ax > bx : a.box.y < b.box.y
            }
        }
    }
}
