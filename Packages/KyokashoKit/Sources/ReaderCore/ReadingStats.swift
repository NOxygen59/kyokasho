// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Chiffres du tableau de bord de lecture, calculés d'après le journal des séances. Sans SwiftUI pour être testés sur Mac.
///
/// Une séance compte entièrement dans le jour et l'heure de son début, même si elle passe minuit : le journal ne garde
/// que le début et la durée.
public struct ReadingStats: Equatable, Sendable {
    public enum Period: String, CaseIterable, Sendable { case week, month, year, all }
    public enum Filter: String, CaseIterable, Sendable { case everything, study, manga }

    /// Une barre du graphique : un jour, ou un mois pour les longues périodes.
    public struct Bucket: Equatable, Sendable, Identifiable {
        public let start: Date
        public var study: TimeInterval = 0
        public var manga: TimeInterval = 0
        public var id: Date { start }
        public var total: TimeInterval { study + manga }
    }

    public struct DocumentTime: Equatable, Sendable {
        public let documentId: String
        public var seconds: TimeInterval
    }

    public private(set) var total: TimeInterval = 0
    public private(set) var sessionCount = 0
    public private(set) var activeDays = 0
    public private(set) var longestSession: TimeInterval = 0
    public private(set) var pages = 0
    public private(set) var lookups = 0
    public private(set) var buckets: [Bucket] = []
    /// Barres par mois plutôt que par jour.
    public private(set) var bucketsAreMonths = false
    /// Secondes par heure de début, de 0 à 23.
    public private(set) var hours = [TimeInterval](repeating: 0, count: 24)
    /// Secondes par jour de la semaine, indice 0 = dimanche (ordre de `Calendar.weekdaySymbols`).
    public private(set) var weekdays = [TimeInterval](repeating: 0, count: 7)
    /// Les plus lus d'abord. Identifiant vide : documents effacés, regroupés.
    public private(set) var documents: [DocumentTime] = []
    /// Jours consécutifs lus jusqu'à aujourd'hui, ou jusqu'à hier si rien n'a encore été lu aujourd'hui.
    public private(set) var currentStreak = 0
    public private(set) var bestStreak = 0

    public var averagePerActiveDay: TimeInterval { activeDays > 0 ? total / Double(activeDays) : 0 }
    public var averageSession: TimeInterval { sessionCount > 0 ? total / Double(sessionCount) : 0 }

    public init(sessions: [ReadingSession], period: Period, filter: Filter = .everything,
                now: Date = Date(), calendar: Calendar = .current) {
        let kept = sessions.filter { Self.matches($0, filter) }
        computeStreaks(kept, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let firstDay: Date
        switch period {
        case .week: firstDay = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month: firstDay = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .year:
            let month = calendar.dateInterval(of: .month, for: today)?.start ?? today
            firstDay = calendar.date(byAdding: .month, value: -11, to: month) ?? month
        case .all:
            let oldest = kept.map(\.start).min() ?? today
            firstDay = calendar.dateInterval(of: .month, for: oldest)?.start ?? oldest
        }
        bucketsAreMonths = period == .year || period == .all
        let unit: Calendar.Component = bucketsAreMonths ? .month : .day
        var index: [Date: Int] = [:]
        var cursor = firstDay
        while cursor <= today {
            index[cursor] = buckets.count
            buckets.append(Bucket(start: cursor))
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor) else { break }
            cursor = next
        }
        var days = Set<Date>()
        var perDocument: [String: TimeInterval] = [:]
        for session in kept where session.start >= firstDay && session.start <= now {
            let seconds = TimeInterval(session.seconds)
            let day = calendar.startOfDay(for: session.start)
            days.insert(day)
            total += seconds
            sessionCount += 1
            longestSession = max(longestSession, seconds)
            pages += session.pages ?? 0
            lookups += session.lookups ?? 0
            hours[calendar.component(.hour, from: session.start)] += seconds
            weekdays[calendar.component(.weekday, from: session.start) - 1] += seconds
            perDocument[session.documentId, default: 0] += seconds
            let key = bucketsAreMonths ? (calendar.dateInterval(of: .month, for: day)?.start ?? day) : day
            if let position = index[key] {
                if session.scope == .manga { buckets[position].manga += seconds } else { buckets[position].study += seconds }
            }
        }
        activeDays = days.count
        documents = perDocument.map { DocumentTime(documentId: $0.key, seconds: $0.value) }
            .sorted { ($0.seconds, $1.documentId) > ($1.seconds, $0.documentId) }
    }

    private static func matches(_ session: ReadingSession, _ filter: Filter) -> Bool {
        switch filter {
        case .everything: return true
        case .manga: return session.scope == .manga
        case .study: return session.scope != .manga
        }
    }

    private mutating func computeStreaks(_ sessions: [ReadingSession], now: Date, calendar: Calendar) {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.start) })
        var run = 0
        var previous: Date?
        for day in days.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day { run += 1 } else { run = 1 }
            bestStreak = max(bestStreak, run)
            previous = day
        }
        let today = calendar.startOfDay(for: now)
        var cursor = days.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while days.contains(cursor) {
            currentStreak += 1
            guard let before = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = before
        }
    }
}
