// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PDFKit
import SwiftUI
import UIKit

/// Fusion de PDF, sur l'iPad seulement (PDFKit) : choisir des fichiers, les ranger, fusionner, puis enregistrer
/// dans Fichiers et / ou importer dans la bibliothèque.
// FDR-V14 : réutiliser pour « Ajouter des pages » à un document : fusion + renumérotage des données par page (GRDB, Analysis/*.md).
struct PDFMergeView: View {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let name: String
        let pages: Int
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Item] = []
    @State private var outputName = ""
    @State private var showPicker = false
    @State private var merging = false
    @State private var result: URL?
    @State private var showChoice = false
    @State private var showExporter = false
    @State private var imported = false
    @State private var error: String?

    /// Dossier temporaire de cette fusion (copies choisies + résultat), effacé à la fermeture.
    @State private var folder = FileManager.default.temporaryDirectory.appendingPathComponent("Merge-\(UUID().uuidString)", isDirectory: true)

    private var totalPages: Int { items.reduce(0) { $0 + $1.pages } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if items.isEmpty {
                        Text("Ajoute au moins deux PDF. Range-les en les faisant glisser : ils seront fusionnés de haut en bas.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.richtext").foregroundStyle(Atelier.Tint.cloud)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).lineLimit(1)
                                Text("\(item.pages) page\(item.pages > 1 ? "s" : "")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { remove(item) } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.red)
                                .accessibilityLabel("Retirer \(item.name)")
                        }
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1); result = nil }
                    .onDelete { offsets in offsets.map { items[$0] }.forEach(remove) }
                    Button { showPicker = true } label: { Label("Ajouter des PDF", systemImage: "plus") }
                } header: {
                    Text(items.isEmpty ? "Fichiers" : "Fichiers · \(totalPages) pages en tout")
                }
                Section("Nom du PDF fusionné") {
                    TextField(defaultName, text: $outputName)
                }
                Section {
                    Button { Task { await merge() } } label: {
                        HStack {
                            if merging { ProgressView() }
                            Text(merging ? "Fusion…" : "Fusionner")
                        }
                    }
                    .disabled(items.count < 2 || merging)
                    if let result {
                        Button { showExporter = true } label: { Label("Enregistrer dans Fichiers", systemImage: "folder") }
                        Button { importResult(result) } label: {
                            Label(imported ? "Importé dans la bibliothèque" : "Importer dans Kyōkasho",
                                  systemImage: imported ? "checkmark.circle" : "books.vertical")
                        }
                        .disabled(imported)
                    }
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                    else { Text("Tout se fait sur l'iPad : rien n'est envoyé en ligne.") }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Fusionner des PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .sheet(isPresented: $showPicker) {
                DocumentPicker { urls in add(urls) }.ignoresSafeArea()
            }
            .sheet(isPresented: $showExporter) {
                if let result { DocumentExporter(url: result).ignoresSafeArea() }
            }
            .confirmationDialog("PDF fusionné (\(totalPages) pages)", isPresented: $showChoice, titleVisibility: .visible) {
                Button("Enregistrer dans Fichiers") { showExporter = true }
                Button("Importer dans Kyōkasho") { if let result { importResult(result) } }
                Button("Plus tard", role: .cancel) {}
            }
            .onDisappear { try? FileManager.default.removeItem(at: folder) }
        }
    }

    private var defaultName: String {
        "Fusion — " + (items.first.map { ($0.name as NSString).deletingPathExtension } ?? "PDF")
    }

    /// Copies choisies (le sélecteur donne des copies temporaires) rangées dans le dossier de la fusion.
    private func add(_ urls: [URL]) {
        error = nil
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var refused: [String] = []
        for url in urls {
            let target = folder.appendingPathComponent(UUID().uuidString + ".pdf")
            do { try FileManager.default.moveItem(at: url, to: target) } catch {
                guard (try? FileManager.default.copyItem(at: url, to: target)) != nil else { refused.append(url.lastPathComponent); continue }
            }
            guard let doc = PDFDocument(url: target), !doc.isLocked else {
                refused.append(url.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                continue
            }
            items.append(Item(url: target, name: url.lastPathComponent, pages: doc.pageCount))
        }
        result = nil
        imported = false
        if !refused.isEmpty { error = "Ignorés (illisibles ou protégés par mot de passe) : " + refused.joined(separator: ", ") }
    }

    private func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: item.url)
        result = nil
        imported = false
    }

    private func merge() async {
        merging = true
        error = nil
        imported = false
        defer { merging = false }
        var name = outputName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = defaultName }
        name = name.replacingOccurrences(of: "/", with: "-")
        if !name.lowercased().hasSuffix(".pdf") { name += ".pdf" }
        let target = folder.appendingPathComponent(name)
        let sources = items.map(\.url)
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            let out = PDFDocument()
            for url in sources {
                guard let doc = PDFDocument(url: url) else { return false }
                for i in 0..<doc.pageCount {
                    guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
                    out.insert(page, at: out.pageCount)
                }
            }
            try? FileManager.default.removeItem(at: target)
            return out.pageCount > 0 && out.write(to: target)
        }.value
        if ok {
            result = target
            showChoice = true
        } else {
            error = "La fusion a échoué (un des PDF n'a pas pu être lu)."
        }
    }

    private func importResult(_ url: URL) {
        // Copie : le fichier reste disponible pour « Enregistrer dans Fichiers ».
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { error = "Import impossible."; return }
        model.importFiles([copy], cleanUp: true, openWhenSingle: false)
        imported = true
    }
}

/// « Enregistrer dans Fichiers » : sélecteur d'emplacement d'iOS (copie du fichier).
struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}
