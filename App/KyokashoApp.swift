// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import ONNXOCRKit
import ReaderCore
import SwiftUI
import UserNotifications
import UIKit

@main
struct KyokashoApp: App {
    init() {
        // PLAN-NOTIF-001 E4 : posé au lancement, pour qu'une notification touchée app fermée ne soit pas perdue.
        UNUserNotificationCenter.current().delegate = NoteNotificationDelegate.shared
        // Avant tout : journal de diagnostic et gestionnaire d'erreurs MLX (message noté avant un arrêt).
        Diagnostics.start()
        // PLAN-DIAG-001 E2a : session du processus (constat « non clôturée » du lancement précédent, puis suivi).
        DiagnosticSessionController.shared.install()
        // PLAN-DIAG-001 E2f : MetricKit seulement si l'essai a été allumé dans Réglages › Diagnostic.
        DiagnosticMetricKit.apply()
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
                .preferredColorScheme(themes.effectiveTheme.colorScheme)
                .environment(\.themeRevision, themes.effectiveRevision)
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
                .onAppear {
                    // PLAN-DIAG-001 E2c : un seul observateur de la pression mémoire pour le processus (et non un par
                    // fenêtre) ; empreinte relevée avant les libérations, qui restent les mêmes, une fois par alerte.
                    DiagnosticSessionController.shared.installMemoryObserver { [weak model] in
                        model?.thumbnails.trim()
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
}

struct RootView: View {
    @EnvironmentObject private var themes: ThemeManager

    @EnvironmentObject private var model: AppModel
    @ObservedObject private var dictionaryUpdates = DictionaryCatalogService.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var retryingStorage = false
    /// N4 (revue R2) : confirmation avant de mettre un journal refusé de côté.
    @State private var confirmingAside = false

    private var showsReader: Bool {
        guard model.storageRecoveryError == nil, let id = model.openDocumentId else { return false }
        return model.documents.contains { $0.id == id }
    }

    var body: some View {
        Group {
            if let error = model.storageRecoveryError {
                VStack(spacing: 20) {
                    Text("Reprise des données nécessaire").font(.title2)
                    Text(error)
                    // Restauration inachevée (#51) : seule une relance peut la reprendre, avant l'ouverture des bases.
                    if !LibraryBackupService.restoreBlocked {
                        Button("Réessayer la reprise") {
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
                        }.disabled(retryingStorage)
                        // N4 (revue R2) : un journal refusé (altéré, incohérent, incomplet) rejoue
                        // le même refus à chaque « Réessayer » — une seule action était une impasse.
                        // Le journal peut être mis de côté (déplacé, jamais effacé) et l'app démarre.
                        Button("Mettre le journal de côté et repartir", role: .destructive) {
                            confirmingAside = true
                        }
                        .disabled(retryingStorage)
                        .confirmationDialog("Mettre ce journal de côté ?", isPresented: $confirmingAside,
                                            titleVisibility: .visible) {
                            Button("Mettre de côté", role: .destructive) { PageShift.setAsideRejectedJournal(model) }
                            Button("Annuler", role: .cancel) {}
                        } message: {
                            Text("L'app redémarre sans rejouer la reprise. Le journal est déplacé dans « Conflits-remplacement/journaux-refusés » : rien n'est effacé.")
                        }
                    }
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
        .allowsHitTesting(!showsReader)
        .accessibilityHidden(showsReader)
        .task { AppUpdate.shared.checkAtLaunch(); MorphologyService.shared.loadIfInstalled(); EnergyMeter.shared.attach(model) }
        .overlay {
            // Différer visite et nouveautés pendant la lecture sans démonter la bibliothèque.
            if !showsReader {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .modifier(IntroPresenter(hasLibrary: { [model] in !model.documents.isEmpty }))
            }
        }
        .overlay {
            ZStack {
                // Pile gardée en place : le calque s'insère dedans sans transition propre (fondu géré par `ReaderReveal`).
                Color.clear.allowsHitTesting(false).accessibilityHidden(true)
                // Un seul calque pour tous les onglets (#16), indépendant des présentations iOS (#93).
                if showsReader {
                    ReaderTabsHost()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Le fond couvre les zones sûres, les commandes gardent leurs marges et le clavier.
                        .background(Atelier.canvas.ignoresSafeArea())
                        .environmentObject(model).environmentObject(model.dictionary).environmentObject(model.review)
                        .environment(\.themeRevision, themes.effectiveRevision)
                        .atelierFontDesign()
                        .tint(Atelier.Tint.read)
                        // Recette 1.6.1 (1.2, 1.3) : fondu lancé une fois le PDF posé, rien si « Réduire les animations ».
                        .modifier(ReaderReveal(reduceMotion: reduceMotion))
                        // Retrait immédiat : le lecteur rend sa mémoire sans attendre la fin d'un fondu.
                        .transition(.identity)
                        .zIndex(1)
                }
            }
        }
        // Permanente et non fermable : un seul ancrage, au-dessus des bannières propres à chaque écran.
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.storageRecoveryError == nil {
                DiagnosticSizeBanner()
            }
        }
        .onAppear {
            model.themeManager = themes
            themes.showDocument(in: model.activeDocumentSpace)
        }
        .onChange(of: model.activeDocumentSpace) { themes.showDocument(in: $0) }
        // Retour à la bibliothèque ou app en arrière-plan : les IA rendent leur mémoire.
        .onChange(of: model.openDocumentId) { if $0 == nil { Self.releaseAI() } }
        .onChange(of: scenePhase) { phase in
            if phase == .background { Self.releaseAI() }
            // Au retour dans l'app : la connexion a pu revenir ou un jour être passé (`DictionaryUpdateSchedule`).
            // Rappels de notes reprogrammés au retour (un jour a pu passer).
            if phase == .active { model.refreshNotesToReview() }
            if phase == .active, !LibraryBackupService.inProgress {
                Task { await dictionaryUpdates.checkAutomaticallyIfDue(model: model.dictionary) }
            }
        }
        .onAppear { NoteNotificationDelegate.shared.model = model }
        .task {
            // Après le chargement de la bibliothèque, et jamais par-dessus une sauvegarde en cours.
            guard !LibraryBackupService.inProgress else { return }
            await dictionaryUpdates.checkAutomaticallyIfDue(model: model.dictionary, atLaunch: true)
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
            Diagnostics.error("fenêtre Mac : \(Diagnostics.describe(error))", "app")
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        restrictions.minimumSize = minimum
        restrictions.maximumSize = maximum
    }
}
#endif
