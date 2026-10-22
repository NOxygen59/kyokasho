// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Bibliothèque « Atelier » : barre latérale (sources, outils) + planche de documents sur fond
/// quadrillé. Pensée pour le paysage ; en portrait la barre latérale se replie en haut.
struct LibraryView: View {
    enum Filter: String, CaseIterable { case all, inProgress, drive }

    @EnvironmentObject private var model: AppModel
    @State private var filter: Filter = .all
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var showDrive = false
    @State private var showBench = false
    @State private var showMerge = false
    @State private var analyzing: LibraryDocument?
    @State private var showDictionary = false
    @State private var renaming: LibraryDocument?
    @EnvironmentObject private var review: ReviewModel
    @EnvironmentObject private var themes: ThemeManager
    @State private var showReview = false
    @State private var settingPageOne: LibraryDocument?
    @State private var pageOneText = ""
    @State private var newTitle = ""
    @State private var deleting: LibraryDocument?
    @State private var search = ""

    private var filtered: [LibraryDocument] {
        var docs = model.documents
        switch filter {
        case .all: break
        case .inProgress: docs = docs.filter { $0.lastPageIndex > 0 && $0.lastPageIndex < $0.pageCount - 1 }
        case .drive: docs = docs.filter { $0.driveFileId != nil }
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { docs = docs.filter { $0.title.localizedCaseInsensitiveContains(query) } }
        return docs
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                GridBackground()
                if landscape {
                    HStack(alignment: .top, spacing: Atelier.gap) {
                        sidebar.frame(width: 248)
                        main
                    }
                    .padding(Atelier.gap)
                } else {
                    VStack(spacing: Atelier.gap) {
                        compactBar
                        main
                    }
                    .padding(Atelier.gap)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if let progress = model.importProgress {
                ImportBanner(progress: progress).padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { urls in model.importFiles(urls) }.ignoresSafeArea()
        }
        .sheet(item: $analyzing) { document in
            DocumentAnalysisSheet(document: document).environmentObject(model).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showMerge) {
            PDFMergeView().environmentObject(model).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(themes).environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showDrive) {
            DriveBrowserView().environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showDictionary) {
            NavigationStack {
                DictionarySearchView(dictionary: model.dictionary, added: model.review.keys) { term in
                    model.review.add(term, sentence: nil, source: nil, image: nil, documentId: nil, page: nil,
                                     dictionary: model.dictionary)
                }
                    .padding(Atelier.gap)
                    .background(GridBackground())
                    .navigationTitle("Dictionnaire")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showDictionary = false } } }
            }
            .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showBench) {
            NavigationStack {
                BenchView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showBench = false } } }
            }
            .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(.dark)
        }
        .alert("Renommer", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titre", text: $newTitle)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") { if let renaming { model.rename(renaming, to: newTitle) } }
        }
        .fullScreenCover(isPresented: $showReview, onDismiss: { review.refresh() }) {
            ReviewScreen().environmentObject(model).environmentObject(review).preferredColorScheme(.dark)
        }
        .onAppear { review.refresh() }
        .alert("Où est la page 1 ?", isPresented: Binding(get: { settingPageOne != nil },
                                                           set: { if !$0 { settingPageOne = nil } })) {
            TextField("Page du PDF", text: $pageOneText).keyboardType(.numberPad)
            Button("Annuler", role: .cancel) {}
            Button("OK") {
                if let settingPageOne, let n = Int(pageOneText) { model.setFirstPage(settingPageOne, pdfPage: n) }
            }
        } message: {
            Text("Numéro de la page du fichier PDF où ton manuel imprime « 1 ». Plus simple : ouvre le livre sur cette page, puis menu ••• → « Cette page est la page 1 ».")
        }
        .alert("Supprimer « \(deleting?.title ?? "") » ?",
               isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) { if let deleting { model.delete(deleting) } }
        } message: {
            Text("Le PDF, ses notes, surlignages, dessins et le texte lu par l'OCR seront effacés de l'iPad.")
        }
    }

    // MARK: Barre latérale

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Text("教").font(.custom("HiraMinProN-W6", size: 26))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(.black.opacity(0.85))
                    .background(Atelier.Tint.japanese, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Kyōkasho").font(Atelier.display(19)).foregroundStyle(Atelier.textPrimary)
                    Text("教科書 · atelier de lecture").font(.system(size: 11)).foregroundStyle(Atelier.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                AtelierLabel("Bibliothèque").padding(.bottom, 4)
                sideRow(.all, icon: "square.grid.2x2", title: "Tous les documents", count: model.documents.count)
                sideRow(.inProgress, icon: "book", title: "En cours",
                        count: model.documents.filter { $0.lastPageIndex > 0 && $0.lastPageIndex < $0.pageCount - 1 }.count)
                sideRow(.drive, icon: "externaldrive.badge.icloud", title: "Depuis Drive",
                        count: model.documents.filter { $0.driveFileId != nil }.count)
            }
            VStack(alignment: .leading, spacing: 4) {
                AtelierLabel("Importer").padding(.bottom, 4)
                actionRow(icon: "folder", title: "Fichiers", tint: Atelier.Tint.cloud) { showPicker = true }
                actionRow(icon: "externaldrive.badge.icloud", title: "Google Drive", tint: Atelier.Tint.cloud) { showDrive = true }
            }
            VStack(alignment: .leading, spacing: 4) {
                AtelierLabel("Outils").padding(.bottom, 4)
                actionRow(icon: "rectangle.stack.badge.play", title: "Révisions", tint: Atelier.Tint.japanese,
                          count: review.counts.total) { showReview = true }
                actionRow(icon: "character.book.closed.ja", title: "Dictionnaire", tint: Atelier.Tint.japanese) { showDictionary = true }
                actionRow(icon: "doc.on.doc", title: "Fusionner des PDF", tint: Atelier.Tint.cloud) { showMerge = true }
                actionRow(icon: "gauge.with.dots.needle.33percent", title: "Banc d'essai OCR", tint: Atelier.Tint.japanese) { showBench = true }
                actionRow(icon: "gearshape", title: "Réglages", tint: Atelier.textSecondary) { showSettings = true }
            }
            Spacer()
            statsCard
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .atelierPanel()
    }

    private func sideRow(_ value: Filter, icon: String, title: String, count: Int) -> some View {
        let on = filter == value
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { filter = value }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 22)
                Text(title)
                Spacer()
                Text("\(count)").font(Atelier.mono).foregroundStyle(on ? Color.black.opacity(0.6) : Atelier.textTertiary)
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 9)
            .foregroundStyle(on ? Color.black.opacity(0.85) : Atelier.textPrimary)
            .background(on ? Atelier.Tint.read : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionRow(icon: String, title: String, tint: Color, count: Int? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 22).foregroundStyle(tint)
                Text(title).foregroundStyle(Atelier.textPrimary)
                Spacer()
                if let count, count > 0 {
                    Text("\(count)").font(Atelier.mono).foregroundStyle(Color.black.opacity(0.8))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(tint, in: Capsule())
                }
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }

    private var statsCard: some View {
        let pages = model.documents.reduce(0) { $0 + $1.pageCount }
        let read = model.documents.reduce(0) { $0 + min($1.lastPageIndex + 1, $1.pageCount) }
        return VStack(alignment: .leading, spacing: 8) {
            AtelierLabel("Progression")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(read)").font(Atelier.display(30)).foregroundStyle(Atelier.textPrimary)
                Text("/ \(pages) pages").font(.system(size: 13)).foregroundStyle(Atelier.textSecondary)
            }
            ProgressView(value: Double(read), total: Double(max(pages, 1))).tint(Atelier.Tint.read)
        }
        .padding(14)
        .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Portrait : barre compacte en haut.
    private var compactBar: some View {
        HStack(spacing: 12) {
            Text("Kyōkasho").font(Atelier.display(22)).foregroundStyle(Atelier.textPrimary)
            Spacer()
            Picker("", selection: $filter) {
                Text("Tous").tag(Filter.all)
                Text("En cours").tag(Filter.inProgress)
                Text("Drive").tag(Filter.drive)
            }
            .pickerStyle(.segmented).frame(width: 260)
            CapsuleButton(icon: "plus", label: "Importer") { showPicker = true }
            CapsuleButton(icon: "externaldrive.badge.icloud", label: "Google Drive") { showDrive = true }
            CapsuleButton(icon: "gearshape", label: "Réglages") { showSettings = true }
        }
        .padding(10)
        .atelierPanel()
    }

    // MARK: Planche

    private var main: some View {
        VStack(alignment: .leading, spacing: Atelier.gap) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    AtelierLabel(filterTitle, tint: Atelier.Tint.read)
                    Text("\(filtered.count) document\(filtered.count > 1 ? "s" : "")")
                        .font(Atelier.display(32)).foregroundStyle(Atelier.textPrimary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Atelier.textTertiary)
                    TextField("Rechercher", text: $search).foregroundStyle(Atelier.textPrimary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(width: 280)
                .atelierPanel(radius: 22)
                Button { showPicker = true } label: { Label("Importer", systemImage: "plus") }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.cloud))
            }
            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 22)], spacing: 26) {
                        ForEach(filtered) { document in
                            Button { model.openDocumentId = document.id } label: { DocumentCard(document: document) }
                                .buttonStyle(PressScale())
                                .contextMenu { menu(for: document) }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private var filterTitle: String {
        switch filter {
        case .all: return "Tous les documents"
        case .inProgress: return "En cours"
        case .drive: return "Depuis Google Drive"
        }
    }

    @ViewBuilder
    private func menu(for document: LibraryDocument) -> some View {
        Button { model.openDocumentId = document.id } label: { Label("Ouvrir", systemImage: "book") }
        Button {
            newTitle = document.title
            renaming = document
        } label: { Label("Renommer", systemImage: "pencil") }
        Button {
            pageOneText = String(document.firstPageIndex + 1)
            settingPageOne = document
        } label: { Label("Définir la page 1…", systemImage: "1.circle") }
        Button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { analyzing = document }
        } label: {
            if let r = DocumentAnalysisService.shared.report(for: document.id), !r.pages.isEmpty {
                Label("Analyse : fiabilité \(Int(r.reliability * 100)) %", systemImage: "checkmark.seal")
            } else {
                Label("Analyser le document entier", systemImage: "checkmark.seal")
            }
        }
        Button(role: .destructive) {
            // Le menu d'appui long doit finir de se fermer, sinon iOS ignore la fenêtre de confirmation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { deleting = document }
        } label: { Label("Supprimer", systemImage: "trash") }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("教").font(.custom("HiraMinProN-W6", size: 64)).foregroundStyle(Atelier.Tint.japanese.opacity(0.8))
            Text(filter == .all ? "Ta bibliothèque est vide" : "Rien ici pour l'instant")
                .font(Atelier.display(24)).foregroundStyle(Atelier.textPrimary)
            Text("Importe un cours ou un manuel en PDF, depuis Fichiers ou Google Drive.")
                .foregroundStyle(Atelier.textSecondary)
            HStack(spacing: 12) {
                Button { showPicker = true } label: { Label("Fichiers", systemImage: "folder") }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.cloud))
                Button { showDrive = true } label: { Label("Google Drive", systemImage: "externaldrive.badge.icloud") }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Carte de document : couverture, titre, progression façon cartouche de plan.
struct DocumentCard: View {
    @EnvironmentObject private var model: AppModel
    let document: LibraryDocument
    @State private var image: UIImage?

    private var progress: Double {
        Double(min(document.lastPageIndex + 1, document.pageCount)) / Double(max(document.pageCount, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                // Le cadre fixe la taille ; la page entière est posée dedans, centrée, jamais coupée.
                // (Avant : `scaledToFill` dans le ZStack faisait déborder l'image hors de la case.)
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Atelier.surfaceHigh)
                .aspectRatio(0.72, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView().tint(Atelier.textTertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Atelier.hairline))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
                if document.driveFileId != nil {
                    Image(systemName: "externaldrive.badge.icloud")
                        .font(.system(size: 12, weight: .bold))
                        .padding(7)
                        .foregroundStyle(.black.opacity(0.8))
                        .background(Atelier.Tint.cloud, in: Circle())
                        .padding(8)
                }
            }
            Text(document.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                .foregroundStyle(Atelier.textPrimary)
            HStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Atelier.surfaceHigh)
                        Capsule().fill(Atelier.Tint.read).frame(width: max(4, g.size.width * progress))
                    }
                }
                .frame(height: 4)
                Text("\(document.pageLabel(document.lastPageIndex))/\(document.pageLabel(document.pageCount - 1))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Atelier.textTertiary)
            }
        }
        .onAppear(perform: load)
        .onChange(of: document.id) { _ in load() }
    }

    private func load() {
        if let cached = model.thumbnails.cached(documentId: document.id, page: 0, width: 400) {
            image = cached
            return
        }
        model.thumbnails.thumbnail(documentId: document.id, fileURL: model.storage.url(for: document.id),
                                   page: 0, width: 400) { image = $0 }
    }
}

struct ImportBanner: View {
    let progress: AppModel.ImportProgress

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Atelier.Tint.cloud)
            VStack(alignment: .leading) {
                Text("Import \(progress.done + 1) / \(progress.total)").font(.subheadline.bold())
                Text(progress.currentName).font(.caption).foregroundStyle(Atelier.textSecondary).lineLimit(1)
            }
        }
        .foregroundStyle(Atelier.textPrimary)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .atelierPanel(radius: 24)
    }
}
