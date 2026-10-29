// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB

/// Catégorie choisie à l'import, pour se repérer sur l'accueil (RET-039, #54). Modifiable dans « Ce document ».
public enum DocumentCategory: String, Codable, CaseIterable, Sendable {
    case book, textbook

    public var title: String {
        switch self {
        case .book: return "Livre"
        case .textbook: return "Manuel"
        }
    }
}

/// Un PDF importé. `id` = empreinte SHA-256 du fichier (hexadécimal) : un même fichier importé
/// deux fois n'est stocké qu'une fois. Le fichier lui-même vit dans `DocumentStorage`, jamais modifié.
public struct LibraryDocument: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var originalFileName: String
    public var pageCount: Int
    public var fileSize: Int64
    public var importedAt: Date
    public var lastOpenedAt: Date?
    /// Index (base 0) de la dernière page source lue.
    public var lastPageIndex: Int
    /// Réglages propres au document, encodés en JSON (`nil` = réglages globaux).
    public var settingsJSON: String?
    /// Origine Google Drive (pour la resynchronisation), si importé depuis Drive.
    public var driveFileId: String?
    public var driveRevision: String?
    /// Index (base 0) de la page source qui porte le numéro 1 imprimé (manuels avec pages de garde).
    public var firstPageIndex: Int
    /// Livre ou manuel (`nil` : pas encore choisi, documents d'avant la migration `v5-document-category`).
    public var category: DocumentCategory?

    public init(id: String, title: String, originalFileName: String, pageCount: Int, fileSize: Int64,
                importedAt: Date = Date(), lastOpenedAt: Date? = nil, lastPageIndex: Int = 0,
                settingsJSON: String? = nil, driveFileId: String? = nil, driveRevision: String? = nil,
                firstPageIndex: Int = 0, category: DocumentCategory? = nil) {
        self.id = id
        self.title = title
        self.originalFileName = originalFileName
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.importedAt = importedAt
        self.lastOpenedAt = lastOpenedAt
        self.lastPageIndex = lastPageIndex
        self.settingsJSON = settingsJSON
        self.driveFileId = driveFileId
        self.driveRevision = driveRevision
        self.firstPageIndex = firstPageIndex
        self.category = category
    }

    /// Numéro affiché pour une page source : la page `firstPageIndex` porte « 1 » ;
    /// les pages d'avant (couverture, sommaire…) sont en chiffres romains, comme dans les livres.
    public func pageLabel(_ index: Int) -> String {
        // Pages modifiées (#49, R5) : chaque page garde son numéro imprimé ; sans numéro (page ajoutée, garde) :
        // chiffres romains, comme les pages avant la page 1.
        if let numbers = PrintedPageNumbers.numbers(for: id, pageCount: pageCount) {
            return numbers[index].map(String.init) ?? Self.roman(index + 1)
        }
        let n = index - firstPageIndex + 1
        return n >= 1 ? String(n) : Self.roman(index + 1)
    }

    /// Page source pour un numéro imprimé (borné au document).
    public func sourceIndex(forPrintedPage n: Int) -> Int {
        if let numbers = PrintedPageNumbers.numbers(for: id, pageCount: pageCount) {
            // Numéro exact, sinon la première page qui vient après (numéro retiré avec sa page), sinon la dernière.
            return numbers.firstIndex(of: n) ?? numbers.firstIndex { ($0 ?? .min) > n } ?? pageCount - 1
        }
        return max(0, min(pageCount - 1, n - 1 + firstPageIndex))
    }

    static func roman(_ value: Int) -> String {
        var n = max(1, value)
        var out = ""
        for (v, s) in [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
                       (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")] {
            while n >= v { out += s; n -= v }
        }
        return out
    }

    public var settingsOverride: ReaderSettingsOverride {
        get {
            guard let settingsJSON, let data = settingsJSON.data(using: .utf8),
                  let value = try? JSONDecoder().decode(ReaderSettingsOverride.self, from: data) else {
                return ReaderSettingsOverride()
            }
            return value
        }
        set {
            if newValue.isEmpty {
                settingsJSON = nil
            } else if let data = try? JSONEncoder.sorted.encode(newValue) {
                settingsJSON = String(decoding: data, as: UTF8.self)
            }
        }
    }
}

extension LibraryDocument: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "document"
}

/// Transformations d'affichage d'une page source (le PDF n'est jamais modifié).
public struct PageTransform: Codable, Hashable, Sendable {
    public var documentId: String
    public var pageIndex: Int
    /// Rotation supplémentaire en degrés (0, 90, 180, 270).
    public var rotation: Int
    /// Coupe une page scannée en double en deux pages.
    public var split: Bool
    /// Rognage automatique calculé (fractions 0…1 de la page, origine en haut à gauche), en cache.
    public var autoCrop: NormalizedRect?

    public init(documentId: String, pageIndex: Int, rotation: Int = 0, split: Bool = false, autoCrop: NormalizedRect? = nil) {
        self.documentId = documentId
        self.pageIndex = pageIndex
        self.rotation = rotation
        self.split = split
        self.autoCrop = autoCrop
    }

}

extension PageTransform: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pageTransform"
}

/// Rectangle en fractions de la page (0…1), origine en haut à gauche.
public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
}

/// Rectangle en coordonnées de page PDF (points, origine en bas à gauche de la mediaBox).
public struct PageRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct Highlight: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var documentId: String
    public var pageIndex: Int
    public var rectsJSON: String
    public var color: HighlightColor
    public var text: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, documentId: String, pageIndex: Int, rects: [PageRect],
                color: HighlightColor, text: String, createdAt: Date = Date()) {
        self.id = id
        self.documentId = documentId
        self.pageIndex = pageIndex
        self.rectsJSON = (try? String(decoding: JSONEncoder.sorted.encode(rects), as: UTF8.self)) ?? "[]"
        self.color = color
        self.text = text
        self.createdAt = createdAt
    }

    public var rects: [PageRect] {
        (try? JSONDecoder().decode([PageRect].self, from: Data(rectsJSON.utf8))) ?? []
    }
}

extension Highlight: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "highlight"
}

public enum HighlightColor: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case yellow, green, blue, pink, orange
}

/// Dessin au stylet d'une page, au format `PKDrawing.dataRepresentation()`,
/// exprimé dans le repère canonique de la page (voir `PageGeometry`).
public struct InkDrawing: Codable, Hashable, Sendable {
    public var documentId: String
    public var pageIndex: Int
    public var data: Data
    public var updatedAt: Date

    public init(documentId: String, pageIndex: Int, data: Data, updatedAt: Date = Date()) {
        self.documentId = documentId
        self.pageIndex = pageIndex
        self.data = data
        self.updatedAt = updatedAt
    }
}

extension InkDrawing: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "inkDrawing"
}

public struct Bookmark: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var documentId: String
    public var pageIndex: Int
    public var title: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, documentId: String, pageIndex: Int, title: String, createdAt: Date = Date()) {
        self.id = id
        self.documentId = documentId
        self.pageIndex = pageIndex
        self.title = title
        self.createdAt = createdAt
    }
}

extension Bookmark: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "bookmark"
}

public struct PageComment: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var documentId: String
    public var pageIndex: Int
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Dessin de la note (`PKDrawing.dataRepresentation()`), si on y a écrit au Pencil.
    public var drawing: Data?
    /// Ancre sur la page (repère absolu de la page source, comme les surlignages) et mot ancré.
    public var anchorX: Double?
    public var anchorY: Double?
    public var anchorWidth: Double?
    public var anchorHeight: Double?
    public var anchorText: String?

    public init(id: String = UUID().uuidString, documentId: String, pageIndex: Int, body: String,
                createdAt: Date = Date(), updatedAt: Date = Date(), drawing: Data? = nil) {
        self.id = id
        self.documentId = documentId
        self.pageIndex = pageIndex
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.drawing = drawing
    }

    public var anchorRect: PageRect? {
        get {
            guard let anchorX, let anchorY, let anchorWidth, let anchorHeight else { return nil }
            return PageRect(x: anchorX, y: anchorY, width: anchorWidth, height: anchorHeight)
        }
        set {
            anchorX = newValue?.x; anchorY = newValue?.y
            anchorWidth = newValue?.width; anchorHeight = newValue?.height
        }
    }
}

extension PageComment: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pageComment"
}

/// Prompt prédéfini à copier avec l'image d'une page.
public struct AIPrompt: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var position: Int

    public init(id: String = UUID().uuidString, title: String, body: String, position: Int) {
        self.id = id
        self.title = title
        self.body = body
        self.position = position
    }

    public static let defaults: [AIPrompt] = [
        AIPrompt(title: "Expliquer la slide",
                 body: "Explique cette slide en français, simplement. Ajoute les furigana aux kanji et propose un petit schéma si ça aide.",
                 position: 0),
        AIPrompt(title: "Traduire la page",
                 body: "Traduis cette page de cours en français, en gardant la mise en forme. Mets les furigana aux kanji difficiles.",
                 position: 1),
        AIPrompt(title: "Vocabulaire",
                 body: "Liste le vocabulaire important de cette page : mot, lecture en hiragana, sens en français, et une phrase d'exemple.",
                 position: 2),
        AIPrompt(title: "Questions de révision",
                 body: "À partir de cette page, écris 5 questions de révision avec leurs réponses, en français.",
                 position: 3),
    ]
}

extension AIPrompt: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "aiPrompt"
}

extension JSONEncoder {
    /// Encodeur à clés triées : sortie stable (comparaisons, tests).
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// Résultat OCR d'une page en cache (contenu = `OCRPage` encodé en JSON par OCRKit).
public struct OCRResultRecord: Codable, Hashable, Sendable {
    public var documentId: String
    public var pageIndex: Int
    public var engine: String
    public var json: Data
    public var durationMs: Int
    public var createdAt: Date

    public init(documentId: String, pageIndex: Int, engine: String, json: Data, durationMs: Int, createdAt: Date = Date()) {
        self.documentId = documentId
        self.pageIndex = pageIndex
        self.engine = engine
        self.json = json
        self.durationMs = durationMs
        self.createdAt = createdAt
    }
}

extension OCRResultRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "ocrResult"
}

/// Échantillon du banc d'essai OCR : une image (fichier) et son texte de référence.
public struct BenchSample: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    /// Nom du fichier image dans le dossier du banc d'essai.
    public var imageFile: String
    public var referenceText: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, title: String, imageFile: String, referenceText: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.imageFile = imageFile
        self.referenceText = referenceText
        self.createdAt = createdAt
    }
}

extension BenchSample: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "benchSample"
}

/// Un passage d'un moteur sur un échantillon : taux d'erreur de caractères et durée.
public struct BenchRun: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var sampleId: String
    public var engine: String
    public var cer: Double
    public var durationMs: Int
    public var text: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, sampleId: String, engine: String, cer: Double, durationMs: Int,
                text: String, createdAt: Date = Date()) {
        self.id = id
        self.sampleId = sampleId
        self.engine = engine
        self.cer = cer
        self.durationMs = durationMs
        self.text = text
        self.createdAt = createdAt
    }
}

extension BenchRun: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "benchRun"
}

extension PageComment {
    /// Texte modifié dans la liste des notes (recette 1.3.2 (62), N1) : `nil` si rien ne change, ou si le texte
    /// deviendrait vide sur une note sans dessin (une note vide ne sert à rien ; « Supprimer » existe pour ça).
    public func editing(body newBody: String, at date: Date = Date()) -> PageComment? {
        let trimmed = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != body, !trimmed.isEmpty || drawing != nil else { return nil }
        var note = self
        note.body = trimmed
        note.updatedAt = date
        return note
    }
}

/// Numéros imprimés des pages des documents dont les pages ont été modifiées (#49, R5), tenus à jour par l'app depuis
/// `AppDatabase.printedNumbers()` (au lancement et après chaque modification des pages ou de la page 1). Un document
/// absent, ou dont le nombre de pages ne correspond pas (valeur périmée), garde la numérotation par `firstPageIndex`.
public enum PrintedPageNumbers {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var table: [String: [Int?]] = [:]

    public static func set(_ numbers: [String: [Int?]]) {
        lock.lock(); defer { lock.unlock() }
        table = numbers
    }

    public static func numbers(for documentId: String, pageCount: Int) -> [Int?]? {
        lock.lock(); defer { lock.unlock() }
        guard let numbers = table[documentId], numbers.count == pageCount else { return nil }
        return numbers
    }
}
