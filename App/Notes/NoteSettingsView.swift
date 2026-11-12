// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Réglages de rangement d'**une** note (PLAN-T4-001, étape E3 ; plan approuvé par NOxygen59 le 11/11/2026, DEC-T4-09 A) :
/// échéance (calendrier), priorité, classeur, étiquettes (créées à la volée), archiver.
///
/// Ouvert depuis la fenêtre de la note (lecteur) et depuis l'écran « Notes » (appui long sur une note). Chaque réglage
/// s'enregistre tout de suite (pas de bouton « Enregistrer » à oublier), par `AppDatabase.apply`, qui n'écrit que les
/// colonnes de rangement : le texte et le dessin de la note ne peuvent pas être touchés d'ici.
///
/// Écritures et lectures hors du fil principal ; après chaque écriture, l'état est relu en base (ce qui est affiché est
/// ce qui est enregistré) et `onChange` prévient l'appelant (écran Notes à relire, pastille de l'accueil).
/// Revue DeepSeek D-07 (F2, F3) : **une écriture à la fois** ; pendant l'écriture et la relecture, les réglages sont
/// figés (`busy`) : un second appui rapide ne part jamais d'un état périmé, l'ordre des gestes est l'ordre en base.
struct NoteSettingsView: View {
    let database: AppDatabase
    let noteId: String
    /// Appelé après chaque écriture réussie.
    var onChange: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var organization: NoteOrganization?
    @State private var folders: [NoteFolder] = []
    @State private var tags: [NoteTag] = []
    @State private var error: String?
    @State private var newTagName = ""
    @State private var newFolderName = ""
    @State private var askingFolderName = false
    /// Écriture ou relecture en cours : réglages figés.
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                if let o = organization {
                    dueSection(o)
                    Section(String(localized: "Priorité")) {
                        Picker(String(localized: "Priorité"), selection: binding(o.priority) { .priority($0) }) {
                            ForEach(NotePriority.allCases.reversed(), id: \.self) { Text(NotesView.title($0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Section(String(localized: "Classeur")) {
                        Picker(String(localized: "Classeur"), selection: binding(o.folderId) { .folder($0) }) {
                            Text("Aucun").tag(String?.none)
                            ForEach(folders) { Text($0.name).tag(String?.some($0.id)) }
                        }
                        Button { askingFolderName = true } label: { Label("Nouveau classeur…", systemImage: "folder.badge.plus") }
                    }
                    tagsSection(o)
                    Section {
                        Button {
                            write(.archived(!o.archived))
                        } label: {
                            Label(o.archived ? String(localized: "Désarchiver") : String(localized: "Archiver"),
                                  systemImage: o.archived ? "tray.and.arrow.up" : "archivebox")
                        }
                    } footer: {
                        Text("Une note archivée sort des listes et de la pastille ; on la retrouve dans « Archivées ».")
                    }
                } else if error == nil {
                    ProgressView()
                }
            }
            .disabled(busy)
            .navigationTitle("Ranger la note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .alert("Nouveau classeur", isPresented: $askingFolderName) {
                TextField("Nom", text: $newFolderName)
                Button("Annuler", role: .cancel) { newFolderName = "" }
                Button("Créer") { createFolder() }
            }
            .task { await reload() }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func dueSection(_ o: NoteOrganization) -> some View {
        Section(String(localized: "Échéance")) {
            Toggle(String(localized: "Avant une date"), isOn: Binding(
                get: { o.dueDay != nil },
                set: { on in write(.due(on ? NoteDay.string(Self.defaultDue()) : nil)) }))
            if let day = o.dueDay, let date = Self.date(day) {
                DatePicker(String(localized: "Avant le"), selection: Binding(
                    get: { date },
                    set: { write(.due(NoteDay.string($0))) }), displayedComponents: .date)
                    .environment(\.calendar, NoteDay.calendar)
            }
        }
    }

    @ViewBuilder
    private func tagsSection(_ o: NoteOrganization) -> some View {
        Section {
            ForEach(tags) { tag in
                let on = o.tagIds.contains(tag.id)
                Button { write(on ? .removeTag(tag.id) : .addTag(tag.id)) } label: {
                    HStack {
                        Text("#" + tag.name).foregroundStyle(Atelier.textPrimary)
                        Spacer()
                        if on { Image(systemName: "checkmark").foregroundStyle(Atelier.Tint.read) }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            HStack {
                TextField(String(localized: "Nouvelle étiquette (ex. Test S46)"), text: $newTagName)
                    .onSubmit(addTag)
                Button("Ajouter", action: addTag)
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Étiquettes")
        } footer: {
            Text("Touche une étiquette pour la mettre ou l'enlever.")
        }
    }

    // MARK: Écritures

    /// Lien vers un réglage : la valeur affichée vient de la base ; la changer écrit puis relit.
    private func binding<T>(_ value: T, _ change: @escaping (T) -> NoteChange) -> Binding<T> {
        Binding(get: { value }, set: { write(change($0)) })
    }

    private func write(_ change: NoteChange) {
        let database = database, id = noteId
        run { try database.apply(change, to: [id]) }
    }

    private func addTag() {
        let name = newTagName, database = database, id = noteId
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        newTagName = ""
        // Étiquette existante (même nom, sans les majuscules) réutilisée, sinon créée — puis posée sur la note, en une
        // transaction (note disparue : rien n'est créé).
        run { try database.addTag(named: name, toNote: id) }
    }

    private func createFolder() {
        let name = newFolderName, database = database, id = noteId
        newFolderName = ""
        run { try database.createNoteFolder(name: name, assigningTo: id) }
    }

    private func run(_ work: @escaping @Sendable () throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            let result = await Task.detached(priority: .userInitiated) { Result { try work() } }.value
            if case .failure(let failure) = result { error = failure.localizedDescription } else { error = nil; onChange() }
            await reload()
        }
    }

    private func reload() async {
        let database = database, id = noteId
        let result = await Task.detached(priority: .userInitiated) {
            Result { (try database.organization(noteId: id), try database.noteFolders(), try database.noteTags()) }
        }.value
        switch result {
        case .success(let (o, f, t)):
            (folders, tags) = (f, t)
            organization = o
            if o == nil { error = String(localized: "Cette note n'existe plus.") }
        case .failure(let failure):
            error = failure.localizedDescription
        }
    }

    // MARK: Jours

    /// Échéance proposée quand on l'active : dans 7 jours (un test « la semaine suivante », retour terrain T4).
    static func defaultDue(today: Date = Date()) -> Date {
        NoteDay.calendar.date(byAdding: .day, value: 7, to: today) ?? today
    }

    /// Date de midi du jour « AAAA-MM-JJ » (midi : aucun changement d'heure ne fait glisser le jour).
    static func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return NoteDay.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
