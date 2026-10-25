// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import PDFKit
import ReaderCore
import SwiftUI

/// Bibliothèque → appui long → « Ajouter des pages… » : d'autres PDF (la suite du manuel) ajoutés au document, dans
/// l'ordre choisi. Le PDF du document est remplacé par la fusion (même document : notes, OCR, cartes gardés). Ajout
/// à la fin (proposé d'office) : rien à renuméroter. Pages insérées avant : tout ce qui est rangé par numéro de
/// page avance d'autant (`AppDatabase.shiftPages`, `DocumentAnalysisService.shiftPages`).
struct AddPagesView: View {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        /// `nil` : le document actuel.
        let url: URL?
        let name: String
        let pages: Int
    }

    let document: LibraryDocument
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Item] = []
    @State private var showPicker = false
    @State private var working = false
    @State private var done = false
    @State private var error: String?
    /// Copies choisies, effacées à la fermeture.
    @State private var folder = FileManager.default.temporaryDirectory.appendingPathComponent("AddPages-\(UUID().uuidString)", isDirectory: true)

    /// Pages ajoutées avant celles du document.
    private var offset: Int { items.prefix { $0.url != nil }.reduce(0) { $0 + $1.pages } }
    private var added: Int { items.filter { $0.url != nil }.reduce(0) { $0 + $1.pages } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.url == nil ? "book.closed.fill" : "doc.richtext")
                                .foregroundStyle(item.url == nil ? Atelier.Tint.read : Atelier.Tint.cloud)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.url == nil ? "\(item.name) (document actuel)" : item.name).lineLimit(1)
                                Text("\(item.pages) page\(item.pages > 1 ? "s" : "")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.url != nil {
                                Button(role: .destructive) { remove(item) } label: { Image(systemName: "minus.circle.fill") }
                                    .buttonStyle(.plain).foregroundStyle(.red)
                                    .accessibilityLabel("Retirer \(item.name)")
                            }
                        }
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    Button { showPicker = true } label: { Label("Choisir des PDF", systemImage: "plus") }
                } header: {
                    Text("Ordre des pages (glisser pour ranger)")
                } footer: {
                    if offset > 0 {
                        Text("\(offset) page(s) avant celles du document : tes notes, surlignages, textes lus et cartes seront décalés d'autant (rien n'est perdu).")
                    } else {
                        Text("Les pages s'ajoutent à la fin : rien ne bouge dans ce qui existe déjà.")
                    }
                }
                Section {
                    Button { Task { await apply() } } label: {
                        HStack {
                            if working { ProgressView() }
                            Text(done ? "Pages ajoutées" : working ? "Ajout…" : "Ajouter \(added) page\(added > 1 ? "s" : "")")
                        }
                    }
                    .disabled(added == 0 || working || done)
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Ajouter des pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(done ? "OK" : "Fermer") { dismiss() } } }
            .sheet(isPresented: $showPicker) { DocumentPicker { add($0) }.ignoresSafeArea() }
            .onAppear {
                if items.isEmpty { items = [Item(url: nil, name: document.title, pages: document.pageCount)] }
            }
            .onDisappear { try? FileManager.default.removeItem(at: folder) }
        }
    }

    private func add(_ urls: [URL]) {
        error = nil
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var refused: [String] = []
        for url in urls {
            let target = folder.appendingPathComponent(UUID().uuidString + ".pdf")
            do { try FileManager.default.moveItem(at: url, to: target) } catch {
                guard (try? FileManager.default.copyItem(at: url, to: target)) != nil else { refused.append(url.lastPathComponent); continue }
            }
            guard let doc = PDFDocument(url: target), !doc.isLocked, doc.pageCount > 0 else {
                refused.append(url.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                continue
            }
            // Ajout à la fin d'office (cas le plus courant : la suite du manuel).
            items.append(Item(url: target, name: url.lastPathComponent, pages: doc.pageCount))
        }
        if !refused.isEmpty { error = "Ignorés (illisibles ou protégés par mot de passe) : " + refused.joined(separator: ", ") }
    }

    private func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        if let url = item.url { try? FileManager.default.removeItem(at: url) }
    }

    private func apply() async {
        let id = document.id
        // Une lecture IA en cours écrit des fichiers par numéro de page : attendre qu'elle finisse.
        if AITaskCenter.shared.jobs.contains(where: { $0.key.contains(id) })
            || DocumentAnalysisService.shared.progress?.documentId == id {
            error = "Une lecture IA de ce document est en cours : attends qu'elle finisse (ou arrête-la), puis réessaie."
            return
        }
        working = true
        error = nil
        defer { working = false }
        let current = model.storage.url(for: id), offset = offset, expected = document.pageCount
        let sources = items.map { $0.url ?? current }
        let merged = folder.appendingPathComponent("merged.pdf")
        let pageCount = await Task.detached(priority: .userInitiated) { () -> Int? in
            let out = PDFDocument()
            for url in sources {
                guard let doc = PDFDocument(url: url) else { return nil }
                // Le document actuel doit garder toutes ses pages, dans l'ordre (sinon les numéros ne suivent plus).
                if url == current, doc.pageCount != expected { return nil }
                for i in 0..<doc.pageCount {
                    guard let page = doc.page(at: i)?.copy() as? PDFPage else { return nil }
                    out.insert(page, at: out.pageCount)
                }
            }
            try? FileManager.default.removeItem(at: merged)
            return out.pageCount > 0 && out.write(to: merged) ? out.pageCount : nil
        }.value
        guard let pageCount else {
            error = "L'ajout a échoué (un des PDF n'a pas pu être lu). Le document n'a pas changé."
            return
        }
        // La fusion a suspendu le MainActor : une tâche IA a pu démarrer entre-temps.
        guard !AITaskCenter.shared.jobs.contains(where: { $0.key.contains(id) }),
              DocumentAnalysisService.shared.progress?.documentId != id else {
            error = "Une lecture IA a démarré pendant la fusion : attends sa fin, puis réessaie. Le document n'a pas changé."
            return
        }
        do {
            let warnings = try await PageShift.apply(model, document: document, merged: merged, offset: offset, newCount: pageCount)
            if !warnings.isEmpty { error = warnings.joined(separator: "\n") }
        } catch {
            self.error = "L'ajout a été interrompu : \(error.localizedDescription). Une reprise peut être nécessaire avant de continuer."
            return
        }
        // Caches par numéro de page : refaits à la demande.
        model.thumbnails.removeAll(for: id)
        ScanSharpening.removeCache(documentId: id)
        ScanSharpening.clearMemory()
        FuriganaLayer.clearMemory()
        LayoutRegionsCache.shared.clear()
        // Ancien PDF et ses réponses « texte intégré ? » oubliés (hors du fil principal : peut attendre un OCR).
        Task.detached { PDFPool.release(current) }
        done = true
        // Nouvelles pages lues par l'IA (seulement celles pas encore lues).
        if let updated = try? model.database.document(id: id) {
            DocumentScan.start(updated, url: current, ocr: model.ocr)
        }
    }
}
