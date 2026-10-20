// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB

/// Un PDF importé. `id` = empreinte SHA-256 du fichier (hexadécimal) : un même fichier importé
/// deux fois n'est stocké qu'une fois. Le fichier lui-même vit dans `DocumentStorage`, jamais modifié.
public struct Document: Codable, Identifiable, Hashable, Sendable {
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

    public init(id: String, title: String, originalFileName: String, pageCount: Int, fileSize: Int64,
                importedAt: Date = Date(), lastOpenedAt: Date? = nil, lastPageIndex: Int = 0,
                settingsJSON: String? = nil, driveFileId: String? = nil, driveRevision: String? = nil) {
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

extension Document: FetchableRecord, PersistableRecord {
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

    public var isIdentity: Bool { rotation % 360 == 0 && !split }
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

    public init(id: String = UUID().uuidString, documentId: String, pageIndex: Int, body: String,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.documentId = documentId
        self.pageIndex = pageIndex
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
