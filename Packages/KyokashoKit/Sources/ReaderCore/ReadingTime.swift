// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Temps de lecture active affiché sur l'accueil à la place de « Progression XX/XX pages » (RET-037, #52).
///
/// « Active » : un livre est ouvert à l'écran et l'app est au premier plan. Le compteur démarre à l'ouverture du
/// lecteur et s'arrête à sa fermeture, au passage en arrière-plan ou au verrouillage. Il part de zéro : le temps
/// passé avant cette version n'a jamais été enregistré.
public struct ReadingClock: Equatable, Sendable {
    /// Plafond d'une seule séance : protège le total si un arrêt n'a pas été reçu (app tuée en arrière-plan).
    public static let maxSession: TimeInterval = 6 * 3600

    public private(set) var total: TimeInterval
    public private(set) var startedAt: Date?

    public init(total: TimeInterval = 0) { self.total = max(0, total) }

    public mutating func start(at date: Date) {
        if startedAt == nil { startedAt = date }
    }

    /// Arrête la séance et ajoute sa durée (bornée entre 0 et ``maxSession``). Sans séance en cours, rien.
    public mutating func stop(at date: Date) {
        guard let startedAt else { return }
        total += min(max(0, date.timeIntervalSince(startedAt)), Self.maxSession)
        self.startedAt = nil
    }

    /// Total, séance en cours comprise.
    public func elapsed(at date: Date) -> TimeInterval {
        guard let startedAt else { return total }
        return total + min(max(0, date.timeIntervalSince(startedAt)), Self.maxSession)
    }

    /// « 35 min », « 4 h 12 », « 2 j 5 h », « 1 mois 3 j » : la plus grande unité utile et la suivante.
    public static func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let hours = minutes / 60, days = hours / 24, months = days / 30
        if months > 0 { return days % 30 > 0 ? String(localized: "\(months) mois \(days % 30) j", bundle: .main) : String(localized: "\(months) mois", bundle: .main) }
        if days > 0 { return hours % 24 > 0 ? String(localized: "\(days) j \(hours % 24) h", bundle: .main) : String(localized: "\(days) j", bundle: .main) }
        if hours > 0 { return String(format: String(localized: "%d h %02d", bundle: .main), hours, minutes % 60) }
        return String(localized: "\(minutes) min", bundle: .main)
    }
}

/// Rangement d'une séance au moment où elle a lieu : mettre un manga à la corbeille, l'effacer ou le déplacer plus tard
/// ne doit pas faire changer de case le temps déjà lu.
public enum ReadingScope: String, Codable, Sendable {
    case manga, textbook, book, unclassified

    public init(document: LibraryDocument) {
        if document.isInMangaSpace {
            self = .manga
        } else {
            switch document.category {
            case .textbook: self = .textbook
            case .book: self = .book
            case nil: self = .unclassified
            }
        }
    }
}

/// Temps par espace, d'après le journal et la séance en cours. Une seule source pour l'accueil : Manga et le reste
/// forment toujours le total.
public struct ReadingBreakdown: Codable, Equatable, Sendable {
    public var manga: TimeInterval = 0
    public var textbook: TimeInterval = 0
    public var book: TimeInterval = 0
    public var unclassified: TimeInterval = 0

    public var total: TimeInterval { manga + textbook + book + unclassified }

    public init() {}

    /// Livres & Manuels : tout ce qui n'est pas Manga. Le total inclut le temps d'avant le journal et les séances trop
    /// courtes pour y figurer.
    public func study(total: TimeInterval) -> TimeInterval { max(0, total - manga) }

    mutating func add(_ seconds: TimeInterval, to scope: ReadingScope?) {
        switch scope {
        case .manga: manga += seconds
        case .textbook: textbook += seconds
        case .book: book += seconds
        case .unclassified, nil: unclassified += seconds
        }
    }
}

/// Une séance de lecture active : début, durée et document (journal des séances, préalable au tableau de bord).
public struct ReadingSession: Codable, Equatable, Sendable {
    public var start: Date
    public var seconds: Int
    /// Vide une fois le document supprimé : le temps reste compté dans ses jours, sans lien avec le livre.
    public var documentId: String
    /// `nil` : séance d'avant cette version. Clé ignorée par les anciennes versions, sans dommage pour le journal.
    public var scope: ReadingScope?
    /// Pages différentes affichées pendant la séance, et mots cherchés au dictionnaire.
    public var pages: Int?
    public var lookups: Int?

    public init(start: Date, seconds: Int, documentId: String, scope: ReadingScope? = nil, pages: Int? = nil, lookups: Int? = nil) {
        self.start = start
        self.seconds = seconds
        self.documentId = documentId
        self.scope = scope
        self.pages = pages
        self.lookups = lookups
    }

    private enum CodingKeys: String, CodingKey {
        case start = "s", seconds = "d", documentId = "id", scope = "c", pages = "p", lookups = "w"
    }
}

/// Journal des séances de lecture active : l'historique dont le futur tableau de bord aura besoin (fréquences par
/// jour, par heure, par livre). Le total de ``ReadingClock`` reste la référence de l'accueil.
public struct ReadingSessionLog: Equatable, Sendable {
    /// Séances trop courtes pour compter (page ouverte puis refermée).
    public static let minSeconds = 5
    /// Environ 6 ans à cinq séances par jour ; au-delà, les plus anciennes partent (≈ 600 Ko au plus).
    public static let maxEntries = 10_000

    public private(set) var sessions: [ReadingSession]
    /// Séances sorties du journal à sa limite : leur détail est perdu, mais leur temps reste dans le total et dans sa case.
    public private(set) var retired = ReadingBreakdown()

    public init(sessions: [ReadingSession] = [], retired: ReadingBreakdown = ReadingBreakdown()) {
        self.sessions = sessions
        self.retired = retired
    }

    private struct Stored: Codable {
        var sessions: [ReadingSession]
        var retired: ReadingBreakdown
    }

    /// Ajoute la séance `start…end`, durée bornée comme ``ReadingClock`` ; rien sous ``minSeconds``.
    public mutating func record(documentId: String, start: Date, end: Date, scope: ReadingScope? = nil,
                                pages: Int? = nil, lookups: Int? = nil) {
        let seconds = Int(min(max(0, end.timeIntervalSince(start)), ReadingClock.maxSession))
        guard seconds >= Self.minSeconds else { return }
        sessions.append(ReadingSession(start: start, seconds: seconds, documentId: documentId, scope: scope, pages: pages, lookups: lookups))
        if sessions.count > Self.maxEntries {
            let removed = sessions.count - Self.maxEntries
            for session in sessions.prefix(removed) { retired.add(TimeInterval(session.seconds), to: session.scope) }
            sessions.removeFirst(removed)
        }
    }

    /// Document supprimé : ses séances perdent le lien avec lui mais gardent leur date et leur durée.
    public mutating func forget(documentId: String) {
        guard !documentId.isEmpty else { return }
        for index in sessions.indices where sessions[index].documentId == documentId {
            sessions[index].documentId = ""
        }
    }

    /// Remplacement d'un cours (lot C2, revue R2 P3 n°5) : les séances de lecture suivent le
    /// document mis à jour — c'est la même activité de lecture du même livre. Rejouable :
    /// l'ancien identifiant épuisé, un nouveau passage ne change rien.
    public mutating func remapDocumentId(from oldId: String, to newId: String) {
        guard oldId != newId else { return }
        for index in sessions.indices where sessions[index].documentId == oldId {
            sessions[index].documentId = newId
        }
    }

    /// Temps total du journal : la seule source du compteur de l'accueil et du tableau de bord.
    public var totalSeconds: TimeInterval { retired.total + TimeInterval(sessions.reduce(0) { $0 + $1.seconds }) }

    /// Ventilation du temps lu. `current` range les séances d'avant cette version, sans rangement enregistré, d'après
    /// l'état actuel de leur document (corbeille comprise). La séance en cours compte dans sa case.
    public func breakdown(current: [String: ReadingScope], activeScope: ReadingScope? = nil,
                          activeSeconds: TimeInterval = 0) -> ReadingBreakdown {
        var result = retired
        for session in sessions {
            result.add(TimeInterval(session.seconds), to: session.scope ?? current[session.documentId])
        }
        result.add(activeSeconds, to: activeScope)
        return result
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(Stored(sessions: sessions, retired: retired)) }

    /// Données absentes ou illisibles : journal vide (le total de l'accueil n'en dépend pas).
    public static func decode(_ data: Data?) -> ReadingSessionLog {
        guard let data else { return ReadingSessionLog() }
        if let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            return ReadingSessionLog(sessions: stored.sessions, retired: stored.retired)
        }
        // Simple liste : forme écrite par les versions précédentes.
        guard let sessions = try? JSONDecoder().decode([ReadingSession].self, from: data) else { return ReadingSessionLog() }
        return ReadingSessionLog(sessions: sessions)
    }
}
