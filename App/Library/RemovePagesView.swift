// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Document à modifier, avec la page choisie au départ (bouton de la bande des pages du lecteur).
struct PageEditTarget: Identifiable {
    var id: String { document.id }
    let document: LibraryDocument
    let page: Int?
}

/// Bibliothèque → appui long → « Supprimer des pages… », ou bande des pages du lecteur → corbeille (#49).
/// Choisir des pages (une à une ou « de … à … »), les supprimer après confirmation, les restaurer pendant 30 jours,
/// voir l'historique des modifications des pages. Le document est fermé pendant l'opération (`PageShift`) : le
/// lecteur ne peut pas écrire sur l'ancienne numérotation (revue Codex R6).
struct RemovePagesView: View {
    let target: PageEditTarget
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var document: LibraryDocument
    @State private var selected: Set<Int>
    @State private var from = ""
    @State private var to = ""
    @State private var edits: [AppDatabase.PageEdit] = []
    @State private var confirming = false
    @State private var restoring: AppDatabase.PageEdit?
    @State private var discarding: AppDatabase.PageEdit?
    @State private var discardingAll = false
    @State private var copiesSize: Int64 = 0
    @State private var working = false
    @State private var message: String?
    @State private var error: String?

    init(target: PageEditTarget) {
        self.target = target
        _document = State(initialValue: target.document)
        _selected = State(initialValue: target.page.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack {
            List {
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                Section {
                    HStack {
                        Text("De la page")
                        TextField("1", text: $from).keyboardType(.numberPad).frame(width: 60).textFieldStyle(.roundedBorder)
                        Text("à")
                        TextField("1", text: $to).keyboardType(.numberPad).frame(width: 60).textFieldStyle(.roundedBorder)
                        Spacer()
                        Button("Sélectionner") { selectRange() }.disabled(from.isEmpty)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                        ForEach(0..<document.pageCount, id: \.self) { page in
                            PageChoice(document: document, page: page, selected: selected.contains(page)) {
                                if selected.contains(page) { selected.remove(page) } else { selected.insert(page) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .id(edits.count) // Après une modification : miniatures relues (même index, autre page).
                } header: {
                    Text("Pages à supprimer")
                } footer: {
                    Text("Les numéros sont ceux affichés dans le lecteur. Les pages supprimées restent restaurables pendant 30 jours, avec leurs notes, dessins et analyses ; ensuite elles sont effacées. Les cartes de révision sont gardées.")
                }
                let restorable = edits.filter { $0.kind == .removal && $0.restoredBy == nil && $0.purgedAt == nil }
                if !restorable.isEmpty {
                    Section("Pages supprimées, restaurables") {
                        ForEach(restorable.reversed(), id: \.id) { edit in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary(edit)).font(.subheadline.weight(.semibold))
                                    Text("Supprimées le \(edit.appliedAt.formatted(date: .abbreviated, time: .shortened)) · effacées vers le \(edit.appliedAt.addingTimeInterval(PageShift.retention).formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Effacer", role: .destructive) { discarding = edit }
                                    .buttonStyle(.borderless).disabled(working)
                                Button("Restaurer") { restoring = edit }
                                    .buttonStyle(.borderless).disabled(working)
                            }
                        }
                    }
                }
                if !edits.isEmpty {
                    Section("Modifications des pages") {
                        ForEach(edits.reversed(), id: \.id) { edit in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary(edit)).font(.subheadline)
                                Text(state(edit)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    LabeledContent("Place des copies", value: ByteCountFormatter.string(fromByteCount: copiesSize, countStyle: .file))
                    Button("Effacer toutes les copies", role: .destructive) { discardingAll = true }
                        .disabled(copiesSize == 0 || working)
                } footer: {
                    Text("Copies complètes du document gardées 30 jours après chaque ajout ou suppression de pages, puis effacées au lancement suivant. Une restauration efface tout de suite les copies devenues inutiles. Une sauvegarde faite entre-temps garde sa propre copie.")
                }
            }
            .navigationTitle("Pages de « \(document.title) »")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(working) }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) { confirming = true } label: {
                        Label("Supprimer (\(selected.count))", systemImage: "trash")
                    }
                    .disabled(selected.isEmpty || selected.count >= document.pageCount || working)
                }
            }
            .overlay {
                if working {
                    ProgressView("Modification des pages…").padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .alert("Supprimer \(selected.count == 1 ? "cette page" : "ces \(selected.count) pages") ?", isPresented: $confirming) {
                Button("Annuler", role: .cancel) {}
                Button("Supprimer", role: .destructive) { remove() }
            } message: {
                Text("Pages \(labels(selected.sorted())). Elles seront retirées du document. Pendant 30 jours, tu pourras les restaurer avec leurs notes, dessins et analyses ; ensuite elles seront effacées. Les cartes de révision sont gardées.")
            }
            .alert("Restaurer ces pages ?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
                Button("Annuler", role: .cancel) {}
                Button("Restaurer") { if let edit = restoring { restore(edit) } }
            } message: {
                Text("\(restoring.map(summary) ?? "") reviennent à leur place, avec leurs notes, dessins et analyses. Ce que tu as fait depuis est gardé.")
            }
            .alert("Effacer définitivement ces pages ?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } })) {
                Button("Annuler", role: .cancel) {}
                Button("Effacer", role: .destructive) { if let edit = discarding { discard(edit) } }
            } message: {
                Text("\(discarding.map(summary) ?? "") : elles ne pourront plus être restaurées. Leurs cartes de révision sont gardées, sans page.")
            }
            .alert("Effacer toutes les copies ?", isPresented: $discardingAll) {
                Button("Annuler", role: .cancel) {}
                Button("Effacer", role: .destructive) { discardAll() }
            } message: {
                Text("Les pages supprimées de ce document ne pourront plus être restaurées. Le document actuel, ses notes et ses cartes ne changent pas.")
            }
            .interactiveDismissDisabled(working)
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        if let fresh = try? model.database.document(id: document.id) { document = fresh }
        edits = (try? model.database.pageEdits(documentId: document.id)) ?? []
        selected = selected.filter { $0 < document.pageCount }
        copiesSize = PageShift.copiesSize(documentId: document.id)
    }

    /// « De … à … » en numéros affichés (numéros imprimés si le document en a).
    private func selectRange() {
        guard let a = Int(from) else { return }
        let b = Int(to) ?? a
        let first = document.sourceIndex(forPrintedPage: min(a, b)), last = document.sourceIndex(forPrintedPage: max(a, b))
        selected.formUnion(first...max(first, last))
    }

    private func labels(_ pages: [Int]) -> String {
        let shown = pages.prefix(12).map(document.pageLabel).joined(separator: ", ")
        return pages.count > 12 ? shown + "…" : shown
    }

    /// Pages d'une opération, avec les numéros affichés **au moment de l'action** (gardés dans l'archive).
    private func summary(_ edit: AppDatabase.PageEdit) -> String {
        switch edit.kind {
        case .insertion:
            let count = edit.mapping.inserted.count
            return "Ajout de \(count) page\(count > 1 ? "s" : "")"
        case .restoration:
            let count = edit.mapping.inserted.count
            return "Restauration de \(count) page\(count > 1 ? "s" : "")"
        case .removal:
            let count = edit.mapping.removed.count
            let identities = ((try? model.database.archivedRows(editId: edit.id)) ?? []).filter { $0.tableName == "pageIdentity" }
            let numbers: [String] = edit.removedPageIds.compactMap { id in
                guard let row = identities.first(where: { $0.pageId == id }) else { return nil }
                if case .integer(let n)? = row.columns["printedNumber"] { return String(n) }
                if case .integer(let p)? = row.columns["position"] { return "(\(p + 1))" }
                return nil
            }
            let pages = numbers.count == count ? " : p. " + numbers.prefix(12).joined(separator: ", ") + (count > 12 ? "…" : "") : ""
            return "Suppression de \(count) page\(count > 1 ? "s" : "")\(pages)"
        }
    }

    private func state(_ edit: AppDatabase.PageEdit) -> String {
        let date = edit.appliedAt.formatted(date: .abbreviated, time: .shortened)
        guard edit.kind == .removal else { return date }
        if edit.restoredBy != nil { return date + " · restaurées" }
        if edit.purgedAt != nil { return date + " · effacées" }
        return date + " · restaurables"
    }

    private func remove() {
        let pages = selected
        run(success: "\(pages.count) page\(pages.count > 1 ? "s" : "") supprimée\(pages.count > 1 ? "s" : ""). Restaurable\(pages.count > 1 ? "s" : "") pendant 30 jours.") {
            try await PageShift.removePages(model, document: document, pages: pages)
        }
    }

    private func restore(_ edit: AppDatabase.PageEdit) {
        run(success: "Pages restaurées.") {
            try await PageShift.restorePages(model, document: document, archiveId: edit.id)
        }
    }

    private func discard(_ edit: AppDatabase.PageEdit) {
        run(success: "Pages effacées.") {
            try PageShift.discardCopy(model, editId: edit.id, documentId: document.id)
        }
    }

    private func discardAll() {
        run(success: "Copies effacées.") {
            try PageShift.discardCopies(model, documentId: document.id)
        }
    }

    private func run(success: String, _ work: @escaping () async throws -> Void) {
        working = true
        error = nil
        message = nil
        Task {
            do {
                try await work()
                message = success
                selected = []
            } catch {
                self.error = error.localizedDescription
            }
            model.refreshPrintedNumbers()
            reload()
            working = false
        }
    }
}

/// Miniature d'une page avec sa case à cocher.
private struct PageChoice: View {
    let document: LibraryDocument
    let page: Int
    let selected: Bool
    let toggle: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var image: UIImage?

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image { Image(uiImage: image).resizable().scaledToFit() } else { Color.secondary.opacity(0.15) }
                    }
                    .frame(width: 84, height: 112)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? Color.red : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1))
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.red : Color.secondary)
                        .background(Circle().fill(.background))
                        .padding(4)
                }
                Text(document.pageLabel(page)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(document.pageLabel(page))\(selected ? ", choisie" : "")")
        .onAppear {
            model.thumbnails.thumbnail(documentId: document.id, fileURL: model.storage.url(for: document.id),
                                       page: page, width: 168) { image = $0 }
        }
    }
}
