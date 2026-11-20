// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Diff des rappels de notes à partir d'instantanés complets, sans effet de bord.
public struct NoteReminderPlan: Equatable, Sendable {
    public static let prefix = "note-"
    public static let limit = 60

    public struct Content: Equatable, Sendable {
        public let title: String
        public let body: String
        public let noteId: String
        public let documentId: String

        public init(title: String, body: String, noteId: String, documentId: String) {
            self.title = title
            self.body = body
            self.noteId = noteId
            self.documentId = documentId
        }
    }

    /// Composantes du déclencheur mural, pas la prochaine date calculée par le système.
    public struct Trigger: Equatable, Sendable {
        public let components: DateComponents
        public let repeats: Bool

        public init(components: DateComponents, repeats: Bool) {
            self.components = components
            self.repeats = repeats
        }
    }

    public struct Reminder: Equatable, Sendable {
        public let id: String
        public let content: Content
        public let trigger: Trigger
    }

    public struct PendingReminder: Equatable, Sendable {
        public let id: String
        public let content: Content?
        public let trigger: Trigger?

        /// `nil` signale un contenu ou un déclencheur incompatible, sans perdre son identifiant.
        public init(id: String, content: Content?, trigger: Trigger?) {
            self.id = id
            self.content = content
            self.trigger = trigger
        }
    }

    public enum Update: Equatable, Sendable {
        case add(Reminder)
        case replace(Reminder)
    }

    /// Ajouts et remplacements, ensemble du plus proche au plus lointain.
    public let updates: [Update]
    public let removals: [String]

    /// L'appelant filtre les documents exclus et fournit un instantané fiable de la bibliothèque.
    /// `pageLabel` (document, index physique à partir de zéro) et `makeTitle` sont des projections pures.
    /// La localisation reste à l'appelant ; `makeTitle` reçoit le titre du livre et le libellé résolu.
    public static func make(
        _ notes: [OrganizedNote], titles: [String: String],
        pageLabel: (_ documentId: String, _ pageIndex: Int) -> String?,
        now: Date, pending: [PendingReminder], defaultMinute: Int, defaultReminders: [Int],
        calendar: Calendar, makeTitle: (_ book: String, _ pageLabel: String) -> String, emptyBody: String
    ) -> NoteReminderPlan {
        var candidates: [(date: Date, reminder: Reminder)] = []
        for item in notes where !item.organization.archived {
            let note = item.note
            guard let day = item.organization.dueDay, let book = titles[note.documentId] else { continue }
            let dates = NoteReminder.fireDates(day: day, minute: item.organization.dueMinute,
                                               reminders: item.organization.reminders, now: now,
                                               defaultMinute: defaultMinute, defaultReminders: defaultReminders,
                                               calendar: calendar)
            guard !dates.isEmpty else { continue }
            let label = pageLabel(note.documentId, note.pageIndex).flatMap { $0.isEmpty ? nil : $0 }
                ?? String(note.pageIndex + 1)
            let text = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = Content(title: makeTitle(book, label), body: text.isEmpty ? emptyBody : String(text.prefix(150)),
                                  noteId: note.id, documentId: note.documentId)
            for date in dates {
                let id = "\(prefix)\(note.id)-\(Int(date.timeIntervalSince1970))"
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                candidates.append((date, Reminder(id: id, content: content,
                                                  trigger: Trigger(components: components, repeats: false))))
            }
        }
        let desired = candidates.sorted { $0.date < $1.date }.prefix(limit).map(\.reminder)
        let desiredIds = Set(desired.map(\.id))
        let old = Dictionary(pending.filter { $0.id.hasPrefix(prefix) }.map { ($0.id, $0) },
                             uniquingKeysWith: { first, _ in first })
        let updates = desired.compactMap { reminder -> Update? in
            guard let existing = old[reminder.id] else { return .add(reminder) }
            return existing.content == reminder.content && existing.trigger == reminder.trigger ? nil : .replace(reminder)
        }
        // Un rappel déplacé ou hors plafond n'est plus souhaité, sans toucher aux autres familles.
        let removals = old.keys.filter { !desiredIds.contains($0) }.sorted()
        return NoteReminderPlan(updates: updates, removals: removals)
    }
}
