// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI
import UIKit

@main
struct KyokashoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
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
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            LibraryView()
        }
        .fullScreenCover(item: Binding(
            get: { model.openDocumentId.flatMap { id in model.documents.first { $0.id == id } } },
            set: { model.openDocumentId = $0?.id }
        )) { document in
            ReaderScreen(document: document, model: model)
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Atelier.Tint.read)
        }
        .alert("Erreur", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }
}
