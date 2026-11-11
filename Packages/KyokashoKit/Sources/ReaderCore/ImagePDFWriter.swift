// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Compression
import CoreGraphics
import Foundation
import ImageIO

/// Écrit un PDF d'images, une page à la fois, directement sur le disque.
///
/// Pourquoi pas Core Graphics : `CGContext` pour PDF garde en mémoire les flux de toutes les images jusqu'à `closePDF()`.
/// Mesuré sur Mac (05/11/2026) : mémoire +641 Mo pour un PDF de 686 Mo, fichier presque vide jusqu'à la fin ; écrire par
/// morceaux puis les fusionner ne libère rien. Un gros CBZ pouvait donc faire fermer l'app sur iPad. Ici, la mémoire reste
/// celle d'une seule page, et chaque octet écrit est connu d'avance pour le contrôle de la place.
///
/// Format : PDF 1.4 à table `xref` classique. Objets 1 (catalogue) et 2 (liste des pages, écrite à la fin), puis trois
/// objets par page. Un JPEG est repris tel quel (`DCTDecode`) ; le reste est compressé sans perte (`FlateDecode`).
final class ImagePDFWriter {
    /// Image prête à écrire : son flux et de quoi le décrire.
    struct Page {
        let width: Int
        let height: Int
        let colorSpace: String
        /// Entrées du dictionnaire de l'image : filtre et paramètres.
        let filter: String
        let stream: Data
    }

    private let handle: FileHandle
    private var offsets: [UInt64] = [0, 0, 0]
    private var position: UInt64 = 0
    private var pageObjects: [Int] = []

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
        try write(Data("%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8))
    }

    deinit { try? handle.close() }

    private func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
        position += UInt64(data.count)
    }

    private func beginObject(_ number: Int) throws {
        if number >= offsets.count { offsets.append(contentsOf: repeatElement(0, count: number - offsets.count + 1)) }
        offsets[number] = position
        try write(Data("\(number) 0 obj\n".utf8))
    }

    func add(_ page: Page) throws {
        let number = offsets.count
        let (pageObject, contents, image) = (number, number + 1, number + 2)
        try beginObject(pageObject)
        try write(Data("<</Type/Page/Parent 2 0 R/MediaBox[0 0 \(page.width) \(page.height)]/Contents \(contents) 0 R/Resources<</XObject<</Im0 \(image) 0 R>>>>>>\nendobj\n".utf8))
        let drawing = Data("q \(page.width) 0 0 \(page.height) 0 0 cm /Im0 Do Q".utf8)
        try beginObject(contents)
        try write(Data("<</Length \(drawing.count)>>\nstream\n".utf8))
        try write(drawing)
        try write(Data("\nendstream\nendobj\n".utf8))
        try beginObject(image)
        try write(Data("<</Type/XObject/Subtype/Image/Width \(page.width)/Height \(page.height)/ColorSpace/\(page.colorSpace)/BitsPerComponent 8\(page.filter)/Length \(page.stream.count)>>\nstream\n".utf8))
        try write(page.stream)
        try write(Data("\nendstream\nendobj\n".utf8))
        pageObjects.append(pageObject)
    }

    /// Écrit la liste des pages et la table, puis ferme le fichier.
    func finish() throws {
        try beginObject(1)
        try write(Data("<</Type/Catalog/Pages 2 0 R>>\nendobj\n".utf8))
        try beginObject(2)
        let kids = pageObjects.map { "\($0) 0 R" }.joined(separator: " ")
        try write(Data("<</Type/Pages/Count \(pageObjects.count)/Kids[\(kids)]>>\nendobj\n".utf8))
        let table = position
        var xref = "xref\n0 \(offsets.count)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { xref += String(format: "%010llu 00000 n \n", offset) }
        xref += "trailer\n<</Size \(offsets.count)/Root 1 0 R>>\nstartxref\n\(table)\n%%EOF\n"
        try write(Data(xref.utf8))
        try handle.close()
    }

    // MARK: Préparation d'une page

    /// JPEG repris sans recompression si possible : ni perte, ni calcul.
    static func jpegPage(at url: URL) -> Page? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              (CGImageSourceGetType(source) as String?) == "public.jpeg",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (properties[kCGImagePropertyDepth] as? Int) == 8,
              (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1,
              max(width, height) <= ComicBookArchive.maximumPageSide,
              let model = properties[kCGImagePropertyColorModel] as? String,
              // CMYK : souvent inversé dans les JPEG d'Adobe. Il passe par le décodage, plus sûr.
              model == (kCGImagePropertyColorModelRGB as String) || model == (kCGImagePropertyColorModelGray as String),
              let stream = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let space = model == (kCGImagePropertyColorModelGray as String) ? "DeviceGray" : "DeviceRGB"
        return Page(width: width, height: height, colorSpace: space, filter: "/Filter/DCTDecode", stream: stream)
    }

    /// Pixels de l'image, sur fond blanc, compressés sans perte. Une image en niveaux de gris le reste : trois fois moins de
    /// données. Le filtre « Up » (chaque ligne moins la précédente) aide beaucoup les planches de manga.
    ///
    /// Un seul tampon de pixels, filtré sur place : sur 6 000 × 6 000 (le plus grand côté permis), 144 Mo plutôt que 252.
    static func losslessPage(_ image: CGImage) -> Page? {
        let width = image.width, height = image.height
        let gray = image.colorSpace?.model == .monochrome
        let components = gray ? 1 : 3
        let drawn = gray ? 1 : 4
        // Une case libre devant chaque ligne pour l'octet de filtre PDF. Une case entière : Core Graphics refuse des pixels de
        // 32 bits qui ne sont pas alignés sur 4 octets.
        let stride = (width + 1) * drawn
        let rowBytes = width * components
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: stride * height)
        defer { buffer.deallocate() }
        let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let info = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        guard let context = CGContext(data: buffer + drawn, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: stride, space: space, bitmapInfo: info) else { return nil }
        let box = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(box)
        context.draw(image, in: box)
        // Du bas vers le haut : la ligne du dessus reste intacte pour le calcul. Dans une ligne, de gauche à droite : l'écriture
        // ne dépasse jamais la lecture, puisqu'on passe de 4 octets à 3 (ou de 1 à 1).
        for row in Swift.stride(from: height - 1, through: 0, by: -1) {
            let source = buffer + row * stride + drawn
            let above: UnsafeMutablePointer<UInt8>? = row > 0 ? source - stride : nil
            var out = source
            for column in 0..<width {
                for component in 0..<components {
                    let offset = column * drawn + component
                    out.pointee = source[offset] &- (above?[offset] ?? 0)
                    out += 1
                }
            }
            source[-1] = 2
        }
        // Lignes resserrées, de haut en bas, avant compression. Les zones peuvent se chevaucher : `update` le permet.
        for row in 0..<height {
            (buffer + row * (rowBytes + 1)).update(from: buffer + row * stride + drawn - 1, count: rowBytes + 1)
        }
        guard let stream = zlib(UnsafeBufferPointer(start: buffer, count: (rowBytes + 1) * height)) else { return nil }
        let colorSpace = gray ? "DeviceGray" : "DeviceRGB"
        let filter = "/Filter/FlateDecode/DecodeParms<</Predictor 12/Colors \(components)/BitsPerComponent 8/Columns \(width)>>"
        return Page(width: width, height: height, colorSpace: colorSpace, filter: filter, stream: stream)
    }

    static func zlib(_ input: [UInt8]) -> Data? { input.withUnsafeBufferPointer { zlib($0) } }

    /// `COMPRESSION_ZLIB` produit du deflate brut : un flux PDF veut aussi l'en-tête et la somme Adler-32 de zlib.
    /// Sortie dans un tampon réservé mais non touché : seule la taille compressée coûte de la mémoire, et `Data` le reprend
    /// sans copie.
    static func zlib(_ input: UnsafeBufferPointer<UInt8>) -> Data? {
        // Marge pour le pire cas : des données incompressibles sortent à peine plus grosses.
        let capacity = input.count + input.count / 100 + 1024
        let output = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity + 6)
        guard let base = input.baseAddress else { output.deallocate(); return nil }
        let size = compression_encode_buffer(output + 2, capacity, base, input.count, nil, COMPRESSION_ZLIB)
        guard size > 0 else { output.deallocate(); return nil }
        output[0] = 0x78
        output[1] = 0x9C
        var a: UInt32 = 1, b: UInt32 = 0
        var index = 0
        while index < input.count {
            // 5 552 octets : le plus long bloc sans dépasser 32 bits avant le modulo.
            let end = min(index + 5552, input.count)
            while index < end {
                a &+= UInt32(base[index])
                b &+= a
                index += 1
            }
            a %= 65521
            b %= 65521
        }
        let adler = (b << 16) | a
        let tail = output + 2 + size
        tail[0] = UInt8(adler >> 24)
        tail[1] = UInt8((adler >> 16) & 255)
        tail[2] = UInt8((adler >> 8) & 255)
        tail[3] = UInt8(adler & 255)
        return Data(bytesNoCopy: output, count: size + 6, deallocator: .custom { pointer, _ in pointer.deallocate() })
    }

    // MARK: Titre

    /// Ajoute le titre par une mise à jour incrémentale du PDF : le fichier d'origine est repris à l'identique et l'empreinte
    /// change, sans rien décoder ni garder en mémoire. `nil` si la fin du PDF n'a pas la forme classique attendue.
    static func titleUpdate(fileTail: String, fileSize: UInt64, title: String) -> Data? {
        func last(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.matches(
                in: fileTail, range: NSRange(fileTail.startIndex..., in: fileTail)).last else { return nil }
            return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: fileTail).map { String(fileTail[$0]) } }
        }
        guard fileTail.contains("trailer"), let start = last(#"startxref\s+(\d+)"#)?.first,
              let root = last(#"/Root\s+(\d+\s+\d+\s+R)"#)?.first,
              let sizeText = last(#"/Size\s+(\d+)"#)?.first, let number = Int(sizeText) else { return nil }
        let hex = "FEFF" + title.utf16.map { String(format: "%04X", $0) }.joined()
        let object = "\n\(number) 0 obj\n<</Title<\(hex)>>>\nendobj\n"
        let objectOffset = fileSize + 1
        let table = fileSize + UInt64(object.utf8.count)
        let xref = "xref\n\(number) 1\n" + String(format: "%010llu 00000 n \n", objectOffset)
            + "trailer\n<</Size \(number + 1)/Root \(root)/Info \(number) 0 R/Prev \(start)>>\nstartxref\n\(table)\n%%EOF\n"
        return Data((object + xref).utf8)
    }
}
