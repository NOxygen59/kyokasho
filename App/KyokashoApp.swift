// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import ONNXOCRKit
import SwiftUI
import UIKit

@main
struct KyokashoApp: App {
    init() {
        // Avant tout : journal de diagnostic et gestionnaire d'erreurs MLX (message noté avant un arrêt).
        Diagnostics.start()
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
                // Changer de thème reconstruit toute l'interface avec les nouvelles couleurs.
                .id(themes.identity)
                .environmentObject(themes)
                .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review)
                .preferredColorScheme(themes.style.colorScheme)
                .atelierFontDesign()
                .tint(Atelier.Tint.read)
                .onOpenURL { url in
                    // PDF ouvert depuis une autre app (« Ouvrir dans Kyōkasho »).
                    // Les copies déposées dans Inbox par le système sont à nous : on les supprime après import.
                    if url.isFileURL { model.importFiles([url], cleanUp: url.path.contains("/Inbox/")) }
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var retryingStorage = false

    var body: some View {
        Group {
            if let error = model.storageRecoveryError {
                VStack(spacing: 20) {
                    Text("Reprise des données nécessaire").font(.title2)
                    Text(error)
                    Button("Réessayer la reprise") {
                        guard !retryingStorage else { return }
                        retryingStorage = true
                        Task {
                            defer { retryingStorage = false }
                            let id = PageShift.pendingDocumentId
                            PageShift.reconcile(model)
                            if model.storageRecoveryError == nil, let id {
                                model.storageRecoveryError = "Finalisation de la reprise…"
                                await model.ocr.endPageMutation(documentId: id)
                                model.storageRecoveryError = nil
                            }
                        }
                    }.disabled(retryingStorage)
                }.padding()
            } else {
                NavigationStack {
                    LibraryView()
                        .safeAreaInset(edge: .top, spacing: 0) { UpdateBanner() }
                }
            }
        }
        // Tâches IA toujours en cours ; le moniteur de la bibliothèque est ancré à droite de la liste (recette 63).
        .overlay(alignment: .bottomLeading) { ActivityDock(showsMonitor: false).padding(Atelier.gap) }
        .task { AppUpdate.shared.checkAtLaunch(); MorphologyService.shared.loadIfInstalled() }
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
                .preferredColorScheme(AppStyle.current.colorScheme)
                .atelierFontDesign()
                .tint(Atelier.Tint.read)
        }
        // Retour à la bibliothèque ou app en arrière-plan : les IA rendent leur mémoire.
        .onChange(of: model.openDocumentId) { if $0 == nil { Self.releaseAI() } }
        .onChange(of: scenePhase) { if $0 == .background { Self.releaseAI() } }
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
