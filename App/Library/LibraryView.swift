// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var showDrive = false
    @State private var renaming: LibraryDocument?
    @State private var newTitle = ""
    @State private var deleting: LibraryDocument?
    @State private var search = ""

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 24)]

    private var filtered: [LibraryDocument] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.documents }
        return model.documents.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if model.documents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(filtered) { document in
                            Button { model.openDocumentId = document.id } label: {
                                DocumentCard(document: document)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { menu(for: document) }
                        }
                    }
                    .padding(24)
                }
                .searchable(text: $search, prompt: "Rechercher un document")
            }
        }
        .navigationTitle("Bibliothèque")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showDrive = true } label: { Label("Google Drive", systemImage: "externaldrive.badge.icloud") }
                Button { showPicker = true } label: { Label("Importer", systemImage: "plus") }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showSettings = true } label: { Label("Réglages", systemImage: "gearshape") }
            }
        }
        .overlay(alignment: .bottom) {
            if let progress = model.importProgress {
                ImportBanner(progress: progress).padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { urls in model.importFiles(urls) }.ignoresSafeArea()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(model)
        }
        .sheet(isPresented: $showDrive) {
            DriveBrowserView().environmentObject(model)
        }
        .alert("Renommer", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titre", text: $newTitle)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") { if let renaming { model.rename(renaming, to: newTitle) } }
        }
        .confirmationDialog("Supprimer ce document et toutes ses notes ?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { if let deleting { model.delete(deleting) } }
        }
    }

    @ViewBuilder
    private func menu(for document: LibraryDocument) -> some View {
        Button { model.openDocumentId = document.id } label: { Label("Ouvrir", systemImage: "book") }
        Button {
            newTitle = document.title
            renaming = document
        } label: { Label("Renommer", systemImage: "pencil") }
        Button(role: .destructive) { deleting = document } label: { Label("Supprimer", systemImage: "trash") }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Aucun document").font(.title2.bold())
            Text("Importe un PDF depuis Fichiers ou Google Drive.").foregroundStyle(.secondary)
            HStack {
                Button { showPicker = true } label: { Label("Importer depuis Fichiers", systemImage: "folder") }
                    .buttonStyle(.borderedProminent)
                Button { showDrive = true } label: { Label("Google Drive", systemImage: "externaldrive.badge.icloud") }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DocumentCard: View {
    @EnvironmentObject private var model: AppModel
    let document: LibraryDocument
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.16))
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(6)
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(0.72, contentMode: .fit)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

            Text(document.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            HStack {
                Text("Page \(document.lastPageIndex + 1) / \(document.pageCount)")
                Spacer()
                if document.driveFileId != nil { Image(systemName: "externaldrive.badge.icloud") }
            }
            .font(.caption).foregroundStyle(.secondary)
            ProgressView(value: Double(document.lastPageIndex + 1), total: Double(max(document.pageCount, 1)))
                .tint(.accentColor)
        }
        .onAppear(perform: load)
        .onChange(of: document.id) { _ in load() }
    }

    private func load() {
        if let cached = model.thumbnails.cached(documentId: document.id, page: 0, width: 360) {
            image = cached
            return
        }
        model.thumbnails.thumbnail(documentId: document.id, fileURL: model.storage.url(for: document.id),
                                   page: 0, width: 360) { image = $0 }
    }
}

struct ImportBanner: View {
    let progress: AppModel.ImportProgress

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading) {
                Text("Import \(progress.done + 1) / \(progress.total)").font(.subheadline.bold())
                Text(progress.currentName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
    }
}
