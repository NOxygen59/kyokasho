// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation
import ImageIO
import ZIPFoundation

/// Lecture expérimentale des comics `.cbz` : une archive ZIP d'images, convertie en PDF à l'import. Le lecteur, les
/// doubles pages, les miniatures et la couverture restent ainsi ceux des PDF, sans second moteur d'affichage.
public enum ComicBookArchive {
    public static let fileExtension = "cbz"
    /// Garde-fous contre une archive anormale. Taille des fichiers, et surtout taille en mémoire une fois décodés : un PNG
    /// très compressé de quelques Mo peut demander plusieurs Go. Au-delà de `maximumPageSide`, la page est réduite.
    static let maximumPageBytes: UInt64 = 128 * 1_048_576
    static let maximumTotalBytes: UInt64 = 4 * 1_073_741_824
    static let maximumPages = 5000
    static let maximumPageSide = 6000
    /// Budget d'une page qu'il faut décoder (PNG, WebP…) : 64 Mo de pixels au plus, puis son flux compressé. Au-delà, elle est
    /// réduite. Un JPEG normal n'est jamais décodé, ce budget ne le touche pas.
    static let maximumDecodedPixels = 16_000_000
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "heif", "tif", "tiff", "bmp"]

    public struct Conversion: Equatable, Sendable {
        public var pages: Int
        /// Images illisibles laissées de côté.
        public var skipped: Int
    }

    /// Pages d'une archive, dans l'ordre de lecture : 2.jpg avant 10.jpg. Sans fichiers cachés ni dossier `__MACOSX`.
    public static func pageNames(_ names: [String]) -> [String] {
        names.filter { name in
            let parts = name.split(separator: "/")
            guard let last = parts.last, !last.hasPrefix("."), !parts.contains("__MACOSX") else { return false }
            return imageExtensions.contains((name as NSString).pathExtension.lowercased())
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Moment d'un contrôle de la place, pour qu'un test puisse viser exactement l'un d'eux.
    enum SpaceCheck: Equatable { case beforeStart, beforePage, afterClose }

    public static func availableSpace(in directory: URL) -> Int64 {
        (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? .max
    }

    /// Écrit le PDF dans `output`, une image par page, à sa taille. Mémoire d'une seule page à la fois (`ImagePDFWriter`).
    /// Un JPEG est repris sans recompression, sauf s'il faut le réduire ou le remettre à l'endroit.
    public static func makePDF(from archiveURL: URL, to output: URL) throws -> Conversion {
        try makePDF(from: archiveURL, to: output) { _, directory in availableSpace(in: directory) }
    }

    static func makePDF(from archiveURL: URL, to output: URL, freeSpace: (SpaceCheck, URL) -> Int64) throws -> Conversion {
        try publishing(to: output) { temporary in try writePDF(from: archiveURL, to: temporary, freeSpace: freeSpace) }
    }

    private static func writePDF(from archiveURL: URL, to output: URL, freeSpace: (SpaceCheck, URL) -> Int64) throws -> Conversion {
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            throw ImportError.unreadable(String(localized: "Ce fichier CBZ n'est pas une archive lisible.", bundle: .main))
        }
        let entries = Dictionary(archive.filter { $0.type == .file }.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let names = pageNames(Array(entries.keys))
        // Tailles lues dans l'archive, donc non fiables : la somme ne doit pas déborder.
        let total = names.reduce(UInt64(0)) { sum, name in
            let (value, overflow) = sum.addingReportingOverflow(entries[name]?.uncompressedSize ?? 0)
            return overflow ? .max : value
        }
        guard total <= maximumTotalBytes, names.count <= maximumPages else {
            throw ImportError.unreadable(String(localized: "Ce fichier CBZ est trop volumineux pour être converti.", bundle: .main))
        }
        // Place pour les pages extraites une à une et pour le PDF, qui peut dépasser l'archive (PNG, WebP).
        let directory = output.deletingLastPathComponent()
        guard freeSpace(.beforeStart, directory) >= Int64(clamping: total + total / 2 + maximumPageBytes) else {
            throw noRoom
        }
        let writer: ImagePDFWriter
        do {
            writer = try ImagePDFWriter(url: output)
        } catch {
            throw ImportError.unreadable(String(localized: "Ce fichier CBZ n'a pas pu être converti.", bundle: .main))
        }
        let pageFile = directory.appendingPathComponent(UUID().uuidString + ".page")
        defer { try? FileManager.default.removeItem(at: pageFile) }
        var pages = 0, skipped = 0
        for name in names {
            guard let entry = entries[name], entry.uncompressedSize <= maximumPageBytes else { skipped += 1; continue }
            try ensureRoom(in: directory, forNext: Int64(clamping: entry.uncompressedSize), check: .beforePage, freeSpace: freeSpace)
            // Une page à la fois, sur disque puis lue par ImageIO : ni l'archive ni le fichier ne restent en mémoire.
            let drawn: Bool = try autoreleasepool {
                try? FileManager.default.removeItem(at: pageFile)
                guard (try? archive.extract(entry, to: pageFile)) != nil, let page = pdfPage(at: pageFile) else { return false }
                // La taille exacte est connue avant d'écrire : la réserve n'est franchie par aucune page.
                try ensureRoom(in: directory, forNext: Int64(page.stream.count), check: .beforePage, freeSpace: freeSpace)
                try writer.add(page)
                return true
            }
            if drawn { pages += 1 } else { skipped += 1 }
        }
        guard pages > 0 else {
            throw ImportError.unreadable(String(localized: "Ce fichier CBZ ne contient aucune page lisible.", bundle: .main))
        }
        try writer.finish()
        try ensureRoom(in: directory, check: .afterClose, freeSpace: freeSpace)
        return Conversion(pages: pages, skipped: skipped)
    }

    private static func pdfPage(at url: URL) -> ImagePDFWriter.Page? {
        if let jpeg = ImagePDFWriter.jpegPage(at: url) { return jpeg }
        return pageImage(at: url).flatMap(ImagePDFWriter.losslessPage)
    }

    /// Reprend le PDF à l'identique et y ajoute le titre (`ImagePDFWriter.titleUpdate`). Sur le même volume, la copie est un
    /// clone : ni temps, ni place, ni mémoire. Une fin de PDF inattendue passe par Core Graphics, page par page.
    static func rewritePDF(_ source: URL, to output: URL, title: String) throws {
        try rewritePDF(source, to: output, title: title) { _, directory in availableSpace(in: directory) }
    }

    /// Core Graphics garde tout le PDF en mémoire : au-delà de cette taille, la voie de secours refuse plutôt que de risquer
    /// une fermeture de l'app. Seuil choisi, pas encore éprouvé sur iPad. Elle ne sert qu'aux PDF à table compressée, que ni Core Graphics ni `ImagePDFWriter` n'écrivent :
    /// les CBZ déjà importés passent par la voie normale.
    static let coreGraphicsCopyLimit = 512 * 1_048_576

    static func rewritePDF(_ source: URL, to output: URL, title: String, coreGraphicsLimit: Int = coreGraphicsCopyLimit,
                           freeSpace: (SpaceCheck, URL) -> Int64) throws {
        try Task.checkCancellation()
        try publishing(to: output) { temporary in
            let directory = output.deletingLastPathComponent()
            let size = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            try ensureRoom(in: directory, forNext: Int64(size), check: .beforePage, freeSpace: freeSpace)
            if let update = try titleUpdate(of: source, title: title) {
                try FileManager.default.copyItem(at: source, to: temporary)
                let handle = try FileHandle(forWritingTo: temporary)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: update)
            } else {
                guard size <= coreGraphicsLimit else {
                    let limit = coreGraphicsLimit / 1_048_576
                    throw ImportError.unreadable(String(localized: "Ce PDF dépasse la limite de \(limit) Mo pour cette conversion.", bundle: .main))
                }
                try copyWithCoreGraphics(source, to: temporary, title: title)
            }
            try ensureRoom(in: directory, check: .afterClose, freeSpace: freeSpace)
        }
    }

    private static func titleUpdate(of source: URL, title: String) throws -> Data? {
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: size - min(size, 4096))
        guard let tail = try handle.readToEnd() else { return nil }
        return ImagePDFWriter.titleUpdate(fileTail: String(decoding: tail, as: UTF8.self), fileSize: size, title: title)
    }

    private static func copyWithCoreGraphics(_ source: URL, to output: URL, title: String) throws {
        guard let document = CGPDFDocument(source as CFURL), document.numberOfPages > 0,
              let context = CGContext(output as CFURL, mediaBox: nil, [kCGPDFContextTitle: title] as CFDictionary) else {
            throw ImportError.unreadable(String(localized: "Ce fichier CBZ n'a pas pu être converti.", bundle: .main))
        }
        for index in 1...document.numberOfPages {
            try Task.checkCancellation()
            autoreleasepool {
                guard let page = document.page(at: index) else { return }
                var box = page.getBoxRect(.mediaBox)
                context.beginPage(mediaBox: &box)
                context.drawPDFPage(page)
                context.endPage()
            }
        }
        context.closePDF()
    }

    /// Réserve gardée libre pendant l'écriture : la taille d'un PDF issu de PNG ou de WebP ne se prévoit pas, seule la place
    /// restante le permet. Vérifiée en cours de route, elle interrompt la conversion avant de remplir l'iPad.
    static let minimumFreeBytes: Int64 = 300 * 1_048_576

    private static var noRoom: ImportError {
        .unreadable(String(localized: "Pas assez d'espace libre pour convertir ce fichier CBZ.", bundle: .main))
    }

    /// Avant une page, `forNext` couvre ce qu'elle va écrire. Après la fermeture, `forNext` vaut 0.
    static func ensureRoom(in directory: URL, forNext bytes: Int64 = 0, check: SpaceCheck, freeSpace: (SpaceCheck, URL) -> Int64) throws {
        guard freeSpace(check, directory) >= minimumFreeBytes + bytes else { throw noRoom }
    }

    /// Écrit dans un fichier à soi, et ne remplace `output` qu'une fois tout réussi : un échec ne touche jamais un fichier
    /// déjà là. Suffixe `.partial` : un arrêt brutal est rattrapé par `DocumentStorage.removeAbandonedTemporaries`.
    private static func publishing<Result>(to output: URL, _ write: (URL) throws -> Result) throws -> Result {
        let temporary = output.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let result = try write(temporary)
        if FileManager.default.fileExists(atPath: output.path) {
            _ = try FileManager.default.replaceItemAt(output, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: output)
        }
        return result
    }

    /// Dimensions lues avant tout décodage. Image normale : reprise telle quelle. Trop grande ou tournée (EXIF) : passe par
    /// ImageIO, qui la réduit sans la décoder entière et la remet à l'endroit.
    static func pageImage(at url: URL) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let side = max(width, height)
        let pixels = Double(width) * Double(height)
        if orientation == 1, side <= maximumPageSide, pixels <= Double(maximumDecodedPixels) {
            return CGImageSourceCreateImageAtIndex(source, 0, options)
        }
        let shrink = min(1, (Double(maximumDecodedPixels) / pixels).squareRoot())
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: min(Int(Double(side) * shrink), maximumPageSide),
        ] as CFDictionary)
    }
}

extension DocumentImporter {
    private static let comicSourcesKey = "comics.sources"

    /// Importe un `.cbz`. L'identifiant d'un document reste l'empreinte de son PDF. Or le PDF converti porte une date et
    /// change à chaque conversion : la correspondance archive → document évite donc un doublon au second import.
    /// Fichier d'abord, puis document et correspondance dans une seule transaction : un échec ne laisse rien de partiel.
    @discardableResult
    public func importComicArchive(at source: URL, displayName: String? = nil) throws -> ImportResult {
        let archiveHash: String
        do {
            archiveHash = try Self.sha256(of: source)
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
        var sources = (try? database.storedValue([String: String].self, forKey: Self.comicSourcesKey)) ?? [:]
        if let id = sources[archiveHash], let existing = try database.document(id: id) {
            return ImportResult(document: existing, isNew: false)
        }
        try FileManager.default.createDirectory(at: storage.root, withIntermediateDirectories: true)
        // Dans le stockage : même volume que la destination, pour l'espace libre comme pour le renommage.
        let temporary = storage.root.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let conversion = try ComicBookArchive.makePDF(from: source, to: temporary)
        let hash = try Self.sha256(of: temporary)
        let pageCount = try Self.inspect(temporary).pageCount
        let fileName = displayName ?? source.lastPathComponent
        sources[archiveHash] = hash
        if let existing = try database.document(id: hash) {
            try database.setStoredValue(sources, forKey: Self.comicSourcesKey)
            return ImportResult(document: existing, isNew: false)
        }
        let destination = storage.url(for: hash)
        let installed = !FileManager.default.fileExists(atPath: destination.path)
        if installed { try FileManager.default.moveItem(at: temporary, to: destination) }
        var document = LibraryDocument(
            id: hash, title: (fileName as NSString).deletingPathExtension, originalFileName: fileName, pageCount: pageCount,
            fileSize: (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0)
        document.settingsOverride = Self.comicSettings
        do {
            try database.saveComic(document, sources: sources, sourcesKey: Self.comicSourcesKey)
        } catch {
            if installed { try? FileManager.default.removeItem(at: destination) }
            throw error
        }
        return ImportResult(document: document, isNew: true, skippedPages: conversion.skipped)
    }

    /// Indépendant des réglages généraux : une page en portrait, deux en paysage, planches larges intactes. Sens gauche →
    /// droite d'office (demande de NOxygen59, 08/11/2026 ; avant : sens japonais), modifiable dans les réglages du
    /// document. Les CBZ déjà importés gardent le sens enregistré.
    static var comicSettings: ReaderSettingsOverride {
        var settings = ReaderSettingsOverride()
        settings.layout = .auto
        settings.scrollMode = .paginated
        settings.direction = .leftToRight
        settings.firstPageAlone = true
        settings.splitWidePages = false
        settings.autoCrop = false
        settings.mangaSpace = true
        return settings
    }

    private static let comicConversionsKey = "comics.converted"

    /// « Tout sélectionner » : tome 2 avant tome 10. Sinon, la conversion suit l'ordre des touchers.
    public static func conversionOrder(_ documents: [LibraryDocument]) -> [LibraryDocument] {
        documents.filter(\.isComicArchive).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Crée un PDF ordinaire, avec OCR et étude, à partir d'un CBZ importé. Le CBZ reste en place et sans OCR.
    /// L'identifiant d'un document est l'empreinte de son fichier, et le CBZ est déjà stocké en PDF : le titre écrit ici
    /// rend le fichier différent, sinon l'import retomberait sur le même document. Un second appel rend le même PDF.
    @discardableResult
    public func convertComicToPDF(_ comic: LibraryDocument) throws -> ImportResult {
        guard comic.isComicArchive else {
            throw ImportError.unreadable(String(localized: "Ce document n'est pas un fichier CBZ.", bundle: .main))
        }
        var conversions = (try? database.storedValue([String: String].self, forKey: Self.comicConversionsKey)) ?? [:]
        if let id = conversions[comic.id], let existing = try database.document(id: id) {
            return ImportResult(document: existing, isNew: false)
        }
        let free = (try? storage.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? .max
        guard free >= comic.fileSize + comic.fileSize / 4 + 100 * 1_048_576 else {
            throw ImportError.unreadable(String(localized: "Pas assez d'espace libre pour créer ce PDF.", bundle: .main))
        }
        let temporary = storage.root.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try ComicBookArchive.rewritePDF(storage.url(for: comic.id), to: temporary, title: comic.title)
        let hash = try Self.sha256(of: temporary)
        let pageCount = try Self.inspect(temporary).pageCount
        conversions[comic.id] = hash
        if let existing = try database.document(id: hash) {
            try database.setStoredValue(conversions, forKey: Self.comicConversionsKey)
            return ImportResult(document: existing, isNew: false)
        }
        let destination = storage.url(for: hash)
        try FileManager.default.moveItem(at: temporary, to: destination)
        var document = LibraryDocument(
            id: hash, title: comic.title, originalFileName: comic.title + ".pdf", pageCount: pageCount,
            fileSize: (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0)
        document.settingsOverride = Self.comicSettings
        do {
            try database.saveComic(document, sources: conversions, sourcesKey: Self.comicConversionsKey)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return ImportResult(document: document, isNew: true)
    }
}
