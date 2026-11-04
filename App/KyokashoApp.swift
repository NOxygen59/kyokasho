// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import ONNXOCRKit
import ReaderCore
import SwiftUI
import UIKit

@main
struct KyokashoApp: App {
    init() {
        // Avant tout : journal de diagnostic et gestionnaire d'erreurs MLX (message noté avant un arrêt).
        Diagnostics.start()
        // Restauration préparée (#51) : appliquée avant que la moindre base soit ouverte.
        LibraryBackupService.applyPendingRestoreOnce()
        // Avant toute lecture du fond des pages (`@AppStorage`, `PageTone.current`) : valeurs retirées remplacées.
        PageTone.migrateStoredSetting()
        // Avant toute lecture de la position du panneau d'étude (`@AppStorage`) : position retirée remplacée.
        StudyPanelMode.migrateStoredSetting()
    }

    @StateObject private var model = AppModel()
    @StateObject private var themes = ThemeManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                // Reconstruit toute l'interface quand une nouvelle apparence est appliquée, c'est-à-dire à la fermeture
                // des Réglages : la page Thèmes reste ouverte pendant le choix et tout est à jour en sortant.
                .id(themes.appliedAppearance)
                .macInitialWindowFrame()
                .environmentObject(themes)
                .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review)
                .preferredColorScheme(themes.theme.colorScheme)
                .atelierFontDesign()
                .tint(Atelier.Tint.read)
                .onOpenURL { url in
                    // PDF ouvert depuis une autre app (« Ouvrir dans Kyōkasho »).
                    // Les copies déposées dans Inbox par le système sont à nous : on les supprime après import.
                    // Paquet `.kyokasho` touché dans Fichiers : même parcours que « Importer un paquet » (bibliothèque).
                    if url.isFileURL, url.pathExtension.lowercased() == DocumentPackage.fileExtension {
                        model.openDocumentId = nil
                        model.incomingPackage = url
                    } else if url.isFileURL { model.importFiles([url], cleanUp: url.path.contains("/Inbox/")) }
                }
                #if DEBUG
                .onAppear {
                    // Tests dans le simulateur sans fenêtre : `-forceLandscape YES` met l'app en paysage.
                    if UserDefaults.standard.bool(forKey: "forceLandscape"),
                       let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                    }
                }
                #endif
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    LocalServerVLM.stopAtTermination()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    model.thumbnails.trim()
                    ONNXEngines.unload()
                    PDFPool.release()
                    ScanSharpening.clearMemory()
                    FuriganaLayer.clearMemory()
                    ToneCache.clear()
                    Task { await GLMOCREngine.unload() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themes: ThemeManager
    @ObservedObject private var dictionaryUpdates = DictionaryCatalogService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var retryingStorage = false

    var body: some View {
        Group {
            if let error = model.storageRecoveryError {
                VStack(spacing: 20) {
                    Text("Reprise des données nécessaire").font(.title2)
                    Text(error)
                    // Restauration inachevée (#51) : seule une relance peut la reprendre, avant l'ouverture des bases.
                    if !LibraryBackupService.restoreBlocked { Button("Réessayer la reprise") {
                        guard !retryingStorage else { return }
                        retryingStorage = true
                        Task {
                            defer { retryingStorage = false }
                            let id = PageShift.pendingDocumentId
                            PageShift.reconcile(model)
                            if model.storageRecoveryError == nil, let id {
                                model.storageRecoveryError = String(localized: "Finalisation de la reprise…")
                                await model.ocr.endPageMutation(documentId: id)
                                model.storageRecoveryError = nil
                            }
                        }
                    }.disabled(retryingStorage) }
                }.padding()
            } else {
                NavigationStack {
                    LibraryView()
                        .safeAreaInset(edge: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                UpdateBanner()
                                DictionaryUpdateBanner().environmentObject(model.dictionary)
                                AnalysisDurationBanner()
                            }
                        }
                }
            }
        }
        // Tâches IA toujours en cours ; le moniteur de la bibliothèque est ancré à droite de la liste (recette 63).
        .overlay(alignment: .bottomLeading) { ActivityDock(showsMonitor: false).padding(Atelier.gap) }
        .task {
            AppUpdate.shared.checkAtLaunch(); MorphologyService.shared.loadIfInstalled(); EnergyMeter.shared.attach(model)
            await DictionaryCatalogService.shared.installAllOnFirstLaunch(model: model.dictionary)
        }
        // Visite guidée au premier lancement, nouveautés après une mise à jour.
        .modifier(IntroPresenter(hasLibrary: { [model] in !model.documents.isEmpty }))
        // Une seule couverture pour tous les onglets (#16) : changer d'onglet remplace le lecteur sans refermer
        // ni rouvrir la feuille plein écran.
        .fullScreenCover(isPresented: Binding(
            get: { model.storageRecoveryError == nil && model.openDocumentId.map { id in model.documents.contains { $0.id == id } } == true },
            set: { if !$0 { model.openDocumentId = nil } }
        )) {
            ReaderTabsHost()
                .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review)
                .preferredColorScheme(Theme.current.colorScheme)
                .atelierFontDesign()
                .tint(Atelier.Tint.read)
        }
        // Retour à la bibliothèque ou app en arrière-plan : les IA rendent leur mémoire.
        .onChange(of: model.openDocumentId) {
            guard $0 == nil else { return }
            Self.releaseAI()
            themes.applyAppearance() // Style choisi juste avant d'ouvrir un manuel : appliqué au retour.
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { Self.releaseAI() }
            // Au retour dans l'app : le Wi-Fi a pu revenir ou la semaine être passée. La garde hebdomadaire reste.
            if phase == .active, !LibraryBackupService.inProgress {
                Task { await dictionaryUpdates.checkAutomaticallyIfDue(model: model.dictionary) }
            }
        }
        .task {
            // Après le chargement de la bibliothèque, et jamais par-dessus une sauvegarde en cours.
            guard !LibraryBackupService.inProgress else { return }
            await dictionaryUpdates.checkAutomaticallyIfDue(model: model.dictionary)
        }
        .alert("Erreur", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    /// Décharge les modèles d'IA (MLX, ONNX, cache GPU), sauf pendant une analyse du document entier ou une lecture
    /// en cours : celles-ci continuent et le modèle est libéré à la fin par inactivité.
    private static func releaseAI() {
        guard DocumentAnalysisService.shared.progress == nil else { return }
        ONNXEngines.unload()
        Task { await GLMOCREngine.unloadIfIdle() }
    }
}

private extension View {
    /// Version Mac : fenêtre en 10:9 à l'ouverture. Rien sur iPad.
    @ViewBuilder
    func macInitialWindowFrame() -> some View {
        #if targetEnvironment(macCatalyst)
        task { await MacInitialWindow.applyOnce() }
        #else
        self
        #endif
    }
}

#if targetEnvironment(macCatalyst)
@MainActor
private enum MacInitialWindow {
    /// Une seule fois par lancement : la racine est reconstruite à chaque changement d'apparence, et ce ne doit pas
    /// redimensionner une fenêtre que l'utilisateur a déjà ajustée.
    private static var applied = false

    static func applyOnce() async {
        guard !applied else { return }
        applied = true
        // Au tout premier affichage, le système ignore la demande (essai du 04/11/2026) : la scène doit être installée.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let restrictions = scene.sizeRestrictions else { return }
        let frame = MacWindowFrame.initial(screen: scene.screen.bounds)
        let minimum = restrictions.minimumSize, maximum = restrictions.maximumSize
        // Taille imposée le temps du changement, puis rendue : la fenêtre reste redimensionnable.
        // Ces limites se comptent en points de l'app, affichés à 77 % sur Mac ; `systemFrame`, en points de l'écran.
        let appSize = CGSize(width: frame.width / 0.77, height: frame.height / 0.77)
        restrictions.minimumSize = appSize
        restrictions.maximumSize = appSize
        scene.requestGeometryUpdate(.Mac(systemFrame: frame)) { error in
            Diagnostics.error("fenêtre Mac : \(error.localizedDescription)", "app")
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        restrictions.minimumSize = minimum
        restrictions.maximumSize = maximum
    }
}
#endif
