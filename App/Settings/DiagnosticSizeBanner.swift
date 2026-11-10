// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Bannière de taille des fichiers de diagnostic (demande du 10/11/2026) : dès que le journal dépasse 1,5 Mo ou le
/// relevé 1 Mo, elle reste affichée dans la bibliothèque **et** dans le lecteur, sans croix pour la fermer. Elle
/// disparaît d'elle-même dès que les deux fichiers repassent sous les seuils (bouton « Effacer » de l'aide au
/// diagnostic) : c'est `DiagnosticFiles.warning`, fonction pure testée, qui décide, et cette vue ne fait qu'afficher.
///
/// Les tailles sont relues à l'apparition, au retour dans l'app et après un effacement : rien ne tourne en fond.
struct DiagnosticSizeBanner: View {
    @State private var warning: DiagnosticFiles.Warning?
    @State private var showHelp = false
    @Environment(\.scenePhase) private var scenePhase
    /// Lu pour être redessiné quand la palette change, comme les autres bannières de la bibliothèque.
    @Environment(\.themeRevision) private var themeRevision

    var body: some View {
        let _ = themeRevision
        Group {
            if let warning {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(Atelier.font(22)).foregroundStyle(Atelier.Tint.annotate)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fichiers de diagnostic volumineux (\(sizeText(warning)) Mo) : partage-les puis efface-les.")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Atelier.textPrimary)
                        Text("Le journal et le relevé de batterie prennent de la place. « Partager le relevé et le journal » les envoie ensemble, puis « Effacer le journal » et « Effacer le relevé » les retirent.")
                            .font(.footnote).foregroundStyle(Atelier.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Button("Aide au diagnostic") { showHelp = true }
                        .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .atelierPanel()
                .padding(.horizontal, Atelier.gap).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: warning != nil)
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { if $0 == .active { refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .diagnosticFilesChanged)) { _ in refresh() }
        .sheet(isPresented: $showHelp, onDismiss: refresh) {
            NavigationStack {
                ReaderHelpSettingsView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { showHelp = false } } }
            }
        }
    }

    /// « 1,8 » ou « 2,4 » : un chiffre après la virgule suffit pour décider d'effacer.
    private func sizeText(_ warning: DiagnosticFiles.Warning) -> String {
        String(format: "%.1f", warning.megabytes)
    }

    private func refresh() {
        let sizes = Diagnostics.diagnosticSizes()
        warning = DiagnosticFiles.warning(journalBytes: sizes.journal, energyBytes: sizes.energy)
    }
}
