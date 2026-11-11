// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Écran « Notes » de l'accueil — PLAN-T4-001, étape E2 (plan approuvé par NOxygen59 le 11/11/2026).
///
/// Décision pure, testée sur Mac : l'écran (`App/Notes/NotesView.swift`) ne fait qu'afficher ce calcul.
/// - Groupes par échéance : En retard, Aujourd'hui, Cette semaine (les 7 jours suivants), Plus tard, Sans échéance.
/// - Dans un groupe : priorité haute d'abord (DEC-T4-07), puis échéance la plus proche, puis note la plus récente.
/// - Filtres cumulables : classeur, étiquette, priorité, livre, texte ; « Archivées » montre seulement les archivées
///   (DEC-T4-D : une note archivée quitte les listes courantes).
public enum NoteListing {
    public enum Group: Int, CaseIterable, Sendable, Comparable {
        case overdue, today, thisWeek, later, noDue

        public static func < (lhs: Group, rhs: Group) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Filter: Equatable, Sendable {
        public var folderId: String?
        public var tagId: String?
        public var priority: NotePriority?
        public var documentId: String?
        public var text = ""
        public var archived = false

        public init(folderId: String? = nil, tagId: String? = nil, priority: NotePriority? = nil,
                    documentId: String? = nil, text: String = "", archived: Bool = false) {
            self.folderId = folderId
            self.tagId = tagId
            self.priority = priority
            self.documentId = documentId
            self.text = text
            self.archived = archived
        }

        /// Un filtre autre que la vue par défaut est-il actif ?
        public var isActive: Bool {
            folderId != nil || tagId != nil || priority != nil || documentId != nil || archived
                || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public struct Section: Equatable, Sendable {
        public var group: Group
        public var notes: [OrganizedNote]
    }

    /// Groupe d'une échéance par rapport à `today` (jours « AAAA-MM-JJ », calendrier grégorien de `NoteDay`).
    public static func group(dueDay: String?, today: Date, calendar: Calendar = NoteDay.calendar) -> Group {
        guard let dueDay, NoteDay.isValid(dueDay) else { return .noDue }
        let todayString = NoteDay.string(today, calendar: calendar)
        if dueDay < todayString { return .overdue }
        if dueDay == todayString { return .today }
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) else { return .later }
        return dueDay <= NoteDay.string(weekEnd, calendar: calendar) ? .thisWeek : .later
    }

    public static func matches(_ item: OrganizedNote, _ filter: Filter) -> Bool {
        let o = item.organization
        guard o.archived == filter.archived else { return false }
        if let folderId = filter.folderId, o.folderId != folderId { return false }
        if let tagId = filter.tagId, !o.tagIds.contains(tagId) { return false }
        if let priority = filter.priority, o.priority != priority { return false }
        if let documentId = filter.documentId, item.note.documentId != documentId { return false }
        let text = filter.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let haystack = item.note.body + " " + (item.note.anchorText ?? "")
            guard haystack.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { return false }
        }
        return true
    }

    /// Sections non vides, dans l'ordre des groupes.
    public static func sections(_ notes: [OrganizedNote], filter: Filter, today: Date,
                                calendar: Calendar = NoteDay.calendar) -> [Section] {
        var byGroup: [Group: [OrganizedNote]] = [:]
        for item in notes where matches(item, filter) {
            byGroup[group(dueDay: item.organization.dueDay, today: today, calendar: calendar), default: []].append(item)
        }
        return Group.allCases.compactMap { group in
            guard let items = byGroup[group], !items.isEmpty else { return nil }
            return Section(group: group, notes: items.sorted(by: order))
        }
    }

    private static func order(_ a: OrganizedNote, _ b: OrganizedNote) -> Bool {
        if a.organization.priority != b.organization.priority { return a.organization.priority > b.organization.priority }
        let dueA = a.organization.dueDay ?? "9999-99-99", dueB = b.organization.dueDay ?? "9999-99-99"
        if dueA != dueB { return dueA < dueB }
        if a.note.createdAt != b.note.createdAt { return a.note.createdAt > b.note.createdAt }
        return a.id < b.id
    }
}
