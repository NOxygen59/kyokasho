// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Sélecteur de l'app Fichiers. `asCopy: true` : le système télécharge d'abord les fichiers
/// « en ligne seulement » (Google Drive, iCloud…) puis nous donne une copie locale complète.
struct DocumentPicker: UIViewControllerRepresentable {
    /// PDF d'office ; images pour « Images vers PDF ».
    var types: [UTType] = [.pdf]
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
