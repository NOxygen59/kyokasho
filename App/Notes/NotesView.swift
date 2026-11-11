// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Écran « Notes » de l'accueil (PLAN-T4-001, étape E2 ; plan approuvé par NOxygen59 le 11/11/2026).
///
/// Toutes les notes de tous les livres, groupées par échéance (En retard, Aujourd'hui, Cette semaine, Plus tard, Sans
/// échéance), avec filtres (classeur, étiquette, priorité, livre, texte) et la vue « Archivées » (DEC-T4-D). Toucher une
/// note ouvre son livre à sa page et fait clignoter son ancre. Les réglages d'une note (échéance, priorité, étiquettes,
/// classeur, archive) arrivent à l'étape E3 : ici, lecture seulement.
///
/// Calcul pur testé : `NoteListing`. Lecture en base hors du fil principal, sans les dessins (`organizedNotes`).
struct NotesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Note choisie : l'appelant ouvre son livre **après** la fermeture de cet écran (`onDismiss`, revue DeepSeek F9).
    var onOpen: (PageComment) -> Void = { _ in }
    @State private var notes: [OrganizedNote] = []
    @State private var loadError: String?
    @State private var folders: [NoteFolder] = []
    @State private var tags: [NoteTag] = []
    @State private var filter = NoteListing.Filter()
    @State private var loaded = false

    private var sections: [NoteListing.Section] {
        NoteListing.sections(notes, filter: filter, today: Date(),
                             documentTitles: Dictionary(model.documents.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a }))
    }

    /// Livres qui ont des notes (filtre « Livre »), par titre.
    private var documentsWithNotes: [LibraryDocument] {
        let ids = Set(notes.map(\.note.documentId))
        return model.documents.filter { ids.contains($0.id) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $filter.archived) {
                        Text("À faire").tag(false)
                        Text("Archivées").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if filter.folderId != nil || filter.tagId != nil || filter.priority != nil || filter.documentId != nil {
                        Button("Retirer les filtres") {
                            filter = NoteListing.Filter(text: filter.text, archived: filter.archived)
                        }
                    }
                }
                if let loadError {
                    // Revue DeepSeek F7 : une lecture en échec n'est jamais présentée comme « aucune note ».
                    Text(String(localized: "Notes illisibles : \(loadError)")).foregroundStyle(.red)
                } else if loaded && sections.isEmpty {
                    Text(emptyText).foregroundStyle(Atelier.textSecondary)
                }
                ForEach(sections, id: \.group) { section in
                    Section(Self.title(section.group)) {
                        ForEach(section.notes) { item in
                            Button { open(item.note) } label: { row(item) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $filter.text, prompt: String(localized: "Chercher dans les notes"))
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
                ToolbarItem(placement: .navigationBarLeading) { filterMenu }
            }
            .task { await reload() }
        }
    }

    private var emptyText: String {
        if filter.isFiltered { return String(localized: "Aucune note ne correspond.") }
        return filter.archived ? String(localized: "Aucune note archivée.")
            : String(localized: "Aucune note pour l'instant. Dans un livre : menu « … » → « Nouvelle note flottante ».")
    }

    private var filterMenu: some View {
        Menu {
            Picker(String(localized: "Classeur"), selection: $filter.folderId) {
                Text("Tous les classeurs").tag(String?.none)
                ForEach(folders) { Text($0.name).tag(String?.some($0.id)) }
            }
            Picker(String(localized: "Étiquette"), selection: $filter.tagId) {
                Text("Toutes les étiquettes").tag(String?.none)
                ForEach(tags) { Text($0.name).tag(String?.some($0.id)) }
            }
            Picker(String(localized: "Priorité"), selection: $filter.priority) {
                Text("Toutes les priorités").tag(NotePriority?.none)
                ForEach(NotePriority.allCases.reversed(), id: \.self) { Text(Self.title($0)).tag(NotePriority?.some($0)) }
            }
            Picker(String(localized: "Livre"), selection: $filter.documentId) {
                Text("Tous les livres").tag(String?.none)
                ForEach(documentsWithNotes) { Text($0.title).tag(String?.some($0.id)) }
            }
        } label: {
            Label("Filtrer", systemImage: filter.isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private func row(_ item: OrganizedNote) -> some View {
        let note = item.note, o = item.organization
        let document = model.documents.first { $0.id == note.documentId }
        let group = NoteListing.group(dueDay: o.dueDay, today: Date())
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: o.priority == .high ? "exclamationmark.circle.fill" : o.priority == .low ? "arrow.down.circle" : "note.text")
                .foregroundStyle(o.priority == .high ? Atelier.Tint.annotate : Atelier.textTertiary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if o.priority != .normal {
                    Text(Self.title(o.priority)).font(Atelier.font(11, weight: .semibold))
                        .foregroundStyle(o.priority == .high ? Atelier.Tint.annotate : Atelier.textTertiary)
                }
                Text(Self.firstLine(note)).font(Atelier.font(16, weight: .semibold)).foregroundStyle(Atelier.textPrimary).lineLimit(2)
                HStack(spacing: 6) {
                    if let document {
                        Text(String(localized: "\(document.title) · p. \(document.pageLabel(note.pageIndex))"))
                            .lineLimit(1)
                    }
                    if let due = o.dueDay {
                        Text(Self.dueLabel(due))
                            .foregroundStyle(group == .overdue ? Color.red : group == .today ? Atelier.Tint.annotate : Atelier.textSecondary)
                    }
                }
                .font(Atelier.font(13)).foregroundStyle(Atelier.textSecondary)
                let labels = labels(for: o)
                if !labels.isEmpty {
                    Text(labels).font(Atelier.font(12, weight: .medium)).foregroundStyle(Atelier.Tint.read).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Classeur puis étiquettes, sur une ligne.
    private func labels(for o: NoteOrganization) -> String {
        var parts: [String] = []
        if let folder = folders.first(where: { $0.id == o.folderId }) { parts.append("▸ " + folder.name) }
        parts += tags.filter { o.tagIds.contains($0.id) }.map { "#" + $0.name }
        return parts.joined(separator: "  ")
    }

    private func open(_ note: PageComment) {
        onOpen(note)
        dismiss()
    }

    private func reload() async {
        let database = model.database, excluded = model.trashedDocumentIds
        let result = await Task.detached(priority: .userInitiated) { () -> Result<([OrganizedNote], [NoteFolder], [NoteTag]), Error> in
            Result { (try database.organizedNotes(includeArchived: true, excludingDocuments: excluded),
                      try database.noteFolders(), try database.noteTags()) }
        }.value
        switch result {
        case .success(let value):
            (notes, folders, tags) = value
            loadError = nil
        case .failure(let error):
            loadError = error.localizedDescription
        }
        loaded = true
    }

    static func title(_ group: NoteListing.Group) -> String {
        switch group {
        case .overdue: return String(localized: "En retard")
        case .today: return String(localized: "Aujourd'hui")
        case .tomorrow: return String(localized: "Demain")
        case .thisWeek: return String(localized: "Dans les 7 jours")
        case .later: return String(localized: "Plus tard")
        case .noDue: return String(localized: "Sans échéance")
        case .archived: return String(localized: "Archivées")
        }
    }

    static func title(_ priority: NotePriority) -> String {
        switch priority {
        case .high: return String(localized: "Priorité haute")
        case .normal: return String(localized: "Priorité normale")
        case .low: return String(localized: "Priorité basse")
        }
    }

    static func firstLine(_ note: PageComment) -> String {
        let line = note.body.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !line.isEmpty { return line }
        if let anchor = note.anchorText, !anchor.isEmpty { return "« \(anchor) »" }
        return String(localized: "Note sans texte (dessin)")
    }

    /// « avant le 18 nov. » à partir du jour « AAAA-MM-JJ ».
    static func dueLabel(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = NoteDay.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return day }
        return String(localized: "avant le \(date.formatted(.dateTime.day().month(.abbreviated)))")
    }
}

private extension NoteListing.Filter {
    /// Un filtre de contenu (hors vue « Archivées ») est-il posé ?
    var isFiltered: Bool {
        folderId != nil || tagId != nil || priority != nil || documentId != nil
            || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
