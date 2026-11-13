// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import ReaderCore
import SwiftUI
import UIKit

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
    /// Catégorie « Lexique » (PLAN-LEX-001, E2) : Livres & Manuels seulement, comme le dictionnaire.
    @State private var showLexicon = false
    /// Écran « Notes » (PLAN-T4-001, E2).
    @State private var showNotes = false
    @State private var noteToOpen: PageComment?
    @State private var showDashboard = false
    /// Mode propriétaire (PLAN-MODLOC-001, E1) : rafale de touchers sur « Temps de lecture ».
    @AppStorage(OwnerMode.unlockedKey) private var ownerUnlocked = false
    @State private var statsTaps = TapBurst()
    @State private var statsDecision: Task<Void, Never>?
    /// Retour visuel bref de la bascule (revue D-07 MODLOC E1, n°2 : l'iPad n'a pas de vibreur) : cadenas ouvert ou
    /// fermé à la place de l'icône du tableau de bord pendant ~1,2 s, sans texte (DEC-01).
    @State private var ownerFlash: Bool?
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

    /// Espace affiché : Livres & Manuels ou Manga. Simple filtre : il ne réécrit ni document ni progression.
    @AppStorage(LibrarySpace.storageKey) private var space = LibrarySpace.study
    @State private var scrollAnchors: [LibrarySpace: String] = [:]
    @State private var snapshot: UIView?
    @AppStorage(PersonalPadLibrary.compactDocumentsKey) private var compactDocuments = true
    private var usesCompactDocuments: Bool { PersonalPadLibrary.isAvailable && compactDocuments }
    @State private var convertingComics: [LibraryDocument] = []
    @State private var showConvertConfirmation = false
    /// Dossier ouvert sur l'accueil (PLAN-T5-001, E2) ; `nil` : accueil complet. Remis à `nil` au changement d'espace.
    @State private var openFolderId: String?
    /// Transition d'entrée et de sortie d'un dossier (recette 1.5.8) : 0 au changement, puis 1 en ressort.
    @State private var folderProgress: CGFloat = 1
    @State private var folderEntering = true
    /// Fenêtre « nom du dossier » : création (avec documents à ranger) ou renommage.
    @State private var folderNaming: FolderNaming?
    @State private var folderName = ""
    @State private var deletingFolder: LibraryFolder?
    /// « Cartes de ce document » (PLAN-CARTES-001, E1).
    @State private var cardsDocument: LibraryDocument?
    @State private var exportAfterCards: LibraryDocument?

    private var spaceDocuments: [LibraryDocument] {
        model.documents.filter { $0.isInMangaSpace == (space == .manga) }
    }

    /// Livres et Manuels : sections par catégorie. Manga : « Manga » (PDF) puis « CBZ » (demande de NOxygen59, 07/11/2026).
    /// Filtre autre que « Tous » ou recherche en cours : les dossiers sans document filtré sont masqués (DEC-T5-09).
    private var isFiltering: Bool {
        filter != .all || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Dossiers en tête et documents hors dossier (PLAN-T5-001, E2 ; calcul pur testé : `LibraryFolderLayout`).
    private var folderLayout: LibraryFolderLayout.Result {
        LibraryFolderLayout.layout(documents: filtered, folders: model.folders, space: space, filtering: isFiltering)
    }

    /// Dossier ouvert, s'il existe encore dans l'espace affiché (supprimé ailleurs : retour à l'accueil complet).
    private var currentFolder: LibraryFolder? {
        guard let openFolderId else { return nil }
        return model.folders.folders(in: space.rawValue).first { $0.id == openFolderId }
    }

    /// Documents du dossier ouvert qui passent le filtre.
    private var currentFolderDocuments: [LibraryDocument] {
        guard let currentFolder else { return [] }
        return folderLayout.tiles.first { $0.folder.id == currentFolder.id }?.documents ?? []
    }

    /// Sections habituelles, pour les seuls documents hors dossier.
    private var sections: [LibrarySections.Section] {
        let loose = folderLayout.loose
        guard space == .manga else { return LibrarySections.group(loose) }
        return LibrarySections.groupManga(loose)
    }

    /// Documents affichés (« Tout sélectionner » ne prend que ceux-là). Revue DeepSeek n°1 : à l'accueil, les
    /// documents rangés dans un dossier ne sont pas affichés, donc jamais sélectionnés en bloc sans être vus.
    private var visibleDocuments: [LibraryDocument] {
        currentFolder != nil ? currentFolderDocuments : folderLayout.loose
    }

    private var selectedComics: [LibraryDocument] {
        batch.order.compactMap { id in model.documents.first { $0.id == id && $0.isComicArchive } }
    }

    private var conversionSizeText: String {
        ByteCountFormatter.string(fromByteCount: convertingComics.reduce(0) { $0 + $1.fileSize }, countStyle: .file)
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = model.notice {
            Text(ui: notice).font(Atelier.font(14, weight: .medium)).foregroundStyle(Atelier.textPrimary)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Atelier.material(.regularMaterial), in: Capsule())
                .atelierShapeShadow(Capsule(), opacity: 0.3, radius: 12, y: 4)
                .padding(.top, 12)
                .transition(.opacity)
        }
    }

    private var spaceTitle: String { space == .manga ? "Aidoku (2)" : "Kyōkasho" }

    private var filtered: [LibraryDocument] {
        var docs = spaceDocuments
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
                packageMessage = String(localized: "Paquet refusé : \(error.localizedDescription)")
            }
            // Copie déposée par iOS dans Inbox (« Ouvrir dans ») : à nous, effacée une fois lue. Un fichier ouvert
            // sur place depuis Fichiers n'est jamais touché.
            if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Paquet touché dans Fichiers (`AppModel.incomingPackage`), au lancement comme app ouverte.
    private func takeIncomingPackage() {
        guard let url = model.incomingPackage else { return }
        model.incomingPackage = nil
        openPackage(url)
    }

    private func install(_ pending: DocumentPackageService.Pending, replacing: Bool) {
        pendingPackage = nil
        Task {
            do {
                let safety = try await model.installPackage(pending, replacing: replacing)
                var text = String(localized: "« \(pending.contents.manifest.title) » importé avec ses notes, OCR, lectures IA, traductions et analyse.")
                if let safety { text += String(localized: " Ancienne version gardée : Paquets de sécurité/\(safety.deletingLastPathComponent().lastPathComponent).") }
                if !pending.missingDictionaries.isEmpty {
                    text += String(localized: " Dictionnaires à télécharger (Réglages → Dictionnaires → Catalogue) : ") + pending.missingDictionaries.joined(separator: ", ") + "."
                }
                packageMessage = text
            } catch {
                packageMessage = String(localized: "Import impossible : \(error.localizedDescription)")
            }
        }
    }

    var body: some View {
        // Hors de `screen` : sa chaîne de fenêtres est à la limite de ce que le compilateur vérifie.
        screen
            .modifier(ComicConversionAlerts(comics: convertingComics, sizeText: conversionSizeText, confirming: $showConvertConfirmation) {
                selecting = false
                batch = BatchDeletion()
            })
            .overlay(alignment: .top) { noticeBanner }
    }

    private var screen: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                libraryBackdrop
                Group {
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
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if let progress = model.importProgress {
                ImportBanner(progress: progress, cancel: { model.cancelConversion() }).padding(.bottom, 28)
            }
        }
        // « Livre ou manuel ? » après chaque import (RET-039, #54). Une alerte ne se ferme pas par un toucher à côté :
        // chaque document reçoit une réponse, « Plus tard » compris.
        .alert("Livre, manuel ou manga ?", isPresented: Binding(get: { !model.categoryQuestions.isEmpty }, set: { _ in }),
               presenting: model.categoryQuestions.first) { _ in
            ForEach(DocumentCategory.allCases, id: \.self) { category in
                Button(category.title) { model.answerCategory(category) }
            }
            Button("Manga") { model.answerManga() }
            Button("Plus tard", role: .cancel) { model.answerCategory(nil) }
        } message: { document in
            Text("« \(document.title) » : la catégorie s'affiche sur l'accueil pour t'aider à te repérer. Tu pourras la changer dans « Ce document ».")
        }
        .sheet(isPresented: $showImportOptions) {
            ImportOptionsView(onImport: { urls, language in model.importFiles(urls, language: language) },
                              onPackage: { url in openPackage(url) })
                .preferredColorScheme(Theme.current.colorScheme)
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
            DocumentAnalysisSheet(document: document).environmentObject(model).preferredColorScheme(Theme.current.colorScheme)
        }
        .sheet(isPresented: $showMerge) {
            PDFMergeView().environmentObject(model).preferredColorScheme(Theme.current.colorScheme)
        }
        .sheet(isPresented: $showImagesToPDF) {
            ImagesToPDFView().environmentObject(model).preferredColorScheme(Theme.current.colorScheme)
        }
        // Fermeture des Réglages : la palette ou le style choisis s'appliquent à toute l'app (reconstruction).
        .sheet(isPresented: $showSettings, onDismiss: { themes.applyAppearance() }) {
            SettingsView().environmentObject(themes).environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(Theme.current.colorScheme)
                .atelierSheet()
        }
        .sheet(isPresented: $showDrive) {
            DriveBrowserView().environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(Theme.current.colorScheme)
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
            .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(Theme.current.colorScheme)
        }
        .fullScreenCover(isPresented: $showNotes, onDismiss: {
            model.refreshNotesToReview()
            // Le livre s'ouvre une fois l'écran « Notes » refermé (deux plein écran ne s'empilent pas ; revue F9).
            if let note = noteToOpen { model.open(note) }
            noteToOpen = nil
        }) {
            NotesView { noteToOpen = $0 }
                .environmentObject(model).preferredColorScheme(Theme.current.colorScheme)
        }
        // Pastille des notes relue au retour sur l'accueil (une échéance a pu passer, une note a pu être supprimée),
        // au retour dans l'app (changement de jour) et quand la corbeille change (revue DeepSeek F4).
        .onAppear { model.refreshNotesToReview() }
        .onChange(of: model.openDocumentId) {
            if $0 == nil {
                model.refreshNotesToReview()
                model.noteJump = nil   // jamais une demande de saut pendante au retour sur l'accueil (F2)
            }
        }
        .onChange(of: model.trashedDocuments.count) { _ in model.refreshNotesToReview() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            model.refreshNotesToReview()
        }
        .fullScreenCover(isPresented: $showLexicon) {
            NavigationStack {
                LexiconView(dictionary: model.dictionary) { term in
                    model.review.add(term, sentence: nil, source: nil, image: nil, documentId: nil, page: nil,
                                     dictionary: model.dictionary)
                }
                    .navigationTitle("Lexique")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showLexicon = false } } }
            }
            .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(Theme.current.colorScheme)
        }
        // Fenêtre posée sur l'accueil, pas une page plein écran (recette iPad 1.5.1, point 5.1) : l'accueil reste visible
        // autour, sous un voile ; toucher le voile ou « OK » referme.
        .overlay {
            if showDashboard {
                ZStack {
                    Atelier.scrim.opacity(0.35).ignoresSafeArea()
                        .onTapGesture { showDashboard = false }
                        .accessibilityLabel(Text("Fermer le tableau de bord"))
                        .accessibilityAddTraits(.isButton)
                    DashboardView(onClose: { showDashboard = false })
                        .environmentObject(model).environmentObject(model.review)
                        .frame(maxWidth: 1040, maxHeight: 860)
                        // Coins toujours arrondis, même avec un style à angles droits (demande de NOxygen59, 07/11/2026).
                        .clipShape(RoundedRectangle(cornerRadius: Self.dashboardRadius, style: .continuous))
                        .atelierShapeShadow(RoundedRectangle(cornerRadius: Self.dashboardRadius, style: .continuous),
                                            opacity: 0.35, radius: 30, y: 12)
                        .padding(.horizontal, 36).padding(.vertical, 28)
                        .accessibilityAddTraits(.isModal)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.9), value: showDashboard)
        .sheet(isPresented: $showBench) {
            NavigationStack {
                BenchView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showBench = false } } }
            }
            .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review).preferredColorScheme(Theme.current.colorScheme)
        }
        .alert("Renommer", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titre", text: $newTitle)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") { if let renaming { model.rename(renaming, to: newTitle) } }
        }
        .fullScreenCover(isPresented: $showReview, onDismiss: { review.refresh() }) {
            ReviewScreen().environmentObject(model).environmentObject(review).preferredColorScheme(Theme.current.colorScheme)
        }
        .onAppear { review.refresh(); takeIncomingPackage() }
        .onChange(of: model.incomingPackage) { _ in takeIncomingPackage() }
        .sheet(item: $addingPages) { document in
            AddPagesView(document: document).environmentObject(model).preferredColorScheme(Theme.current.colorScheme)
        }
        .sheet(item: $editingPages) { target in
            RemovePagesView(target: target).environmentObject(model).preferredColorScheme(Theme.current.colorScheme)
        }
        .onReceive(model.$pageEditRequest) { request in
            guard let request, let document = model.documents.first(where: { $0.id == request.documentId }) else { return }
            model.pageEditRequest = nil
            // Le lecteur (plein écran) finit de se fermer avant d'ouvrir la fenêtre.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { editingPages = PageEditTarget(document: document, page: request.page) }
        }
        .sheet(item: $chatDocument) { document in
            NavigationStack { QwenChatView(document: document, database: model.database) }
                .environmentObject(model).preferredColorScheme(Theme.current.colorScheme)
                // Recette iPad 1.5.5 (10.3) : fermé d'un toucher à côté de la feuille, le chat laissait l'accueil
                // incapable de présenter le lecteur (l'onglet s'ajoutait, le livre ne s'ouvrait pas). Fermé par
                // « Fermer », tout allait bien : seule cette sortie reste, le modèle est déchargé par `onDisappear`.
                .interactiveDismissDisabled()
        }
        // Export Anki demandé depuis l'écran des cartes : la feuille d'export s'ouvre à la fermeture de celui-ci
        // (`onDismiss`, revue DeepSeek n°12), sans délai arbitraire.
        .sheet(item: $cardsDocument, onDismiss: {
            if let exportAfterCards { exporting = exportAfterCards }
            exportAfterCards = nil
        }) { document in
            DocumentCardsView(document: document) {
                exportAfterCards = document
                cardsDocument = nil
            }
            .environmentObject(model).environmentObject(model.review).preferredColorScheme(Theme.current.colorScheme)
        }
        .sheet(item: $exporting) { document in
            DocumentExportSheet(document: document)
                .environmentObject(model).environmentObject(model.review).preferredColorScheme(Theme.current.colorScheme)
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
        .sheet(isPresented: $showTrash) { TrashView().environmentObject(model).preferredColorScheme(Theme.current.colorScheme) }
    }

    @ViewBuilder
    private var libraryBackdrop: some View {
        if PersonalPadLibrary.isAvailable {
            ThemeBackdrop(theme: themes.effectiveTheme, style: themes.style)
                .id(themes.effectiveTheme.id)
                .ignoresSafeArea()
        } else {
            GridBackground()
        }
    }

    /// Rayon de la fenêtre du tableau de bord : celui du style, jamais moins de 18 pt.
    static var dashboardRadius: CGFloat { max(Atelier.corner(26), 18) }

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
                Text(verbatim: space == .manga ? "漫" : "教").font(.custom("HiraMinProN-W6", size: 26))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(Atelier.onAccentInk.opacity(0.85))
                    .background(Atelier.Tint.japanese, in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: spaceTitle).font(Atelier.display(19)).foregroundStyle(Atelier.textPrimary)
                    Text(space == .manga ? "漫画 · lecture de manga" : "教科書 · atelier de lecture").font(Atelier.font(11)).foregroundStyle(Atelier.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                AtelierLabel(String(localized: "Bibliothèque")).padding(.bottom, 4)
                sideRow(.all, icon: "square.grid.2x2", title: String(localized: "Tous les documents"), count: spaceDocuments.count)
                sideRow(.inProgress, icon: "book", title: String(localized: "En cours"),
                        count: spaceDocuments.filter { $0.lastPageIndex > 0 && $0.lastPageIndex < $0.pageCount - 1 }.count)
                sideRow(.drive, icon: "externaldrive.badge.icloud", title: String(localized: "Depuis Drive"),
                        count: spaceDocuments.filter { $0.driveFileId != nil }.count)
            }
            // Recette 1.5.8 : la colonne était trop remplie (13 lignes à la suite). Rien n'est retiré : ce qui sert chaque
            // jour reste en lignes avec pastille ; importer et convertir passent en tuiles ; banc d'essai, corbeille et
            // réglages en rangée du bas.
            VStack(alignment: .leading, spacing: 4) {
                AtelierLabel(String(localized: "Étudier")).padding(.bottom, 4)
                // Manga : pas de révisions, de dictionnaire, d'images vers PDF ni de banc d'essai OCR (demande de NOxygen59,
                // 07/11/2026) ; ces outils servent l'étude des manuels.
                if space != .manga {
                    actionRow(icon: "rectangle.stack.badge.play", title: String(localized: "Révisions"), tint: Atelier.Tint.japanese,
                              count: review.counts.total) { showReview = true }
                    actionRow(icon: "character.book.closed.ja", title: String(localized: "Dictionnaire"), tint: Atelier.Tint.japanese,
                              count: model.dictionary.notebook.saved.count) { showDictionary = true }
                    actionRow(icon: "text.book.closed", title: String(localized: "Lexique"), tint: Atelier.Tint.japanese) { showLexicon = true }
                }
                // Notes dans les deux espaces (revue DeepSeek F1) : les PDF de Manga ont aussi des notes, l'écran est global.
                // Pastille : notes à revoir (échéance passée, aujourd'hui ou demain ; DEC-T4-06).
                // PLAN-NOTIF-001 (DEC-01/02 = A) : « ! » noir si une échéance tombe dans les 7 jours, rouge si elle est
                // aujourd'hui ou dépassée ; le nombre reste dans l'écran Notes.
                actionRow(icon: "note.text", title: String(localized: "Notes"), tint: Atelier.Tint.annotate,
                          due: model.noteDueBadge) { showNotes = true }
            }
            VStack(alignment: .leading, spacing: 8) {
                AtelierLabel(String(localized: "Importer et convertir")).padding(.bottom, 2)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    toolTile(icon: "folder", title: String(localized: "Fichiers"), tint: Atelier.Tint.cloud) { showImportOptions = true }
                    toolTile(icon: "externaldrive.badge.icloud", title: String(localized: "Google Drive"), tint: Atelier.Tint.cloud) { showDrive = true }
                    toolTile(icon: "doc.on.doc", title: String(localized: "Fusionner des PDF"), tint: Atelier.Tint.cloud) { showMerge = true }
                    if space != .manga {
                        toolTile(icon: "photo.on.rectangle.angled", title: String(localized: "Images vers PDF"), tint: Atelier.Tint.cloud) { showImagesToPDF = true }
                    }
                }
            }
            HStack(spacing: 8) {
                if space != .manga {
                    toolTile(icon: "speedometer", title: String(localized: "Banc d'essai OCR"), tint: Atelier.Tint.japanese) { showBench = true }
                }
                toolTile(icon: "trash", title: String(localized: "Corbeille"), tint: Atelier.textSecondary,
                         count: model.trashedDocuments.count) { showTrash = true }
                toolTile(icon: "gearshape", title: String(localized: "Réglages"), tint: Atelier.textSecondary) { showSettings = true }
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
                Text(ui: title)
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

    private func actionRow(icon: String, title: String, tint: Color, count: Int? = nil, due: NoteDueBadge = .none,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 22).foregroundStyle(tint)
                Text(ui: title).foregroundStyle(Atelier.textPrimary)
                Spacer()
                dueMark(due)
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

    /// « ! » des échéances de notes : noir dans les 7 jours, rouge aujourd'hui ou en retard (PLAN-NOTIF-001, E1).
    @ViewBuilder
    private func dueMark(_ due: NoteDueBadge) -> some View {
        if due != .none {
            Text(verbatim: "!").font(Atelier.font(13, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                // Noir demandé par NOxygen59 (recette 1.5.8, 1.9), quel que soit le thème.
                .background(due == .urgent ? Color.red : Color.black, in: Circle())
                .accessibilityLabel(due == .urgent ? String(localized: "Échéance aujourd'hui ou dépassée")
                                    : String(localized: "Échéance dans les 7 jours"))
        }
    }

    /// Tuile compacte de la colonne de gauche (recette 1.5.8) : icône au-dessus, nom en dessous, pastille en coin.
    private func toolTile(icon: String, title: String, tint: Color, count: Int? = nil,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(Atelier.font(17, weight: .medium)).foregroundStyle(tint)
                Text(ui: title).font(Atelier.font(12, weight: .medium)).foregroundStyle(Atelier.textPrimary)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.horizontal, 4).padding(.vertical, 6)
            .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let count, count > 0 {
                    Text("\(count)").font(Atelier.mono).foregroundStyle(Atelier.onAccentInk.opacity(0.8))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(tint, in: Capsule())
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .combine)
    }

    /// Temps de lecture active, à la place de « Progression XX/XX pages » (RET-037, #52).
    private var statsCard: some View {
        Button { statsTapped() } label: { statsCardContent }
            .buttonStyle(PressScale())
            // Revue D-07 (n°5) : une décision en attente ne survit pas à l'écran.
            .onDisappear { cancelStatsBurst() }
            .accessibilityHint(Text("Ouvre le tableau de bord"))
    }

    /// DEC-01 = A : on attend la fin de la rafale ; 3 touchers basculent le mode propriétaire, sinon le tableau de bord.
    private func statsTapped() {
        statsTaps.tap(at: Date())
        statsDecision?.cancel()
        statsDecision = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(TapBurst.window * 1_000_000_000))
            guard !Task.isCancelled, let outcome = statsTaps.outcome(at: Date()) else { return }
            statsTaps = TapBurst()
            switch outcome {
            case .single: showDashboard = true
            case .toggleOwnerMode:
                OwnerMode.toggle()
                ownerFlash = UserDefaults.standard.bool(forKey: OwnerMode.unlockedKey)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                ownerFlash = nil
            }
        }
    }

    private func cancelStatsBurst() {
        statsDecision?.cancel()
        statsTaps = TapBurst()
        ownerFlash = nil
    }

    /// Icône du tableau de bord, ou cadenas pendant le retour de la bascule.
    private var dashboardIcon: String { ownerFlash.map { $0 ? "lock.open.fill" : "lock.fill" } ?? "chart.bar.fill" }

    private var statsCardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AtelierLabel(String(localized: "Temps de lecture"))
                Spacer()
                Image(systemName: dashboardIcon).font(Atelier.font(12)).foregroundStyle(Atelier.textTertiary)
            }
            // Séparé par espace, d'après le journal des séances. Le reste du total, plus ancien que ce journal, reste
            // compté dans Livres & Manuels.
            let now = Date()
            let time = readingTime.breakdown(documents: model.documents + model.trashedDocuments, at: now)
            Text(ReadingClock.format(space == .manga ? time.manga : time.study(total: readingTime.clock.elapsed(at: now))))
                .font(Atelier.display(30)).foregroundStyle(Atelier.textPrimary)
            if space == .study {
                Text("Manuels \(ReadingClock.format(time.textbook)) · Livres \(ReadingClock.format(time.book))")
                    .font(Atelier.font(12)).foregroundStyle(Atelier.textSecondary)
            }
            Text("livre ouvert à l'écran").font(Atelier.font(13)).foregroundStyle(Atelier.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.corner(14), style: .continuous))
    }

    /// Portrait : barre compacte en haut.
    private var compactBar: some View {
        HStack(spacing: 12) {
            Text(verbatim: spaceTitle).font(Atelier.display(22)).foregroundStyle(Atelier.textPrimary)
            Spacer()
            Picker("", selection: $filter) {
                Text("Tous").tag(Filter.all)
                Text("En cours").tag(Filter.inProgress)
                Text("Drive").tag(Filter.drive)
            }
            .pickerStyle(.segmented).frame(width: 260)
            CapsuleButton(icon: "plus", label: String(localized: "Importer")) { showImportOptions = true }
            CapsuleButton(icon: "externaldrive.badge.icloud", label: String(localized: "Google Drive")) { showDrive = true }
            CapsuleButton(icon: "character.book.closed.ja", label: String(localized: "Dictionnaire")) { showDictionary = true }
            // Hors périmètre en Manga (PLAN-LEX-001, § 2) : l'entrée n'existe que pour Livres & Manuels.
            if space == .study {
                CapsuleButton(icon: "text.book.closed", label: String(localized: "Lexique")) { showLexicon = true }
            }
            CapsuleButton(icon: "note.text", label: model.notesToReview > 0
                          ? String(localized: "Notes · \(model.notesToReview) à revoir") : String(localized: "Notes")) { showNotes = true }
                .overlay(alignment: .topTrailing) { dueMark(model.noteDueBadge).scaleEffect(0.75).offset(x: 6, y: -6).allowsHitTesting(false) }
            // Revue D-07 MODLOC E1 (n°1) : en portrait, la même rafale passe par ce bouton (pas de carte « Temps de lecture »).
            CapsuleButton(icon: dashboardIcon, label: String(localized: "Tableau de bord")) { statsTapped() }
                .onDisappear { cancelStatsBurst() }
            CapsuleButton(icon: "gearshape", label: String(localized: "Réglages")) { showSettings = true }
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

    /// Onglets ouverts au-dessus : ils valent pour les deux espaces.
    private var spaceTabs: some View {
        HStack(spacing: 8) {
            spaceTab(.study, title: String(localized: "Livres & Manuels"), icon: "books.vertical")
            spaceTab(.manga, title: String(localized: "Manga"), icon: "book")
            Spacer(minLength: 0)
        }
    }

    private func spaceTab(_ value: LibrarySpace, title: String, icon: String) -> some View {
        let on = space == value
        let count = model.documents.filter { $0.isInMangaSpace == (value == .manga) }.count
        return Button {
            guard !on else { return }
            selecting = false
            openFolderId = nil
            batch = BatchDeletion()
            captureAppearance()
            space = value
            themes.showLibrarySpace(value)
        } label: {
            Label { Text(ui: "\(title) · \(count)") } icon: { Image(systemName: icon) }
                .font(Atelier.font(14, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(on ? Atelier.onAccentInk.opacity(0.85) : Atelier.textPrimary)
                .background(Capsule().fill(on ? Atelier.Tint.japanese : Atelier.surfaceHigh))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // Un seul cliché au-dessus de l’interface, sans dupliquer les listes ni leurs miniatures.
    private func captureAppearance() {
        guard PersonalPadLibrary.isAvailable, !reduceMotion,
              let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive })?.keyWindow else { return }
        snapshot?.removeFromSuperview()
        guard let image = window.snapshotView(afterScreenUpdates: false) else { return }
        image.frame = window.bounds
        image.isUserInteractionEnabled = false
        image.accessibilityElementsHidden = true
        window.addSubview(image)
        snapshot = image
        UIView.animate(withDuration: 0.25, delay: 0.05, options: [.curveEaseInOut]) {
            image.alpha = 0
        } completion: { _ in
            image.removeFromSuperview()
            if snapshot === image { snapshot = nil }
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: Atelier.gap) {
            if usesCompactDocuments {
                VStack(alignment: .leading, spacing: 5) {
                    spaceTabs
                    OpenDocumentsStrip(compact: true, palette: themes.effectiveTheme)
                }
            } else {
                OpenDocumentsStrip(palette: themes.effectiveTheme)
                spaceTabs
            }
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
                Button {
                    folderName = ""
                    folderNaming = .create(moving: [])
                } label: { Label("Nouveau dossier", systemImage: "folder.badge.plus") }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
                if !model.documents.isEmpty {
                    Button {
                        selecting.toggle()
                        if !selecting { batch = BatchDeletion() }
                    } label: { Label(selecting ? String(localized: "Terminé") : String(localized: "Sélectionner"), systemImage: selecting ? "checkmark" : "checklist") }
                        .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.annotate))
                }
                Button { showImportOptions = true } label: { Label("Importer", systemImage: "plus") }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.cloud))
            }
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: Atelier.gap) {
                    if filtered.isEmpty && folderLayout.tiles.isEmpty && currentFolder == nil {
                        emptyState
                    } else {
                        ScrollViewReader { proxy in
                            let displayedSpace = space
                            ScrollView {
                                // Sections « Manuels », « Livres », « Non classés » (recette 1.3.2 (61), E5) : chacune s'allonge
                                // avec ses documents, les suivantes descendent d'autant.
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 22)], spacing: 26) {
                                    if let folder = currentFolder {
                                        // Dossier ouvert (PLAN-T5-001, E2) : ses documents seulement, en une section.
                                        Section {
                                            ForEach(currentFolderDocuments) { document in
                                                documentCard(document)
                                            }
                                        } header: {
                                            openFolderHeader(folder)
                                        }
                                    } else {
                                    if !folderLayout.tiles.isEmpty {
                                        // Dossiers en tête de l'espace (DEC-T5-08 : ordre alphabétique de la base).
                                        Section {
                                            ForEach(folderLayout.tiles) { tile in
                                                Button {
                                                    // Revue DeepSeek n°2 et n°13 : on entre aussi en mode sélection, et
                                                    // la sélection repart de zéro (jamais de document choisi hors de vue).
                                                    batch = BatchDeletion()
                                                    openFolderId = tile.folder.id
                                                } label: {
                                                    FolderCard(name: tile.folder.name, documents: tile.documents)
                                                }
                                                .buttonStyle(PressScale())
                                                .contextMenu { if !selecting { folderMenu(tile.folder) } }
                                                // Revue DeepSeek n°14 : gérer le dossier sans appui long (VoiceOver).
                                                .accessibilityAction(named: Text("Renommer")) { askRename(tile.folder) }
                                                .accessibilityAction(named: Text("Supprimer le dossier")) { deletingFolder = tile.folder }
                                            }
                                        } header: {
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                AtelierLabel(String(localized: "Dossiers"), tint: Atelier.Tint.read)
                                                Text("\(folderLayout.tiles.count)").font(Atelier.mono).foregroundStyle(Atelier.textTertiary)
                                                Spacer()
                                            }
                                            .padding(.top, 8)
                                        }
                                    }
                                    ForEach(sections, id: \.title) { section in
                                        Section {
                                            ForEach(section.documents) { document in
                                                documentCard(document)
                                            }
                                        } header: {
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                AtelierLabel(section.title, tint: space == .manga ? Atelier.Tint.japanese : section.category == .textbook ? Atelier.Tint.read
                                                             : section.category == .book ? Atelier.Tint.annotate : Atelier.textTertiary)
                                                Text("\(section.documents.count)").font(Atelier.mono).foregroundStyle(Atelier.textTertiary)
                                                Spacer()
                                            }
                                            .padding(.top, 8)
                                        }
                                    }
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .coordinateSpace(name: "library-grid")
                            .id(PersonalPadLibrary.isAvailable ? displayedSpace.rawValue : "")
                            .onAppear {
                                if let anchor = scrollAnchors[displayedSpace], filtered.contains(where: { $0.id == anchor }) {
                                    proxy.scrollTo(LibraryCardRenderIdentity(
                                        documentId: anchor,
                                        category: filtered.first(where: { $0.id == anchor })?.category,
                                        selecting: selecting, manga: displayedSpace == .manga,
                                        folderId: openFolderId, selected: selecting && batch.selected.contains(anchor)), anchor: .top)
                                }
                            }
                            .onPreferenceChange(LibraryCardPositions.self) { frames in
                                guard space == displayedSpace else { return }
                                let first = frames.filter { $0.value.maxY > 0 }.min { lhs, rhs in
                                    lhs.value.minY == rhs.value.minY ? lhs.value.minX < rhs.value.minX : lhs.value.minY < rhs.value.minY
                                }
                                if let first, scrollAnchors[displayedSpace] != first.key {
                                    scrollAnchors[displayedSpace] = first.key
                                }
                            }
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
                // Hors du `.transaction` ci-dessus, qui couperait l'animation : le contenu du dossier arrive en zoom
                // léger et en fondu ; en sortant, l'accueil revient du sens inverse. Fondu seul avec « Réduire les
                // animations ».
                .opacity(0.25 + 0.75 * folderProgress)
                .scaleEffect(reduceMotion ? 1 : 1 + (folderEntering ? -0.05 : 0.05) * (1 - folderProgress), anchor: .top)
                .onChange(of: openFolderId) { id in
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) {
                        folderEntering = id != nil
                        folderProgress = 0
                    }
                    // Au tour suivant : sinon SwiftUI fusionne les deux changements et rien ne s'anime.
                    DispatchQueue.main.async {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.88)) {
                            folderProgress = 1
                        }
                    }
                }
                if monitorVisible {
                    ResourceMonitorPanel(expandsDown: true, fillsWidth: monitorDetailed, showsActivities: model.openDocumentId == nil)
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
        // Dossiers (PLAN-T5-001, E2) : nom d'un nouveau dossier (avec les documents à y ranger) ou nouveau nom.
        // Recette 1.5.7 (2.1) : l'alerte système d'iOS 16 n'affichait pas le bouton de validation (grisé au départ, jamais
        // remis à jour) ; fenêtre de l'app à la place, demandée par NOxygen59.
        .sheet(isPresented: Binding(get: { folderNaming != nil }, set: { if !$0 { folderNaming = nil } })) {
            FolderNameSheet(title: folderNaming?.title ?? "", name: $folderName,
                            confirm: folderNaming.map { if case .rename = $0 { return String(localized: "Renommer") }
                                                        return String(localized: "Créer") } ?? "",
                            cancel: { folderNaming = nil }) {
                switch folderNaming {
                case .create(let moving):
                    model.createFolder(named: folderName, in: LibraryFolderLayout.commonSpace(of: moving) ?? space,
                                       moving: moving.map(\.id))
                case .rename(let folder): model.renameFolder(folder, to: folderName)
                case nil: break
                }
                folderNaming = nil
            }
        }
        .alert("Supprimer ce dossier ?", isPresented: Binding(get: { deletingFolder != nil },
                                                              set: { if !$0 { deletingFolder = nil } })) {
            Button("Annuler", role: .cancel) { deletingFolder = nil }
            Button("Supprimer le dossier", role: .destructive) {
                if let deletingFolder {
                    if openFolderId == deletingFolder.id { openFolderId = nil }
                    model.deleteFolder(deletingFolder)
                }
                deletingFolder = nil
            }
        } message: {
            Text("« \(deletingFolder?.name ?? "") » disparaît. Ses documents restent dans la bibliothèque, dans leur section habituelle.")
        }
    }

    /// Carte d'un document dans la grille (sections habituelles et dossier ouvert).
    @ViewBuilder
    private func documentCard(_ document: LibraryDocument) -> some View {
        Button {
            if selecting { batch.toggle(document.id) } else { model.openDocumentId = document.id }
        } label: {
            DocumentCard(document: document)
        }
        .buttonStyle(PressScale())
        .id(LibraryCardRenderIdentity(documentId: document.id,
                                      category: document.category,
                                      selecting: selecting,
                                      manga: document.isInMangaSpace,
                                      folderId: openFolderId,
                                      selected: selecting && batch.selected.contains(document.id)))
        // La catégorie appartient à l'état courant de la bibliothèque. En la
        // dessinant au-dessus du bouton, elle n'est plus retenue dans l'ancien
        // rendu interne de la carte après l'import.
        .overlay(alignment: .topLeading) {
            if document.isInMangaSpace {
                // Format fixe pour un .cbz ; simple rangement pour un PDF.
                mangaMark(archive: document.isComicArchive).allowsHitTesting(false)
            } else if let category = document.category {
                categoryMark(category).allowsHitTesting(false)
            }
        }
        // L'indicateur reste au-dessus du bouton lui-même. Dans le contenu du
        // bouton, SwiftUI pouvait le masquer jusqu'à la reconstruction de la
        // bibliothèque après un redémarrage (constaté sur iPad, 30/10/2026).
        .overlay(alignment: .topTrailing) {
            if selecting {
                selectionMark(batch.selected.contains(document.id))
                    .allowsHitTesting(false)
            }
        }
        .background {
            if PersonalPadLibrary.isAvailable {
                GeometryReader { card in
                    Color.clear.preference(key: LibraryCardPositions.self,
                        value: [document.id: card.frame(in: .named("library-grid"))])
                }
            }
        }
        .contextMenu { if !selecting { menu(for: document) } }
    }

    /// En-tête du dossier ouvert : retour à l'accueil, nom, nombre, gestion du dossier.
    private func openFolderHeader(_ folder: LibraryFolder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    batch = BatchDeletion()
                    openFolderId = nil
                } label: { Label("Accueil", systemImage: "chevron.left") }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
                Image(systemName: "folder.fill").foregroundStyle(Atelier.Tint.read)
                Text(folder.name).font(Atelier.font(20, weight: .semibold)).foregroundStyle(Atelier.textPrimary).lineLimit(1)
                Text("\(currentFolderDocuments.count)").font(Atelier.mono).foregroundStyle(Atelier.textTertiary)
                Spacer()
                Menu { folderMenu(folder) } label: { Image(systemName: "ellipsis.circle").font(Atelier.font(22)) }
                    .accessibilityLabel(String(localized: "Gérer le dossier"))
            }
            if currentFolderDocuments.isEmpty {
                Text(isFiltering ? String(localized: "Aucun document de ce dossier ne correspond au filtre.")
                     : String(localized: "Dossier vide. Pour y ranger un document : appui long sur sa carte → « Déplacer vers… », ou « Sélectionner » puis « Déplacer »."))
                    .font(Atelier.font(14)).foregroundStyle(Atelier.textSecondary)
            }
        }
        .padding(.top, 8)
    }

    /// Renommer ou supprimer un dossier (la suppression demande confirmation ; les documents restent).
    @ViewBuilder
    private func folderMenu(_ folder: LibraryFolder) -> some View {
        // Revue DeepSeek n°4 : après la fermeture du menu d'appui long (0,35 s, comme les autres fenêtres de
        // l'accueil), sinon iOS peut ignorer la fenêtre.
        Button { afterMenu { askRename(folder) } } label: { Label("Renommer", systemImage: "pencil") }
        Button(role: .destructive) { afterMenu { deletingFolder = folder } } label: { Label("Supprimer le dossier", systemImage: "folder.badge.minus") }
    }

    private func askRename(_ folder: LibraryFolder) {
        folderName = folder.name
        folderNaming = .rename(folder)
    }

    /// Présente une fenêtre une fois le menu contextuel refermé.
    private func afterMenu(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }

    /// « Déplacer vers… » : dossiers de l'espace des documents, nouveau dossier, ou sortie du dossier. Une sélection qui
    /// mélange les deux espaces ne propose que la sortie (un dossier appartient à un seul espace, DEC-T5-02).
    @ViewBuilder
    private func moveMenuItems(_ documents: [LibraryDocument]) -> some View {
        let current = Set(documents.compactMap { model.folders.membership[$0.id] })
        if let common = LibraryFolderLayout.commonSpace(of: documents) {
            ForEach(model.folders.folders(in: common.rawValue)) { folder in
                Button { model.move(documents, to: folder) } label: { shelfLabel(folder.name, on: current == [folder.id]) }
            }
            Button {
                afterMenu {
                    folderName = ""
                    folderNaming = .create(moving: documents)
                }
            } label: { Label("Nouveau dossier…", systemImage: "folder.badge.plus") }
        }
        if !current.isEmpty {
            Button { model.move(documents, to: nil) } label: { Label("Sortir du dossier", systemImage: "arrow.up.forward.square") }
        }
    }

    /// Pastille Livre/Manuel, rendue par la grille depuis la catégorie publiée la plus récente.
    private func categoryMark(_ category: DocumentCategory) -> some View {
        Text(category.title).font(Atelier.font(11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(Atelier.onAccentInk.opacity(0.8))
            .background(category == .textbook ? Atelier.Tint.read : Atelier.Tint.annotate, in: Capsule())
            .padding(8)
    }

    private func mangaMark(archive: Bool) -> some View {
        Text(archive ? String(localized: "CBZ · expérimental") : String(localized: "Manga")).font(Atelier.font(11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(Atelier.onAccentInk.opacity(0.8))
            .background(Atelier.Tint.japanese, in: Capsule())
            .padding(8)
    }

    /// Case de sélection sur la couverture.
    private func selectionMark(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(Atelier.font(26, weight: .semibold))
            .foregroundStyle(on ? Atelier.Tint.annotate : Atelier.textPrimary)
            .background(Circle().fill(Atelier.surface.opacity(0.8)))
            .padding(10)
            .accessibilityLabel(on ? String(localized: "Sélectionné") : String(localized: "Non sélectionné"))
    }

    /// Barre de la sélection : tout sélectionner, supprimer (première des deux confirmations).
    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text("\(batch.selected.count) sélectionné\(batch.selected.count > 1 ? "s" : "")")
                .font(Atelier.font(14, weight: .semibold)).foregroundStyle(Atelier.textSecondary)
            Spacer()
            // Propre à l'espace Manga : le CBZ reste en place, le PDF créé a l'OCR.
            if space == .manga, !selectedComics.isEmpty {
                Button("Convertir en PDF (\(selectedComics.count))") {
                    convertingComics = selectedComics
                    showConvertConfirmation = true
                }
                .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.japanese))
            }
            Menu {
                moveMenuItems(model.documents.filter { batch.selected.contains($0.id) })
            } label: {
                Label("Déplacer", systemImage: "folder")
                    .font(Atelier.font(15, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .foregroundStyle(Atelier.onAccentInk.opacity(0.85))
                    .background(Atelier.Tint.read, in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
            }
            .disabled(batch.selected.isEmpty)
            Button("Tout sélectionner") {
                let comics = DocumentImporter.conversionOrder(visibleDocuments)
                batch.selectAll(comics.map(\.id) + visibleDocuments.filter { !$0.isComicArchive }.map(\.id))
            }
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
        // Revue Codex après 1.5.6 (P2 n°1) : la sélection suit ce qui est affiché (déplacement, dossier ouvert).
        .onChange(of: visibleDocuments.map(\.id)) { ids in batch.keepOnly(Set(ids)) }
    }

    /// Titres des documents choisis (au plus 5), pour les deux questions.
    private var batchTitles: String {
        let titles = model.documents.filter { batch.selected.contains($0.id) }.map(\.title)
        let shown = titles.prefix(5).map { "« \($0) »" }.joined(separator: "\n")
        return titles.count > 5 ? shown + String(localized: "\n… et \(titles.count - 5) autre\(titles.count - 5 > 1 ? "s" : "")") : shown
    }

    private var filterTitle: String {
        switch filter {
        case .all: return String(localized: "Tous les documents")
        case .inProgress: return String(localized: "En cours")
        case .drive: return String(localized: "Depuis Google Drive")
        }
    }

    /// Un modèle de chat est là : officiel ou importé (revue R2 MODLOC E3, n°1).
    private var chatModelInstalled: Bool {
        Qwen3VLReader().isAvailable || ModelStore.shared.isInstalled(.qwen35chat4b) || !LocalModels.specs().isEmpty
    }

    @ViewBuilder
    private func menu(for document: LibraryDocument) -> some View {
        Button { model.openDocumentId = document.id } label: { Label("Ouvrir", systemImage: "book") }
        if !document.capabilities.chat || !ownerUnlocked {
            // CBZ et mangas : ni chat ni mention de lecture IA. Mode propriétaire verrouillé : chat caché (DEC-03).
        } else if chatModelInstalled, DocumentKnowledge.isReady(document) {
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { chatDocument = document }
            } label: { Label("Discuter du livre", systemImage: "bubble.left.and.bubble.right") }
        } else if chatModelInstalled {
            Label("Chat après lecture OvisOCR2 (\(DocumentKnowledge.readCount(document))/\(document.pageCount))",
                  systemImage: "text.book.closed")
        }
        Button {
            newTitle = document.title
            renaming = document
        } label: { Label("Renommer", systemImage: "pencil") }
        Menu { moveMenuItems([document]) } label: { Label("Déplacer vers…", systemImage: "folder") }
        if document.capabilities.editableShelf {
            shelfPicker(for: document)
        }
        if document.capabilities.pageEditing {
            Button {
                pageOneText = String(document.firstPageIndex + 1)
                settingPageOne = document
            } label: { Label("Définir la page 1…", systemImage: "1.circle") }
        }
        if document.capabilities.study {
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { analyzing = document }
            } label: {
                if let r = DocumentAnalysisService.shared.report(for: document.id), !r.pages.isEmpty {
                    Label("Analyse : fiabilité \(Int(r.reliability * 100)) %", systemImage: "checkmark.seal")
                } else {
                    Label("Analyser le document entier", systemImage: "checkmark.seal")
                }
            }
        }
        // Revue DeepSeek (n°11) : même condition que « Créer des cartes de cette page » dans le lecteur (pas les CBZ).
        if document.capabilities.pageEditing {
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { cardsDocument = document }
            } label: { Label("Cartes de ce document", systemImage: "rectangle.stack") }
        }
        if document.capabilities.pageEditing {
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { addingPages = document }
            } label: { Label("Ajouter des pages…", systemImage: "doc.badge.plus") }
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editingPages = PageEditTarget(document: document, page: nil) }
            } label: { Label("Supprimer des pages…", systemImage: "doc.badge.minus") }
        }
        if document.capabilities.export {
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { exporting = document }
            } label: { Label("Exporter…", systemImage: "square.and.arrow.up") }
        }
        Button(role: .destructive) {
            // Le menu d'appui long doit finir de se fermer, sinon iOS ignore la fenêtre de confirmation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { deleting = document }
        } label: { Label("Supprimer", systemImage: "trash") }
    }

    /// Classement libre. « Manga » est un espace, pas un format : le PDF garde l'OCR et l'étude.
    private func shelfPicker(for document: LibraryDocument) -> some View {
        let manga = document.isInMangaSpace
        return Menu {
            ForEach(DocumentCategory.allCases, id: \.self) { category in
                Button {
                    model.setMangaSpace(document.id, false)
                    model.setCategory(document.id, category)
                } label: { shelfLabel(category.title, on: !manga && document.category == category) }
            }
            Button {
                model.setMangaSpace(document.id, true)
                model.setCategory(document.id, nil)
            } label: { shelfLabel(String(localized: "Manga"), on: manga) }
            Button {
                model.setMangaSpace(document.id, false)
                model.setCategory(document.id, nil)
            } label: { shelfLabel(String(localized: "Non classé"), on: !manga && document.category == nil) }
        } label: {
            Label("Catégorie", systemImage: "tag")
        }
    }

    @ViewBuilder
    private func shelfLabel(_ title: String, on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("教").font(.custom("HiraMinProN-W6", size: 64)).foregroundStyle(Atelier.Tint.japanese.opacity(0.8))
            Text(space == .manga && filter == .all ? String(localized: "Aucun manga pour l'instant") : filter == .all ? String(localized: "Ta bibliothèque est vide") : String(localized: "Rien ici pour l'instant"))
                .font(Atelier.display(24)).foregroundStyle(Atelier.textPrimary)
            Text(space == .manga ? "Importe un .cbz, ou range un PDF ici d'un appui long sur sa carte." : "Importe un cours ou un manuel en PDF, depuis Fichiers ou Google Drive.")
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

/// Toute petite barre sous la carte du document en cours d'analyse. Vue à part : seule elle se redessine à chaque page
/// analysée, pas toute la grille. Rien du tout pour les autres documents.
private struct AnalysisProgressLine: View {
    let documentId: String
    @ObservedObject private var analysis = DocumentAnalysisService.shared

    var body: some View {
        if let progress = analysis.progress, progress.documentId == documentId {
            GeometryReader { area in
                ZStack(alignment: .leading) {
                    Capsule().fill(Atelier.Tint.ai.opacity(0.2))
                    Capsule().fill(Atelier.Tint.ai)
                        .frame(width: max(2, area.size.width * Double(progress.done) / Double(max(progress.total, 1))))
                }
            }
            .frame(height: 2)
            .accessibilityElement()
            .accessibilityLabel(Text("Analyse : \(progress.done) sur \(progress.total)"))
        }
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
            AnalysisProgressLine(documentId: document.id)
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

/// Questions de la conversion des CBZ. À part : la vue de l'accueil porte déjà trop de fenêtres pour le compilateur.
private struct ComicConversionAlerts: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let comics: [LibraryDocument]
    let sizeText: String
    @Binding var confirming: Bool
    let started: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Convertir \(comics.count) CBZ en PDF ?", isPresented: $confirming) {
                Button("Convertir") {
                    model.convertComics(comics)
                    started()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Un PDF par CBZ, avec les fonctions OCR de l'app. Les CBZ restent en place. Place nécessaire : environ \(sizeText).")
            }
            .alert("Mettre \(model.convertedComics.count) CBZ à la corbeille ?", isPresented: Binding(
                get: { !model.convertedComics.isEmpty }, set: { if !$0 { model.convertedComics = [] } })) {
                Button("Mettre à la corbeille", role: .destructive) {
                    model.convertedComics.forEach(model.moveToTrash)
                    model.convertedComics = []
                }
                Button("Garder", role: .cancel) { model.convertedComics = [] }
            } message: {
                Text("Leur conversion a réussi. Le PDF garde sa propre progression, et les CBZ restent récupérables dans la corbeille.")
            }
    }
}

struct ImportBanner: View {
    let progress: AppModel.ImportProgress
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Atelier.Tint.cloud)
            VStack(alignment: .leading) {
                Text(progress.isConversion ? String(localized: "Conversion \(progress.done + 1) / \(progress.total)")
                     : String(localized: "Import \(progress.done + 1) / \(progress.total)")).font(.subheadline.bold())
                Text(progress.currentName).font(.caption).foregroundStyle(Atelier.textSecondary).lineLimit(1)
            }
            if progress.isConversion { Button("Annuler", action: cancel).font(.subheadline.weight(.semibold)) }
        }
        .foregroundStyle(Atelier.textPrimary)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .atelierPanel(radius: 24)
    }
}

private struct LibraryCardPositions: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Fenêtre de nom d'un dossier de l'accueil (PLAN-T5-001, E2).
/// Nom d'un dossier (créer ou renommer) dans une fenêtre de l'app (recette 1.5.7, 2.1) : champ prêt à taper, bouton de
/// validation actif dès qu'un nom est écrit, « Entrée » valide aussi.
struct FolderNameSheet: View {
    let title: String
    @Binding var name: String
    let confirm: String
    let cancel: () -> Void
    let done: () -> Void
    @FocusState private var focused: Bool

    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom du dossier", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { if valid { done() } }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", action: cancel) }
                ToolbarItem(placement: .confirmationAction) { Button(confirm, action: done).disabled(!valid) }
            }
            // Revue D-07 (n°2) : le focus demandé pendant l'animation d'ouverture est perdu sur iOS 16 ; on attend sa fin.
            .task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                focused = true
            }
        }
        .presentationDetents([.medium])
    }
}

enum FolderNaming {
    /// Nouveau dossier ; les documents donnés y sont rangés tout de suite (« Déplacer vers → Nouveau dossier… »).
    case create(moving: [LibraryDocument])
    case rename(LibraryFolder)

    var title: String {
        switch self {
        case .create: return String(localized: "Nouveau dossier")
        case .rename: return String(localized: "Renommer le dossier")
        }
    }
}

/// Tuile d'un dossier sur l'accueil : même gabarit qu'une carte de document, avec les couvertures des premiers
/// documents en éventail (PLAN-T5-001, E2).
struct FolderCard: View {
    let name: String
    let documents: [LibraryDocument]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: Atelier.corner(12), style: .continuous).fill(Atelier.surfaceHigh)
                .aspectRatio(0.72, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    if documents.isEmpty {
                        Image(systemName: "folder").font(Atelier.font(44)).foregroundStyle(Atelier.Tint.read)
                    } else {
                        ZStack {
                            ForEach(Array(documents.prefix(3).enumerated().reversed()), id: \.element.id) { index, document in
                                FolderCover(document: document)
                                    .padding(22)
                                    .rotationEffect(.degrees(Double(index) * -5))
                                    .offset(x: CGFloat(index) * -6, y: CGFloat(index) * 4)
                            }
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "folder.fill").font(Atelier.font(15, weight: .bold))
                        .padding(8)
                        .foregroundStyle(Atelier.onAccentInk.opacity(0.85))
                        .background(Atelier.Tint.read, in: Circle())
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: Atelier.corner(12), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Atelier.corner(12), style: .continuous).strokeBorder(Atelier.hairline))
            Text(name).font(Atelier.font(15, weight: .semibold)).lineLimit(2)
                .foregroundStyle(Atelier.textPrimary)
            Text(documents.count == 1 ? String(localized: "1 document") : String(localized: "\(documents.count) documents"))
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Atelier.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(documents.count == 1 ? String(localized: "Dossier \(name), 1 document")
                            : String(localized: "Dossier \(name), \(documents.count) documents"))
    }
}

/// Couverture réduite d'un document dans une tuile de dossier. Revue DeepSeek n°3 : le cache mémoire seul restait
/// vide au lancement (un document rangé n'a plus de carte à l'accueil) ; la vignette passe donc par le même chemin que
/// `DocumentCard` (même largeur 400, donc même entrée de cache, rendue au plus une fois). Trois au plus par dossier.
private struct FolderCover: View {
    @EnvironmentObject private var model: AppModel
    let document: LibraryDocument
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: Atelier.corner(6), style: .continuous).fill(Atelier.surface)
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
