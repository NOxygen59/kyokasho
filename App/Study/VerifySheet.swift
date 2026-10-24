// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import SwiftUI

/// « Vérifier la double page » : OvisOCR2 relit les pages affichées ; chaque ligne qui diffère est proposée,
/// à accepter ou refuser. Rien ne change sans accord.
struct VerifySheet: View {
    @ObservedObject var reader: ReaderController
    @Environment(\.dismiss) private var dismiss
    /// Arrêt : deux confirmations (la lecture coûte des minutes).
    @State private var confirmStop = false
    @State private var confirmStopAgain = false

    var body: some View {
        NavigationStack {
            List {
                switch reader.verifyState {
                case .running(let done, let total):
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("OvisOCR2 lit la page \(done + 1) sur \(total)… (quelques dizaines de secondes par page)")
                                .font(.footnote)
                        }
                        Button("Arrêter", role: .destructive) { confirmStop = true }
                    }
                case .done where reader.verifications.allSatisfy({ $0.suggestions.isEmpty && $0.error == nil }):
                    Section { Label("Aucune différence : OvisOCR2 lit la même chose.", systemImage: "checkmark.seal") }
                default:
                    EmptyView()
                }
                ForEach(reader.verifications) { page in
                    Section {
                        if let error = page.error { Text(error).font(.footnote).foregroundStyle(.red) }
                        ForEach(page.suggestions) { s in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(s.current).font(Atelier.jp).foregroundStyle(.secondary).strikethrough(color: .red.opacity(0.6))
                                Text(s.proposed).font(Atelier.jp)
                                HStack {
                                    Button("Accepter") { reader.acceptSuggestions([s], source: page.source) }
                                        .buttonStyle(.borderedProminent).tint(Atelier.Tint.ai)
                                    Button("Refuser") { reader.dropSuggestion(s, source: page.source) }
                                        .buttonStyle(.bordered)
                                }
                                .font(.footnote)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        HStack {
                            Text("Page \(reader.document.pageLabel(page.source)) · \(page.suggestions.count) différence\(page.suggestions.count > 1 ? "s" : "")")
                            Spacer()
                            if page.suggestions.count > 1 {
                                Button("Tout accepter") { reader.acceptSuggestions(page.suggestions, source: page.source) }
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Vérification (OvisOCR2)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { reader.verifyShownPages(force: true) } label: {
                        Label("Relire avec OvisOCR2", systemImage: "arrow.clockwise")
                    }
                    .disabled(AITaskCenter.shared.isRunning(reader.verifyKey))
                }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .alert("Arrêter la vérification ?", isPresented: $confirmStop) {
                Button("Continuer", role: .cancel) {}
                Button("Arrêter", role: .destructive) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { confirmStopAgain = true }
                }
            } message: {
                Text("Elle continue même si tu fermes cette fenêtre ou changes de page.")
            }
            .alert("Vraiment arrêter ?", isPresented: $confirmStopAgain) {
                Button("Non, continuer", role: .cancel) {}
                Button("Oui, arrêter", role: .destructive) { reader.cancelVerification() }
            }
        }
    }
}
