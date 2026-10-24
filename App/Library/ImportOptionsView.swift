// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import SwiftUI

/// Choix de la langue avant l'import et la lecture OvisOCR2 automatique.
struct ImportOptionsView: View {
    let onImport: ([URL], OCRTargetLanguage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var language: OCRTargetLanguage = .japanese
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Langue du document", selection: $language) {
                        ForEach(OCRTargetLanguage.allCases, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                } footer: {
                    Text("La lecture IA privilégie cette langue. Les chiffres, lettres latines et formules restent tels qu'ils figurent sur la page. Le japonais est conseillé pour les manuels japonais.")
                }
                Section {
                    Button { showPicker = true } label: {
                        Label("Choisir des PDF", systemImage: "doc.badge.plus")
                    }
                }
            }
            .navigationTitle("Importer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
            .sheet(isPresented: $showPicker) {
                DocumentPicker { urls in
                    guard !urls.isEmpty else { return }
                    onImport(urls, language)
                    dismiss()
                }
                .ignoresSafeArea()
            }
        }
    }
}
