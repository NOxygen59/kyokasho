// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI
import UIKit

/// Fenêtre de partage d'iOS pour un fichier déjà écrit sur disque (AirDrop, Mail, Fichiers, apps de notes).
/// Présentée dans une feuille SwiftUI : sur l'iPad, pas de popover à ancrer.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Adresse partageable par `.sheet(item:)`.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
