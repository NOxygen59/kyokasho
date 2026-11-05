// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import SwiftUI

/// Choix de la langue avant l'import et la lecture OvisOCR2 automatique.
struct ImportOptionsView: View {
    let onImport: ([URL], OCRTargetLanguage) -> Void
    /// Paquet Kyōkasho choisi (document complet exporté depuis un autre appareil).
    var onPackage: ((URL) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var language: OCRTargetLanguage = .japanese
    @State private var showPicker = false
    @State private var showPackagePicker = false

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
                } footer: {
                    Text("Mangas et magazines .cbz acceptés, à titre expérimental : lecture d'immersion, images seules, sans OCR ni IA.")
                }
                if onPackage != nil {
                    Section {
                        Button { showPackagePicker = true } label: {
                            Label("Importer un paquet Kyōkasho (.kyokasho)", systemImage: "shippingbox")
                        }
                    } footer: {
                        Text("Un document exporté « en entier » depuis Kyōkasho : il revient avec ses notes, OCR, lectures IA, traductions et analyse, sans rien relancer.")
                    }
                }
            }
            .navigationTitle("Importer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
            .sheet(isPresented: $showPicker) {
                DocumentPicker(types: [.pdf, DocumentPicker.comicArchive]) { urls in
                    guard !urls.isEmpty else { return }
                    onImport(urls, language)
                    dismiss()
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showPackagePicker) {
                DocumentPicker(types: [DocumentPackageService.contentType, .zip, .data], multiple: false) { urls in
                    guard let url = urls.first else { return }
                    onPackage?(url)
                    dismiss()
                }
                .ignoresSafeArea()
            }
        }
    }
}
