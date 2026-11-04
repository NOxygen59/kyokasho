// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Langue de l'interface : « AppleLanguages » propre à l'app, appliquée au relancement comme le prévoit iOS.
/// Vide = langue du système. Le chinois est réservé à la version Mac (décision de NOxygen59 du 04/11/2026).
struct AppLanguagePicker: View {
    @State private var language = Self.stored
    @State private var changed = false

    private static var stored: String {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let first = (domain?["AppleLanguages"] as? [String])?.first else { return "" }
        #if targetEnvironment(macCatalyst)
        return first.hasPrefix("zh") ? "zh-Hans" : first.hasPrefix("en") ? "en" : "fr"
        #else
        return first.hasPrefix("en") ? "en" : "fr"
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Langue de l'app", selection: $language) {
                Text("Système").tag("")
                Text("Français").tag("fr")
                Text("English").tag("en")
                #if targetEnvironment(macCatalyst)
                Text("简体中文").tag("zh-Hans")
                #endif
            }
            .pickerStyle(.segmented)
            .onChange(of: language) { value in
                if value.isEmpty { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
                else { UserDefaults.standard.set([value], forKey: "AppleLanguages") }
                changed = true
            }
            if changed {
                Text("Relance l'app pour appliquer la langue (ferme-la puis rouvre-la).")
                    .font(.footnote).foregroundStyle(Atelier.textSecondary)
                // Sur Mac, fermer la fenêtre ne quitte pas l'app, d'où ce bouton (essai du 30/10/2026).
                Button("Quitter pour appliquer") { exit(0) }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
            }
        }
    }
}
