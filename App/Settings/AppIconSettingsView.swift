// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI
import UIKit

/// Les noms alternatifs correspondent aux clés de `CFBundleAlternateIcons` dans Info.plist.
private enum AppIconChoice: String, CaseIterable, Identifiable {
    case ivory, navy, jade, charcoal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ivory: return String(localized: "Ivoire")
        case .navy: return String(localized: "Bleu nuit")
        case .jade: return String(localized: "Jade")
        case .charcoal: return String(localized: "Anthracite")
        }
    }

    var alternateName: String? {
        switch self {
        case .ivory: return nil
        case .navy: return "AppIconNavy"
        case .jade: return "AppIconJade"
        case .charcoal: return "AppIconCharcoal"
        }
    }

    var previewAsset: String {
        switch self {
        case .ivory: return "IconPreviewIvory"
        case .navy: return "IconPreviewNavy"
        case .jade: return "IconPreviewJade"
        case .charcoal: return "IconPreviewCharcoal"
        }
    }
}

/// Réglages → Général → Icône de l'app.
/// iPadOS affiche sa propre confirmation après un changement réussi.
struct AppIconSettingsView: View {
    @State private var currentName = UIApplication.shared.alternateIconName
    @State private var changing = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 18)]

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(AppIconChoice.allCases) { choice in
                        Button { select(choice) } label: {
                            VStack(spacing: 9) {
                                Image(choice.previewAsset)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 92, height: 92)
                                    .clipShape(RoundedRectangle(cornerRadius: Atelier.corner(21), style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        if currentName == choice.alternateName {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title2)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(Atelier.onAccentInk, Atelier.Tint.read)
                                                .background(Circle().fill(Atelier.surface))
                                                .offset(x: 5, y: -5)
                                        }
                                    }
                                Text(choice.title)
                                    .font(.subheadline.weight(currentName == choice.alternateName ? .semibold : .regular))
                                    .foregroundStyle(Atelier.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Atelier.surface, in: RoundedRectangle(cornerRadius: Atelier.corner(16)))
                            .overlay {
                                RoundedRectangle(cornerRadius: Atelier.corner(16))
                                    .stroke(currentName == choice.alternateName ? Atelier.Tint.read : Atelier.hairline,
                                            lineWidth: currentName == choice.alternateName ? 2 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(changing || currentName == choice.alternateName)
                        .accessibilityLabel("Icône \(choice.title)")
                        .accessibilityAddTraits(currentName == choice.alternateName ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Le choix ne change ni tes livres ni tes réglages. iPadOS confirme le remplacement de l'icône sur l'écran d'accueil.")
            }
        }
        .navigationTitle("Icône de l'app")
        .overlay { if changing { ProgressView().controlSize(.large) } }
        .alert("Impossible de changer l'icône", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? String(localized: "Erreur inconnue."))
        }
    }

    private func select(_ choice: AppIconChoice) {
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = String(localized: "Cette version d'iPadOS ne permet pas les icônes alternatives.")
            return
        }
        changing = true
        UIApplication.shared.setAlternateIconName(choice.alternateName) { error in
            DispatchQueue.main.async {
                changing = false
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    currentName = UIApplication.shared.alternateIconName
                }
            }
        }
    }
}
