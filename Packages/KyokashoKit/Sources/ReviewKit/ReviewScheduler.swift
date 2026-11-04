// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import FSRS

/// Réglages des révisions (enregistrés par l'app).
public struct ReviewSettings: Codable, Equatable, Sendable {
    /// Probabilité visée de se souvenir au moment de la révision (FSRS « desired retention »).
    public var retention: Double = 0.9
    public var maximumIntervalDays: Double = 36500
    public var newCardsPerDay: Int = 20
    public var maximumReviewsPerDay: Int = 200
    /// Petites variations d'intervalle pour ne pas tout revoir le même jour.
    public var fuzz: Bool = true
    /// Heure de début de la journée de révision (comme Anki : 4 h).
    public var dayStartHour: Int = 4
    /// Paquet où vont les nouvelles cartes.
    public var defaultDeckId: Int64?
    public var defaultTemplateId: Int64?
    /// Envoyer aussi chaque nouvelle carte à AnkiMobile.
    public var sendToAnkiMobile = false
    public var ankiMobileDeck = "Kyōkasho"
    public var ankiMobileNoteType = "Kyōkasho"
    /// Image de la zone de la page sur la carte.
    public var includeImage = true
    /// Audio du mot sur la carte (téléchargé une fois, puis local).
    public var includeAudio = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReviewSettings()
        retention = min(0.99, max(0.7, (try? c.decode(Double.self, forKey: .retention)) ?? d.retention))
        maximumIntervalDays = max(1, (try? c.decode(Double.self, forKey: .maximumIntervalDays)) ?? d.maximumIntervalDays)
        newCardsPerDay = max(0, (try? c.decode(Int.self, forKey: .newCardsPerDay)) ?? d.newCardsPerDay)
        maximumReviewsPerDay = max(1, (try? c.decode(Int.self, forKey: .maximumReviewsPerDay)) ?? d.maximumReviewsPerDay)
        fuzz = (try? c.decode(Bool.self, forKey: .fuzz)) ?? d.fuzz
        dayStartHour = min(23, max(0, (try? c.decode(Int.self, forKey: .dayStartHour)) ?? d.dayStartHour))
        defaultDeckId = try? c.decode(Int64.self, forKey: .defaultDeckId)
        defaultTemplateId = try? c.decode(Int64.self, forKey: .defaultTemplateId)
        sendToAnkiMobile = (try? c.decode(Bool.self, forKey: .sendToAnkiMobile)) ?? d.sendToAnkiMobile
        ankiMobileDeck = (try? c.decode(String.self, forKey: .ankiMobileDeck)) ?? d.ankiMobileDeck
        ankiMobileNoteType = (try? c.decode(String.self, forKey: .ankiMobileNoteType)) ?? d.ankiMobileNoteType
        includeImage = (try? c.decode(Bool.self, forKey: .includeImage)) ?? d.includeImage
        includeAudio = (try? c.decode(Bool.self, forKey: .includeAudio)) ?? d.includeAudio
    }

    /// Début de la « journée de révision » contenant `date`.
    public func dayStart(for date: Date, calendar: Calendar = .current) -> Date {
        let shifted = date.addingTimeInterval(-Double(dayStartHour) * 3600)
        return calendar.startOfDay(for: shifted).addingTimeInterval(Double(dayStartHour) * 3600)
    }
}

/// Planification FSRS (bibliothèque swift-fsrs, MIT).
public struct ReviewScheduler: Sendable {
    let fsrs: FSRS

    public init(settings: ReviewSettings = ReviewSettings()) {
        fsrs = FSRS(parameters: FSRSParameters(requestRetention: settings.retention,
                                               maximumInterval: settings.maximumIntervalDays,
                                               enableFuzz: settings.fuzz,
                                               enableShortTerm: true))
    }

    /// Carte après la réponse + ligne d'historique.
    public func review(_ card: StudyCard, grade: Grade, now: Date = Date(), duration: Double = 0) throws -> (StudyCard, ReviewEntry) {
        let result = try fsrs.next(card: Self.fsrsCard(card), now: now, grade: Self.rating(grade))
        var updated = card
        Self.apply(result.card, to: &updated)
        updated.modifiedAt = now
        let log = ReviewEntry(cardId: card.id ?? 0, grade: grade, state: card.state, reviewedAt: now,
                              elapsedDays: result.log.elapsedDays, scheduledDays: result.card.scheduledDays,
                              stability: result.card.stability, difficulty: result.card.difficulty, duration: duration)
        return (updated, log)
    }

    /// Prochaine échéance pour chaque réponse (affichée sous les boutons).
    public func preview(_ card: StudyCard, now: Date = Date()) -> [Grade: Date] {
        guard let preview = try? fsrs.repeat(card: Self.fsrsCard(card), now: now) else { return [:] }
        var out: [Grade: Date] = [:]
        for grade in Grade.allCases {
            if let item = preview[Self.rating(grade)] { out[grade] = item.card.due }
        }
        return out
    }

    /// Probabilité de se souvenir maintenant (0…1).
    public func retrievability(_ card: StudyCard, now: Date = Date()) -> Double {
        guard card.state != .new else { return 0 }
        return fsrs.getRetrievability(card: Self.fsrsCard(card), now: now).number
    }

    static func rating(_ g: Grade) -> Rating {
        switch g {
        case .again: return .again
        case .hard: return .hard
        case .good: return .good
        case .easy: return .easy
        }
    }

    static func fsrsCard(_ c: StudyCard) -> Card {
        Card(due: c.due, stability: c.stability, difficulty: c.difficulty, elapsedDays: c.elapsedDays,
             scheduledDays: c.scheduledDays, learningSteps: c.learningSteps, reps: c.reps, lapses: c.lapses,
             state: CardState(rawValue: c.state.rawValue) ?? .new, lastReview: c.lastReview)
    }

    static func apply(_ f: Card, to c: inout StudyCard) {
        c.due = f.due
        c.stability = f.stability
        c.difficulty = f.difficulty
        c.elapsedDays = f.elapsedDays
        c.scheduledDays = f.scheduledDays
        c.learningSteps = f.learningSteps
        c.reps = f.reps
        c.lapses = f.lapses
        c.state = MemoryState(rawValue: f.state.rawValue) ?? .review
        c.lastReview = f.lastReview
    }

    /// « 10 min », « 3 j », « 2 mois »… pour les boutons.
    public static func intervalLabel(from now: Date, to due: Date) -> String {
        let s = max(0, due.timeIntervalSince(now))
        if s < 60 { return String(localized: "< 1 min", bundle: .main) }
        if s < 3600 { return "\(Int((s / 60).rounded())) min" }
        if s < 86400 { return "\(Int((s / 3600).rounded())) h" }
        let days = s / 86400
        if days < 30 { return "\(Int(days.rounded())) j" }
        if days < 365 { return String(format: String(localized: "%.1f mois", bundle: .main), days / 30).replacingOccurrences(of: ".0", with: "") }
        return String(format: String(localized: "%.1f an", bundle: .main), days / 365).replacingOccurrences(of: ".0", with: "")
    }
}
