// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Écran « Notes » de l'accueil (PLAN-T4-001, étape E2 ; plan approuvé par NOxygen59 le 11/11/2026).
///
/// Toutes les notes de tous les livres, groupées par échéance (En retard, Aujourd'hui, Cette semaine, Plus tard, Sans
/// échéance), avec filtres (classeur, étiquette, priorité, livre, texte) et la vue « Archivées » (DEC-T4-D). Toucher une
/// note ouvre son livre à sa page et fait clignoter son ancre.
///
/// Étape E3 (DEC-T4-09 A) : appui long sur une note → « Ranger… » (`NoteSettingsView`) ou archiver ; glisser vers la
/// gauche → archiver / désarchiver ; « Choisir » → sélection multiple, puis échéance, priorité, classeur, étiquette ou
/// archive pour toutes les notes choisies d'un coup (`AppDatabase.apply`, tout ou rien).
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
    /// Sélection multiple (E3) : actif quand `selecting`.
    @State private var selecting = false
    @State private var selection = Set<String>()
    /// Note dont on règle le rangement (feuille `NoteSettingsView`).
    @State private var settingsFor: PageComment?
    @State private var choosingDue = false
    @State private var chosenDue = NoteSettingsView.defaultDue()
    @State private var actionError: String?

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
            List(selection: $selection) {
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
                if let actionError {
                    Text(actionError).foregroundStyle(.red)
                }
                ForEach(sections, id: \.group) { section in
                    Section(Self.title(section.group)) {
                        ForEach(section.notes) { item in
                            noteRow(item)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(selecting ? .active : .inactive))
            // Revue DeepSeek D-07 F1 : jamais de note choisie qui n'est plus affichée (filtre, onglet, recherche).
            .onChange(of: filter) { _ in selection.formIntersection(visibleIds) }
            .searchable(text: $filter.text, prompt: String(localized: "Chercher dans les notes"))
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
                ToolbarItem(placement: .navigationBarLeading) { filterMenu }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(selecting ? String(localized: "Terminé") : String(localized: "Choisir")) {
                        selecting.toggle()
                        selection = []
                    }
                    .disabled(!selecting && notes.isEmpty)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if selecting { selectionBar }
                }
            }
            .sheet(item: $settingsFor, onDismiss: { Task { await reload() } }) { note in
                NoteSettingsView(database: model.database, noteId: note.id) { model.refreshNotesToReview() }
            }
            .sheet(isPresented: $choosingDue) { dueSheet }
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

    /// Ligne : toucher ouvre la note (hors sélection) ; appui long et glissement pour la ranger (E3).
    @ViewBuilder
    private func noteRow(_ item: OrganizedNote) -> some View {
        if selecting {
            row(item).tag(item.id)
        } else {
            Button { open(item.note) } label: { row(item) }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { settingsFor = item.note } label: { Label("Ranger…", systemImage: "slider.horizontal.3") }
                    archiveButton([item.id], archived: item.organization.archived)
                }
                .swipeActions(edge: .trailing) {
                    archiveButton([item.id], archived: item.organization.archived).tint(Atelier.Tint.read)
                }
        }
    }

    private func archiveButton(_ ids: [String], archived: Bool) -> some View {
        Button { apply(.archived(!archived), to: ids) } label: {
            Label(archived ? String(localized: "Désarchiver") : String(localized: "Archiver"),
                  systemImage: archived ? "tray.and.arrow.up" : "archivebox")
        }
    }

    // MARK: Sélection multiple (E3)

    /// Barre du bas : réglages appliqués à toutes les notes choisies.
    @ViewBuilder
    private var selectionBar: some View {
        let ids = Array(selection)
        let none = selection.isEmpty
        Menu {
            Button("Aujourd'hui") { apply(.due(NoteDay.string(Date())), to: ids) }
            Button("Demain") { apply(.due(NoteDay.string(NoteDay.calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())), to: ids) }
            Button("Dans 7 jours") { apply(.due(NoteDay.string(NoteSettingsView.defaultDue())), to: ids) }
            Button("Choisir une date…") { choosingDue = true }
            Button("Sans échéance", role: .destructive) { apply(.due(nil), to: ids) }
        } label: { Label("Échéance", systemImage: "calendar") }
        .disabled(none)
        Menu {
            ForEach(NotePriority.allCases.reversed(), id: \.self) { p in
                Button(Self.title(p)) { apply(.priority(p), to: ids) }
            }
        } label: { Label("Priorité", systemImage: "exclamationmark.circle") }
        .disabled(none)
        Menu {
            ForEach(folders) { f in Button(f.name) { apply(.folder(f.id), to: ids) } }
            Button("Aucun classeur") { apply(.folder(nil), to: ids) }
        } label: { Label("Classeur", systemImage: "folder") }
        .disabled(none)
        Menu {
            Section("Ajouter") {
                ForEach(tags) { t in Button("#" + t.name) { apply(.addTag(t.id), to: ids) } }
            }
            Section("Retirer") {
                ForEach(tags) { t in Button("#" + t.name, role: .destructive) { apply(.removeTag(t.id), to: ids) } }
            }
        } label: { Label("Étiquette", systemImage: "tag") }
        .disabled(none)
        Spacer()
        Text(String(localized: "\(selection.count) choisie(s)")).font(Atelier.font(13)).foregroundStyle(Atelier.textSecondary)
        Spacer()
        archiveButton(ids, archived: filter.archived).disabled(none)
    }

    private var visibleIds: Set<String> { Set(sections.flatMap(\.notes).map(\.id)) }

    private var dueSheet: some View {
        NavigationStack {
            DatePicker(String(localized: "Avant le"), selection: $chosenDue, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.calendar, NoteDay.calendar)
                .padding()
                .navigationTitle("Échéance")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { choosingDue = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Appliquer") {
                            apply(.due(NoteDay.string(chosenDue)), to: Array(selection))
                            choosingDue = false
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    /// Écrit hors du fil principal, puis relit l'écran et la pastille. Tout ou rien (une transaction).
    private func apply(_ change: NoteChange, to ids: [String]) {
        guard !ids.isEmpty else { return }
        let database = model.database
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try database.apply(change, to: ids) } }.value
            switch result {
            case .failure(let error): actionError = error.localizedDescription
            case .success: actionError = nil
            }
            // Une note archivée ou désarchivée quitte la vue affichée : la sélection ne garde que ce qui reste visible ;
            // plus rien de choisi après un lot → fin du mode sélection (revue D-07 F16).
            await reload()
            selection.formIntersection(visibleIds)
            if selecting, selection.isEmpty, case .success = result { selecting = false }
            model.refreshNotesToReview()
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
