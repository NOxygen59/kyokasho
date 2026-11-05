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
    /// Garde-fous contre une archive anormale : décompressée en mémoire, page par page.
    static let maximumPageBytes: UInt64 = 256 * 1_048_576
    static let maximumTotalBytes: UInt64 = 8 * 1_073_741_824
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

    /// Écrit le PDF dans `output`. Une image par page, à sa taille : Core Graphics reprend les JPEG sans les recompresser.
    public static func makePDF(from archiveURL: URL, to output: URL) throws -> Conversion {
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            throw ImportError.unreadable(String(localized: "Ce fichier CBZ n'est pas une archive lisible.", bundle: .main))
        }
        let entries = Dictionary(archive.filter { $0.type == .file }.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let names = pageNames(Array(entries.keys))
        let total = names.reduce(UInt64(0)) { $0 + (entries[$1]?.uncompressedSize ?? 0) }
        guard total <= maximumTotalBytes else {
            throw ImportError.unreadable(String(localized: "Ce fichier CBZ est trop volumineux pour être converti.", bundle: .main))
        }
        guard let context = CGContext(output as CFURL, mediaBox: nil, nil) else {
            throw ImportError.unreadable(String(localized: "Ce fichier CBZ n'a pas pu être converti.", bundle: .main))
        }
        var pages = 0, skipped = 0
        for name in names {
            guard let entry = entries[name], entry.uncompressedSize <= maximumPageBytes else { skipped += 1; continue }
            // Une page à la fois, libérée aussitôt : un comics peut peser des centaines de Mo.
            let drawn: Bool = autoreleasepool {
                var data = Data(capacity: Int(entry.uncompressedSize))
                guard (try? archive.extract(entry, consumer: { data.append($0) })) != nil,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      image.width > 0, image.height > 0 else { return false }
                var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                context.beginPage(mediaBox: &box)
                context.draw(image, in: box)
                context.endPage()
                return true
            }
            if drawn { pages += 1 } else { skipped += 1 }
        }
        context.closePDF()
        guard pages > 0 else {
            throw ImportError.unreadable(String(localized: "Ce fichier CBZ ne contient aucune page lisible.", bundle: .main))
        }
        return Conversion(pages: pages, skipped: skipped)
    }
}

extension DocumentImporter {
    private static let comicSourcesKey = "comics.sources"

    /// Importe un `.cbz`. L'identifiant d'un document reste l'empreinte de son PDF. Or le PDF converti porte une date et
    /// change à chaque conversion : la correspondance archive → document évite donc un doublon au second import.
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
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = try ComicBookArchive.makePDF(from: source, to: temporary)
        var result = try importFile(at: temporary, displayName: displayName ?? source.lastPathComponent)
        if result.isNew {
            result.document.category = .comics
            // Lecture japonaise d'office ; le réglage du document reste modifiable.
            var settings = result.document.settingsOverride
            settings.direction = .rightToLeft
            result.document.settingsOverride = settings
            try database.save(result.document)
        }
        sources[archiveHash] = result.document.id
        try database.setStoredValue(sources, forKey: Self.comicSourcesKey)
        return result
    }
}
