// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Sélecteur de l'app Fichiers. `asCopy: true` : le système télécharge d'abord les fichiers
/// « en ligne seulement » (Google Drive, iCloud…) puis nous donne une copie locale complète.
struct DocumentPicker: UIViewControllerRepresentable {
    /// PDF d'office ; images pour « Images vers PDF » ; paquet Kyōkasho (un seul fichier).
    var types: [UTType] = [.pdf]
    /// Comics, déclaré dans `Info.plist` : .cbz seulement, pas tout fichier ZIP.
    static let comicArchive = UTType(importedAs: "fr.noxygen59.kyokasho.cbz")
    var multiple = true
    /// `false` : ouvrir sur place (dossier de sauvegarde gardé par signet) au lieu d'une copie dans l'app.
    var asCopy = true
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: asCopy)
        picker.allowsMultipleSelection = multiple
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

/// Fichier choisi gardé tout de suite dans un dossier privé de l'app (`tmp/Picked-<UUID>/`). Sur Mac (Catalyst), la
/// copie que donne le sélecteur peut disparaître dès qu'il se ferme, avant qu'une tâche asynchrone ne la lise : l'import
/// d'un paquet échouait sans rien dire (essai du 29/10/2026). Au propriétaire de l'effacer après usage (`discard`).
enum PickedFile {
    static func keep(_ url: URL) -> URL? {
        // Déjà une copie privée (ex. passée par `documentPicker` sur Mac) : la garder telle quelle.
        if url.deletingLastPathComponent().lastPathComponent.hasPrefix("Picked-") { return url }
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("Picked-\(UUID().uuidString)", isDirectory: true)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(url.lastPathComponent)
            try fm.copyItem(at: url, to: copy)
            return copy
        } catch {
            Diagnostics.error("fichier choisi non copié : \(error.localizedDescription)", "import")
            try? fm.removeItem(at: folder)
            return nil
        }
    }

    static func discard(_ url: URL) {
        let folder = url.deletingLastPathComponent()
        guard folder.lastPathComponent.hasPrefix("Picked-") else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}

extension View {
    /// Choix de fichiers ou d'un dossier, pour toute l'app. iPad : le sélecteur d'iOS dans une feuille (inchangé, validé
    /// en recette). Mac (Catalyst, #55) : ce sélecteur ne rend jamais les fichiers choisis à l'app (essai du
    /// 29/10/2026 : import de PDF, de paquet et restauration impossibles) ; on passe par le sélecteur natif de SwiftUI
    /// (`fileImporter`). Ses fichiers sont les originaux : avec `asCopy`, ils sont d'abord copiés dans un dossier
    /// privé (`PickedFile`), pour que rien de la suite (import qui efface sa copie de passage) ne touche à l'original.
    @ViewBuilder
    func documentPicker(isPresented: Binding<Bool>, types: [UTType] = [.pdf], multiple: Bool = true, asCopy: Bool = true,
                        onPick: @escaping ([URL]) -> Void) -> some View {
        #if targetEnvironment(macCatalyst)
        fileImporter(isPresented: isPresented, allowedContentTypes: types, allowsMultipleSelection: multiple) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            onPick(asCopy ? urls.compactMap(PickedFile.keep) : urls)
        }
        #else
        sheet(isPresented: isPresented) {
            DocumentPicker(types: types, multiple: multiple, asCopy: asCopy, onPick: onPick).ignoresSafeArea()
        }
        #endif
    }
}
