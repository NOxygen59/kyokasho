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
    }

    @StateObject private var model = AppModel()
    @StateObject private var themes = ThemeManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                // Changer de thème reconstruit toute l'interface avec les nouvelles couleurs.
                .id(themes.theme.id)
                .environmentObject(themes)
                .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review)
                .preferredColorScheme(.dark)
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
                    Task { await GLMOCREngine.unload() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            LibraryView()
                .safeAreaInset(edge: .top, spacing: 0) { UpdateBanner() }
        }
        .task { AppUpdate.shared.checkAtLaunch(); MorphologyService.shared.loadIfInstalled() }
        .fullScreenCover(item: Binding(
            get: { model.openDocumentId.flatMap { id in model.documents.first { $0.id == id } } },
            set: { model.openDocumentId = $0?.id }
        )) { document in
            ReaderScreen(document: document, model: model)
                .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review)
                .preferredColorScheme(.dark)
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
