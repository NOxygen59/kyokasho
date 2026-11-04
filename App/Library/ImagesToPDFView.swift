// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PhotosUI
import ReaderCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Images (PNG, JPEG, HEIC) vers PDF, sur l'iPad seulement : choisir des images (Photos ou Fichiers), les ranger,
/// créer le PDF (une page par image, ``ImagePDFLayout``), puis l'importer dans la bibliothèque et / ou l'enregistrer
/// dans Fichiers. Même déroulé que « Fusionner des PDF ».
struct ImagesToPDFView: View {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let name: String
        let thumbnail: UIImage?
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Item] = []
    @State private var outputName = ""
    @State private var showFiles = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var loading = false
    @State private var building = false
    @State private var result: URL?
    @State private var showChoice = false
    @State private var showExporter = false
    @State private var imported = false
    @State private var error: String?

    /// Dossier temporaire de cette conversion (copies des images + PDF), effacé à la fermeture.
    @State private var folder = FileManager.default.temporaryDirectory.appendingPathComponent("Images-\(UUID().uuidString)", isDirectory: true)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if items.isEmpty {
                        Text("Ajoute des images PNG, JPEG ou HEIC. Range-les en les faisant glisser : une page par image, de haut en bas.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Group {
                                if let thumbnail = item.thumbnail {
                                    Image(uiImage: thumbnail).resizable().scaledToFill()
                                } else {
                                    Image(systemName: "photo").foregroundStyle(Atelier.Tint.cloud)
                                }
                            }
                            .frame(width: 36, height: 48).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Atelier.corner(4), style: .continuous))
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Button(role: .destructive) { remove(item) } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.red)
                                .accessibilityLabel("Retirer \(item.name)")
                        }
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1); result = nil }
                    .onDelete { offsets in offsets.map { items[$0] }.forEach(remove) }
                    PhotosPicker(selection: $photos, matching: .images) {
                        Label("Depuis Photos", systemImage: "photo.on.rectangle")
                    }
                    Button { showFiles = true } label: { Label("Depuis Fichiers", systemImage: "folder") }
                    if loading { HStack { ProgressView(); Text("Ajout des images…") } }
                } header: {
                    Text(items.isEmpty ? String(localized: "Images") : String(localized: "Images · \(items.count) page\(items.count > 1 ? "s" : "")"))
                }
                Section("Nom du PDF") {
                    TextField(defaultName, text: $outputName)
                }
                Section {
                    Button { Task { await build() } } label: {
                        HStack {
                            if building { ProgressView() }
                            Text(building ? String(localized: "Création…") : String(localized: "Créer le PDF"))
                        }
                    }
                    .disabled(items.isEmpty || building || loading)
                    if let result {
                        Button { showExporter = true } label: { Label("Enregistrer dans Fichiers", systemImage: "folder") }
                        Button { importResult(result) } label: {
                            Label(imported ? String(localized: "Importé dans la bibliothèque") : String(localized: "Importer dans Kyōkasho"),
                                  systemImage: imported ? "checkmark.circle" : "books.vertical")
                        }
                        .disabled(imported)
                    }
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                    else { Text("Une page par image, à sa forme. Les très grandes photos sont réduites (≈ 300 ppp sur A4, assez pour l'OCR). Tout se fait sur l'iPad : rien n'est envoyé en ligne.") }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Images vers PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .sheet(isPresented: $showFiles) {
                DocumentPicker(types: [.png, .jpeg, .heic, .heif]) { urls in add(urls) }.ignoresSafeArea()
            }
            .sheet(isPresented: $showExporter) {
                if let result { DocumentExporter(url: result).ignoresSafeArea() }
            }
            .confirmationDialog("PDF créé (\(items.count) page\(items.count > 1 ? "s" : ""))", isPresented: $showChoice, titleVisibility: .visible) {
                Button("Enregistrer dans Fichiers") { showExporter = true }
                Button("Importer dans Kyōkasho") { if let result { importResult(result) } }
                Button("Plus tard", role: .cancel) {}
            }
            .onChange(of: photos) { picked in
                guard !picked.isEmpty else { return }
                photos = []
                Task { await addPhotos(picked) }
            }
            .onDisappear { try? FileManager.default.removeItem(at: folder) }
        }
    }

    private var defaultName: String {
        String(localized: "Images — ") + (items.first.map { ($0.name as NSString).deletingPathExtension } ?? "PDF")
    }

    /// Copie dans le dossier de la conversion ; une image illisible est refusée tout de suite.
    private func keep(_ data: Data, name: String, ext: String) -> Item? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(UUID().uuidString + "." + ext)
        guard (try? data.write(to: target)) != nil, let image = UIImage(contentsOfFile: target.path) else {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
        return Item(url: target, name: name, thumbnail: image.preparingThumbnail(of: CGSize(width: 72, height: 96)))
    }

    private func add(_ urls: [URL]) {
        error = nil
        var refused: [String] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let item = keep(data, name: url.lastPathComponent, ext: url.pathExtension.isEmpty ? "img" : url.pathExtension) else {
                refused.append(url.lastPathComponent)
                continue
            }
            items.append(item)
            try? FileManager.default.removeItem(at: url)   // copie temporaire du sélecteur
        }
        changed(refused: refused)
    }

    private func addPhotos(_ picked: [PhotosPickerItem]) async {
        loading = true
        defer { loading = false }
        error = nil
        var refused = 0
        for photo in picked {
            // Données d'origine (HEIC compris), pas une version recompressée.
            guard let data = try? await photo.loadTransferable(type: Data.self),
                  let item = keep(data, name: String(localized: "Photo \(items.count + 1)"), ext: photo.supportedContentTypes.first?.preferredFilenameExtension ?? "img") else {
                refused += 1
                continue
            }
            items.append(item)
        }
        changed(refused: refused > 0 ? ["\(refused) photo(s)"] : [])
    }

    private func changed(refused: [String]) {
        result = nil
        imported = false
        if !refused.isEmpty { error = String(localized: "Ignorées (illisibles) : ") + refused.joined(separator: ", ") }
    }

    private func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: item.url)
        result = nil
        imported = false
    }

    private func build() async {
        building = true
        error = nil
        imported = false
        defer { building = false }
        var name = outputName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = defaultName }
        name = name.replacingOccurrences(of: "/", with: "-")
        if !name.lowercased().hasSuffix(".pdf") { name += ".pdf" }
        let target = folder.appendingPathComponent(name)
        let sources = items.map(\.url)
        let ok = await Task.detached(priority: .userInitiated) { Self.render(sources, to: target) }.value
        if ok {
            result = target
            showChoice = true
        } else {
            error = String(localized: "La création a échoué (une image n'a pas pu être lue).")
        }
    }

    /// Une page par image, une image à la fois (photos de plusieurs dizaines de Mpx : mémoire bornée).
    nonisolated static func render(_ sources: [URL], to target: URL) -> Bool {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        var failed = false
        do {
            try renderer.writePDF(to: target) { context in
                for url in sources {
                    autoreleasepool {
                        guard let image = UIImage(contentsOfFile: url.path) else { failed = true; return }
                        // `size` tient compte de l'orientation (photo prise en portrait).
                        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
                        let kept = ImagePDFLayout.pixelSize(for: pixels)
                        let page = CGRect(origin: .zero, size: ImagePDFLayout.pageSize(for: pixels))
                        let format = UIGraphicsImageRendererFormat()
                        format.scale = 1
                        let reduced = kept == pixels ? image : UIGraphicsImageRenderer(size: kept, format: format).image { _ in
                            image.draw(in: CGRect(origin: .zero, size: kept))
                        }
                        context.beginPage(withBounds: page, pageInfo: [:])
                        reduced.draw(in: page)
                    }
                }
            }
        } catch {
            return false
        }
        return !failed
    }

    private func importResult(_ url: URL) {
        // Copie : le fichier de la fenêtre est effacé à sa fermeture ; l'import travaille sur la sienne.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { error = String(localized: "Import impossible."); return }
        imported = true
        // Fenêtre fermée d'abord, import ensuite : la question « Livre ou manuel ? » s'affiche sur la bibliothèque.
        // Posée pendant que cette fenêtre était ouverte, l'alerte ne pouvait pas paraître et restait en attente,
        // bloquant les suivantes (confirmation de suppression) jusqu'au relancement (recette 1.3.2 (62)).
        let model = model
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            model.importFiles([copy], cleanUp: true, openWhenSingle: false)
        }
    }
}
