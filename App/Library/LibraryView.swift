// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import ReaderCore
import SwiftUI

/// Bibliothèque « Atelier » : barre latérale (sources, outils) + planche de documents sur fond
/// quadrillé. Pensée pour le paysage ; en portrait la barre latérale se replie en haut.
struct LibraryView: View {
    enum Filter: String, CaseIterable { case all, inProgress, drive }

    @EnvironmentObject private var model: AppModel
    @State private var filter: Filter = .all
    @State private var showImportOptions = false
    /// Paquet Kyōkasho ouvert et vérifié, en attente d'accord (document déjà présent) ou de résultat.
    @State private var pendingPackage: DocumentPackageService.Pending?
    @State private var packageMessage: String?
    @State private var showSettings = false
    @State private var showDrive = false
    @State private var showBench = false
    @State private var showMerge = false
    @State private var showImagesToPDF = false
    // Moniteur ancré à droite, sous « Sélectionner » et « Importer » (recette 1.3.2 (63), point 15).
    @AppStorage(ResourceMonitor.enabledKey) private var monitorEnabled = false
    @AppStorage(ResourceMonitor.shownKey) private var monitorShown = false
    @AppStorage("monitor.detailed") private var monitorDetailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTrash = false
    @State private var analyzing: LibraryDocument?
    @State private var exporting: LibraryDocument?
    @State private var addingPages: LibraryDocument?
    @State private var editingPages: PageEditTarget?
    @State private var chatDocument: LibraryDocument?
    @State private var showDictionary = false
    @State private var renaming: LibraryDocument?
    @EnvironmentObject private var review: ReviewModel
    @EnvironmentObject private var themes: ThemeManager
    @ObservedObject private var readingTime = ReadingTimeTracker.shared
    @State private var showReview = false
    @State private var settingPageOne: LibraryDocument?
    @State private var pageOneText = ""
    @State private var newTitle = ""
    @State private var deleting: LibraryDocument?
    /// Suppression de plusieurs documents, avec double confirmation (recette 1.3.2 (61)).
    @State private var selecting = false
    @State private var batch = BatchDeletion()
    @State private var showBatchFirst = false
    @State private var showBatchSecond = false
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

    /// Paquet choisi : vérifié d'abord ; nouveau document installé tout de suite, document existant après accord.
    private func openPackage(_ url: URL) {
        Task {
            do {
                let pending = try await model.openPackage(url)
                if pending.exists { pendingPackage = pending } else { install(pending, replacing: false) }
            } catch {
                packageMessage = "Paquet refusé : \(error.localizedDescription)"
            }
        }
    }

    private func install(_ pending: DocumentPackageService.Pending, replacing: Bool) {
        pendingPackage = nil
        Task {
            do {
                let safety = try await model.installPackage(pending, replacing: replacing)
                var text = "« \(pending.contents.manifest.title) » importé avec ses notes, OCR, lectures IA, traductions et analyse."
                if let safety { text += " Ancienne version gardée : Paquets de sécurité/\(safety.deletingLastPathComponent().lastPathComponent)." }
                if !pending.missingDictionaries.isEmpty {
                    text += " Dictionnaires à télécharger (Réglages → Dictionnaires → Catalogue) : " + pending.missingDictionaries.joined(separator: ", ") + "."
                }
                packageMessage = text
            } catch {
                packageMessage = "Import impossible : \(error.localizedDescription)"
            }
        }
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
        // « Livre ou manuel ? » après chaque import (RET-039, #54). Une alerte ne se ferme pas par un toucher à côté :
        // chaque document reçoit une réponse, « Plus tard » compris.
        .alert("Livre ou manuel ?", isPresented: Binding(get: { !model.categoryQuestions.isEmpty }, set: { _ in }),
               presenting: model.categoryQuestions.first) { _ in
            ForEach(DocumentCategory.allCases, id: \.self) { category in
                Button(category.title) { model.answerCategory(category) }
            }
            Button("Plus tard", role: .cancel) { model.answerCategory(nil) }
        } message: { document in
            Text("« \(document.title) » : la catégorie s'affiche sur l'accueil pour t'aider à te repérer. Tu pourras la changer dans « Ce document ».")
        }
        .sheet(isPresented: $showImportOptions) {
            ImportOptionsView(onImport: { urls, language in model.importFiles(urls, language: language) },
                              onPackage: { url in openPackage(url) })
                .preferredColorScheme(AppStyle.current.colorScheme)
        }
        .alert("Remplacer « \(pendingPackage?.contents.manifest.title ?? "") » ?",
               isPresented: Binding(get: { pendingPackage?.exists == true }, set: { if !$0, let p = pendingPackage { model.discardPackage(p); pendingPackage = nil } })) {
            Button("Annuler", role: .cancel) {}
            Button("Remplacer", role: .destructive) { if let p = pendingPackage { install(p, replacing: true) } }
        } message: {
            Text("Ce document est déjà dans ta bibliothèque. Sa version actuelle (notes, OCR, lectures IA…) sera d'abord enregistrée dans Fichiers → Kyōkasho → Paquets de sécurité, puis remplacée par celle du paquet.")
        }
        .alert("Paquet Kyōkasho", isPresented: Binding(get: { packageMessage != nil }, set: { if !$0 { packageMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(packageMessage ?? "") }
        .sheet(item: $analyzing) { document in
            DocumentAnalysisSheet(document: document).environmentObject(model).preferredColorScheme(AppStyle.current.colorScheme)
        }
        .sheet(isPresented: $showMerge) {
            PDFMergeView().environmentObject(model).preferredColorScheme(AppStyle.current.colorScheme)
        }
        .sheet(isPresented: $showImagesToPDF) {
            ImagesToPDFView().environmentObject(model).preferredColorScheme(AppStyle.current.colorScheme)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(themes).environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(AppStyle.current.colorScheme)
        }
        .sheet(isPresented: $showDrive) {
            DriveBrowserView().environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(AppStyle.current.colorScheme)
        }
        .fullScreenCover(isPresented: $showDictionary) {
            NavigationStack {
                DictionarySearchView(dictionary: model.dictionary, added: model.review.keys) { term in
                    model.review.add(term, sentence: nil, source: nil, image: nil, documentId: nil, page: nil,
                                     dictionary: model.dictionary)
                }
                    .navigationTitle("Dictionnaire")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showDictionary = false } } }
            }
            .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(AppStyle.current.colorScheme)
        }
        .sheet(isPresented: $showBench) {
            NavigationStack {
                BenchView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showBench = false } } }
            }
            .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(AppStyle.current.colorScheme)
        }
        .alert("Renommer", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titre", text: $newTitle)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") { if let renaming { model.rename(renaming, to: newTitle) } }
        }
        .fullScreenCover(isPresented: $showReview, onDismiss: { review.refresh() }) {
            ReviewScreen().environmentObject(model).environmentObject(review).preferredColorScheme(AppStyle.current.colorScheme)
        }
        .onAppear { review.refresh() }
        .sheet(item: $addingPages) { document in
            AddPagesView(document: document).environmentObject(model).preferredColorScheme(AppStyle.current.colorScheme)
        }
        .sheet(item: $editingPages) { target in
            RemovePagesView(target: target).environmentObject(model).preferredColorScheme(AppStyle.current.colorScheme)
        }
        .onReceive(model.$pageEditRequest) { request in
            guard let request, let document = model.documents.first(where: { $0.id == request.documentId }) else { return }
            model.pageEditRequest = nil
            // Le lecteur (plein écran) finit de se fermer avant d'ouvrir la fenêtre.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { editingPages = PageEditTarget(document: document, page: request.page) }
        }
        .sheet(item: $chatDocument) { document in
            NavigationStack { QwenChatView(document: document, database: model.database) }
                .environmentObject(model).preferredColorScheme(AppStyle.current.colorScheme)
        }
        .sheet(item: $exporting) { document in
            DocumentExportSheet(document: document)
                .environmentObject(model).environmentObject(model.review).preferredColorScheme(AppStyle.current.colorScheme)
        }
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
        // Double confirmation de la suppression multiple : rien n'est effacé avant « Effacer » (`BatchDeletion`).
        .alert("Supprimer \(batch.selected.count) document\(batch.selected.count > 1 ? "s" : "") ?", isPresented: $showBatchFirst) {
            Button("Annuler", role: .cancel) { batch.cancel() }
            Button("Continuer", role: .destructive) {
                batch.confirmFirst()
                // La première alerte doit finir de se fermer, sinon iOS ignore la seconde.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showBatchSecond = batch.step == .secondConfirmation }
            }
        } message: {
            Text(batchTitles)
        }
        .alert("Mettre à la corbeille ?", isPresented: $showBatchSecond) {
            Button("Annuler", role: .cancel) { batch.cancel() }
            Button("Mettre \(batch.selected.count) à la corbeille", role: .destructive) {
                let ids = batch.confirmSecond(existing: Set(model.documents.map(\.id)))
                for document in model.documents where ids.contains(document.id) { model.moveToTrash(document) }
                selecting = false
            }
        } message: {
            Text("Ces \(batch.selected.count) documents quittent la bibliothèque, avec tout ce qu'ils contiennent. Ils restent 30 jours dans la Corbeille, d'où on peut les restaurer.")
        }
        .alert("Mettre « \(deleting?.title ?? "") » à la corbeille ?",
               isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Annuler", role: .cancel) {}
            Button("Mettre à la corbeille", role: .destructive) { if let deleting { model.moveToTrash(deleting) } }
        } message: {
            Text("Il quitte la bibliothèque mais garde son PDF, ses notes, surlignages, dessins et son texte OCR. Restaurable pendant 30 jours depuis la Corbeille.")
        }
        .sheet(isPresented: $showTrash) { TrashView().environmentObject(model).preferredColorScheme(AppStyle.current.colorScheme) }
    }

    // MARK: Barre latérale

    /// Colonne de gauche. Trop haute pour l'écran (outils ajoutés, carte de l'IA), elle étirait toute la page,
    /// poussait la barre de sélection multiple hors de l'écran et coupait la carte du temps de lecture (recette
    /// 1.3.2 (66)). Les outils défilent quand ils ne tiennent pas ; le temps de lecture reste fixé en bas, entier.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .vertical) {
                sidebarContent
                ScrollView(showsIndicators: false) { sidebarContent }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            statsCard
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .atelierPanel()
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Text("教").font(.custom("HiraMinProN-W6", size: 26))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(Atelier.onAccentInk.opacity(0.85))
                    .background(Atelier.Tint.japanese, in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Kyōkasho").font(Atelier.display(19)).foregroundStyle(Atelier.textPrimary)
                    Text("教科書 · atelier de lecture").font(Atelier.font(11)).foregroundStyle(Atelier.textTertiary)
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
                actionRow(icon: "folder", title: "Fichiers", tint: Atelier.Tint.cloud) { showImportOptions = true }
                actionRow(icon: "externaldrive.badge.icloud", title: "Google Drive", tint: Atelier.Tint.cloud) { showDrive = true }
            }
            VStack(alignment: .leading, spacing: 4) {
                AtelierLabel("Outils").padding(.bottom, 4)
                actionRow(icon: "rectangle.stack.badge.play", title: "Révisions", tint: Atelier.Tint.japanese,
                          count: review.counts.total) { showReview = true }
                actionRow(icon: "character.book.closed.ja", title: "Dictionnaire", tint: Atelier.Tint.japanese,
                          count: model.dictionary.notebook.saved.count) { showDictionary = true }
                actionRow(icon: "doc.on.doc", title: "Fusionner des PDF", tint: Atelier.Tint.cloud) { showMerge = true }
                actionRow(icon: "photo.on.rectangle.angled", title: "Images vers PDF", tint: Atelier.Tint.cloud) { showImagesToPDF = true }
                actionRow(icon: "gauge.with.dots.needle.33percent", title: "Banc d'essai OCR", tint: Atelier.Tint.japanese) { showBench = true }
                actionRow(icon: "trash", title: "Corbeille", tint: Atelier.textSecondary,
                          count: model.trashedDocuments.count) { showTrash = true }
                actionRow(icon: "gearshape", title: "Réglages", tint: Atelier.textSecondary) { showSettings = true }
            }
            // Avertissement de l'IA locale (RET-018) : dans la partie qui défile, au-dessus du temps de lecture fixé.
            LocalAIEnergyCard()
        }
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
                Text("\(count)").font(Atelier.mono).foregroundStyle(on ? Atelier.onAccentInk.opacity(0.6) : Atelier.textTertiary)
            }
            .font(Atelier.font(15, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 9)
            .foregroundStyle(on ? Atelier.onAccentInk.opacity(0.85) : Atelier.textPrimary)
            .background(on ? Atelier.Tint.read : Color.clear, in: RoundedRectangle(cornerRadius: Atelier.corner(10), style: .continuous))
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
                    Text("\(count)").font(Atelier.mono).foregroundStyle(Atelier.onAccentInk.opacity(0.8))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(tint, in: Capsule())
                }
            }
            .font(Atelier.font(15, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }

    /// Temps de lecture active, à la place de « Progression XX/XX pages » (RET-037, #52).
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            AtelierLabel("Temps de lecture")
            Text(ReadingClock.format(readingTime.clock.elapsed(at: Date())))
                .font(Atelier.display(30)).foregroundStyle(Atelier.textPrimary)
            Text("livre ouvert à l'écran").font(Atelier.font(13)).foregroundStyle(Atelier.textSecondary)
        }
        .padding(14)
        .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.corner(14), style: .continuous))
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
            CapsuleButton(icon: "plus", label: "Importer") { showImportOptions = true }
            CapsuleButton(icon: "externaldrive.badge.icloud", label: "Google Drive") { showDrive = true }
            CapsuleButton(icon: "character.book.closed.ja", label: "Dictionnaire") { showDictionary = true }
            CapsuleButton(icon: "gearshape", label: "Réglages") { showSettings = true }
        }
        .padding(10)
        .atelierPanel()
    }

    // MARK: Planche

    private static let monitorWidth: CGFloat = 300

    static func monitorAnimation(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 1)
    }
    private var monitorVisible: Bool { monitorEnabled && monitorShown }

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
                if !model.documents.isEmpty {
                    Button {
                        selecting.toggle()
                        if !selecting { batch = BatchDeletion() }
                    } label: { Label(selecting ? "Terminé" : "Sélectionner", systemImage: selecting ? "checkmark" : "checklist") }
                        .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.annotate))
                }
                Button { showImportOptions = true } label: { Label("Importer", systemImage: "plus") }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.cloud))
            }
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: Atelier.gap) {
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            // Sections « Manuels », « Livres », « Non classés » (recette 1.3.2 (61), E5) : chacune s'allonge
                            // avec ses documents, les suivantes descendent d'autant.
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 22)], spacing: 26) {
                                ForEach(LibrarySections.group(filtered), id: \.title) { section in
                                    Section {
                                        ForEach(section.documents) { document in
                                            Button {
                                                if selecting { batch.toggle(document.id) } else { model.openDocumentId = document.id }
                                            } label: {
                                                DocumentCard(document: document)
                                                    .overlay(alignment: .topTrailing) {
                                                        if selecting { selectionMark(batch.selected.contains(document.id)) }
                                                    }
                                            }
                                            .buttonStyle(PressScale())
                                            .contextMenu { if !selecting { menu(for: document) } }
                                        }
                                    } header: {
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            AtelierLabel(section.title, tint: section.category == .textbook ? Atelier.Tint.read
                                                         : section.category == .book ? Atelier.Tint.annotate : Atelier.textTertiary)
                                            Text("\(section.documents.count)").font(Atelier.mono).foregroundStyle(Atelier.textTertiary)
                                            Spacer()
                                        }
                                        .padding(.top, 8)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        if selecting { selectionBar }
                    }
                }
                // Moniteur déroulé : les documents s'arrêtent avant lui. Replié, il se pose sur le coin sans réserver
                // de colonne.
                .padding(.trailing, monitorVisible && monitorDetailed ? Self.monitorWidth + Atelier.gap : 0)
                // La liste prend sa nouvelle largeur d'un coup : animée, toute la grille se recalculait à chaque image
                // et le défilement saccadait pendant l'animation (recette 1.3.2 (65), point 6). Seul le moniteur s'anime.
                .transaction { $0.animation = nil }
                if monitorVisible {
                    ResourceMonitorPanel(expandsDown: true, fillsWidth: monitorDetailed)
                        .frame(width: monitorDetailed ? Self.monitorWidth : nil)
                        .transition(reduceMotion ? .opacity
                                    : .asymmetric(insertion: .opacity.combined(with: .offset(x: 24)),
                                                  removal: .opacity.combined(with: .offset(x: 24))))
                }
            }
            // Ressort amorti sans rebond, un peu plus long (recette 1.3.2 (64), point 7 : transition trop sèche), pour
            // l'entrée, la sortie et le déroulé du moniteur.
            .animation(Self.monitorAnimation(reduceMotion), value: monitorVisible && monitorDetailed)
            .animation(Self.monitorAnimation(reduceMotion), value: monitorVisible)
        }
        .padding(.horizontal, 6)
    }

    /// Case de sélection sur la couverture.
    private func selectionMark(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(Atelier.font(26, weight: .semibold))
            .foregroundStyle(on ? Atelier.Tint.annotate : Atelier.textPrimary)
            .background(Circle().fill(Atelier.surface.opacity(0.8)))
            .padding(10)
            .accessibilityLabel(on ? "Sélectionné" : "Non sélectionné")
    }

    /// Barre de la sélection : tout sélectionner, supprimer (première des deux confirmations).
    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text("\(batch.selected.count) sélectionné\(batch.selected.count > 1 ? "s" : "")")
                .font(Atelier.font(14, weight: .semibold)).foregroundStyle(Atelier.textSecondary)
            Spacer()
            Button("Tout sélectionner") { batch.selectAll(filtered.map(\.id)) }
                .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
            Button(role: .destructive) {
                batch.requestDeletion()
                showBatchFirst = batch.step == .firstConfirmation
            } label: { Label("Supprimer", systemImage: "trash") }
                .buttonStyle(AtelierButtonStyle(tint: .red))
                .disabled(batch.selected.isEmpty)
        }
        .padding(12)
        .atelierPanel(radius: 18)
    }

    /// Titres des documents choisis (au plus 5), pour les deux questions.
    private var batchTitles: String {
        let titles = model.documents.filter { batch.selected.contains($0.id) }.map(\.title)
        let shown = titles.prefix(5).map { "« \($0) »" }.joined(separator: "\n")
        return titles.count > 5 ? shown + "\n… et \(titles.count - 5) autre\(titles.count - 5 > 1 ? "s" : "")" : shown
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
        if (Qwen3VLReader().isAvailable || ModelStore.shared.isInstalled(.qwen35chat4b)),
           DocumentKnowledge.isReady(document) {
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { chatDocument = document }
            } label: { Label("Discuter du livre", systemImage: "bubble.left.and.bubble.right") }
        } else if Qwen3VLReader().isAvailable || ModelStore.shared.isInstalled(.qwen35chat4b) {
            Label("Chat après lecture OvisOCR2 (\(DocumentKnowledge.readCount(document))/\(document.pageCount))",
                  systemImage: "text.book.closed")
        }
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
        Button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { addingPages = document }
        } label: { Label("Ajouter des pages…", systemImage: "doc.badge.plus") }
        Button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editingPages = PageEditTarget(document: document, page: nil) }
        } label: { Label("Supprimer des pages…", systemImage: "doc.badge.minus") }
        Button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { exporting = document }
        } label: { Label("Exporter…", systemImage: "square.and.arrow.up") }
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
                Button { showImportOptions = true } label: { Label("Fichiers", systemImage: "folder") }
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
                RoundedRectangle(cornerRadius: Atelier.corner(12), style: .continuous).fill(Atelier.surfaceHigh)
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
                .clipShape(RoundedRectangle(cornerRadius: Atelier.corner(12), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Atelier.corner(12), style: .continuous).strokeBorder(Atelier.hairline))
                .atelierShadow(opacity: 0.5, radius: 12, y: 8)
                if let category = document.category {
                    // Repère sur l'accueil (RET-039, #54).
                    Text(category.title).font(Atelier.font(11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundStyle(Atelier.onAccentInk.opacity(0.8))
                        .background(category == .textbook ? Atelier.Tint.read : Atelier.Tint.annotate, in: Capsule())
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if document.driveFileId != nil {
                    Image(systemName: "externaldrive.badge.icloud")
                        .font(Atelier.font(12, weight: .bold))
                        .padding(7)
                        .foregroundStyle(Atelier.onAccentInk.opacity(0.8))
                        .background(Atelier.Tint.cloud, in: Circle())
                        .padding(8)
                }
            }
            Text(document.title).font(Atelier.font(15, weight: .semibold)).lineLimit(2)
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
