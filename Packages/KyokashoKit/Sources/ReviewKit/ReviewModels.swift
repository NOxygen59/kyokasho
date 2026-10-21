// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB

/// Paquet de cartes.
public struct Deck: Codable, Identifiable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "deck"

    public var id: Int64?
    public var name: String
    public var createdAt: Date

    public init(id: Int64? = nil, name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// Modèle de carte : liste des champs + recto/verso (syntaxe `CardTemplate`) + CSS.
public struct NoteTemplate: Codable, Identifiable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "noteTemplate"

    public var id: Int64?
    public var name: String
    public var fieldNames: [String]
    public var front: String
    public var back: String
    public var css: String
    public var modifiedAt: Date

    public init(id: Int64? = nil, name: String, fieldNames: [String], front: String, back: String, css: String,
                modifiedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.fieldNames = fieldNames
        self.front = front
        self.back = back
        self.css = css
        self.modifiedAt = modifiedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    /// Erreur de syntaxe éventuelle (affichée dans l'éditeur).
    public var validationError: String? {
        do {
            _ = try CardTemplate(front)
            _ = try CardTemplate(back)
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// Recto et verso rendus. Un template invalide est affiché tel quel (pas de plantage).
    public func render(_ fields: [String: String]) -> (front: String, back: String) {
        let front = (try? CardTemplate(self.front))?.render(fields) ?? self.front
        let back = (try? CardTemplate(self.back))?.render(fields, extra: ["FrontSide": front]) ?? self.back
        return (front, back)
    }
}

/// État de mémoire d'une carte (algorithme FSRS).
public enum MemoryState: Int, Codable, Sendable, CaseIterable {
    case new = 0, learning = 1, review = 2, relearning = 3

    public var label: String {
        switch self {
        case .new: return "Nouvelle"
        case .learning: return "En apprentissage"
        case .review: return "À réviser"
        case .relearning: return "Réapprentissage"
        }
    }
}

/// Réponse à une révision.
public enum Grade: Int, Codable, Sendable, CaseIterable, Identifiable {
    case again = 1, hard = 2, good = 3, easy = 4

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .again: return "À revoir"
        case .hard: return "Difficile"
        case .good: return "Bien"
        case .easy: return "Facile"
        }
    }
}

/// Une carte : champs (HTML) + planification FSRS + d'où elle vient.
public struct StudyCard: Codable, Identifiable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "card"

    public var id: Int64?
    public var deckId: Int64
    public var templateId: Int64
    /// Identifiant stable (Anki `guid`) : réexporter met à jour les mêmes notes.
    public var guid: String
    /// Clé anti-doublon : « mot|lecture ».
    public var key: String
    public var fields: [String: String]
    public var tags: [String]
    public var sourceDocumentId: String?
    public var sourcePage: Int?
    public var createdAt: Date
    public var modifiedAt: Date
    public var suspended: Bool

    // FSRS
    public var due: Date
    public var stability: Double
    public var difficulty: Double
    public var elapsedDays: Double
    public var scheduledDays: Double
    public var learningSteps: Int
    public var reps: Int
    public var lapses: Int
    public var state: MemoryState
    public var lastReview: Date?

    public init(id: Int64? = nil, deckId: Int64, templateId: Int64, key: String, fields: [String: String],
                tags: [String] = [], sourceDocumentId: String? = nil, sourcePage: Int? = nil, now: Date = Date()) {
        self.id = id
        self.deckId = deckId
        self.templateId = templateId
        self.guid = AnkiGUID.make(key + "|" + UUID().uuidString)
        self.key = key
        self.fields = fields
        self.tags = tags
        self.sourceDocumentId = sourceDocumentId
        self.sourcePage = sourcePage
        self.createdAt = now
        self.modifiedAt = now
        self.suspended = false
        self.due = now
        self.stability = 0
        self.difficulty = 0
        self.elapsedDays = 0
        self.scheduledDays = 0
        self.learningSteps = 0
        self.reps = 0
        self.lapses = 0
        self.state = .new
        self.lastReview = nil
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public static func key(expression: String, reading: String) -> String { expression + "|" + reading }

    /// Premier champ non vide (titre de la carte dans les listes).
    public func title(fieldNames: [String]) -> String {
        for name in fieldNames {
            let v = CardTemplate.stripHTML(fields[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return v }
        }
        return key.components(separatedBy: "|").first ?? key
    }
}

/// Historique des révisions (une ligne par réponse).
public struct ReviewEntry: Codable, Identifiable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "reviewLog"

    public var id: Int64?
    public var cardId: Int64
    public var grade: Grade
    /// État avant la réponse.
    public var state: MemoryState
    public var reviewedAt: Date
    public var elapsedDays: Double
    public var scheduledDays: Double
    public var stability: Double
    public var difficulty: Double
    /// Temps passé sur la carte (secondes).
    public var duration: Double

    public init(id: Int64? = nil, cardId: Int64, grade: Grade, state: MemoryState, reviewedAt: Date,
                elapsedDays: Double, scheduledDays: Double, stability: Double, difficulty: Double, duration: Double) {
        self.id = id
        self.cardId = cardId
        self.grade = grade
        self.state = state
        self.reviewedAt = reviewedAt
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
        self.stability = stability
        self.difficulty = difficulty
        self.duration = duration
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// `guid` au format d'Anki (base 91 des 8 premiers octets d'un hachage).
enum AnkiGUID {
    static let table = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&()*+,-./:;<=>?@[]^_`{|}~")

    static func make(_ s: String) -> String {
        // FNV-1a 64 bits : stable, rapide, sans dépendance.
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        var out: [Character] = []
        repeat {
            out.append(table[Int(h % UInt64(table.count))])
            h /= UInt64(table.count)
        } while h > 0
        return String(out.reversed())
    }
}
