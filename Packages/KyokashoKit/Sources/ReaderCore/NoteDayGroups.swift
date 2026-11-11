// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Notes de l'onglet Notes regroupées par jour de création, avec leur heure (RET-019, #22).
///
/// `PageComment.createdAt` existe depuis la première version des notes : aucune donnée nouvelle, aucune migration.
/// Les jours vont du plus récent au plus ancien ; dans un jour, les notes gardent l'ordre de création.
public enum NoteDayGroups {
    public struct Group: Equatable, Sendable {
        /// Début du jour (fuseau de l'appareil), sert d'identifiant.
        public var day: Date
        /// « Aujourd'hui », « Hier », « 27 oct. » ou « 27 oct. 2025 » (autre année).
        public var title: String
        public var notes: [PageComment]
    }

    public static func group(_ notes: [PageComment], now: Date = Date(), calendar: Calendar = .current) -> [Group] {
        let byDay = Dictionary(grouping: notes) { calendar.startOfDay(for: $0.createdAt) }
        return byDay.keys.sorted(by: >).map { day in
            Group(day: day, title: title(for: day, now: now, calendar: calendar),
                  notes: byDay[day, default: []].sorted { $0.createdAt < $1.createdAt })
        }
    }

    public static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Aujourd'hui", bundle: .main) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return String(localized: "Hier", bundle: .main)
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return formatter(sameYear ? "d MMM" : "d MMM y", calendar).string(from: day)
    }

    /// Heure discrète à côté d'une note : « 14:32 ».
    public static func time(_ date: Date, calendar: Calendar = .current) -> String {
        formatter("HH:mm", calendar).string(from: date)
    }

    private static func formatter(_ template: String, _ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
