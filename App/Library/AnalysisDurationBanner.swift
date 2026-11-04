// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import SwiftUI

/// Avertissement en haut de la bibliothèque tant qu'OvisOCR2 lit des pages (demande de NOxygen59, 04/11/2026) : une lecture
/// est longue et fait chauffer l'appareil, et rien d'autre ne le disait une fois l'analyse lancée. Masquable pour cette
/// lecture ; il revient à la lecture suivante.
struct AnalysisDurationBanner: View {
    @ObservedObject private var analysis = DocumentAnalysisService.shared
    @ObservedObject private var center = AITaskCenter.shared
    @State private var dismissed = false

    private var ovisIsReading: Bool {
        analysis.progress?.phase == String(localized: "Lecture OvisOCR2")
            || center.jobs.contains { $0.modelId == ModelSpec.ovisocr2.id }
    }

    var body: some View {
        Group {
            if ovisIsReading, !dismissed {
                HStack(spacing: 12) {
                    Image(systemName: "hourglass").font(Atelier.font(22)).foregroundStyle(Atelier.Tint.ai)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lecture OvisOCR2 en cours : ça va prendre beaucoup de temps").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Atelier.textPrimary)
                        #if targetEnvironment(macCatalyst)
                        Text("Compte plusieurs minutes par page sur un Mac Intel. Le processeur tourne à fond et les ventilateurs s'entendent : c'est normal. Pour arrêter, touche la pastille OvisOCR2 en bas à gauche.")
                            .font(.footnote).foregroundStyle(Atelier.textSecondary)
                        #else
                        Text("Un livre entier peut prendre des heures et l'iPad chauffe : c'est normal. Branche-le et laisse l'app ouverte. Pour arrêter, touche la pastille OvisOCR2 en bas à gauche.")
                            .font(.footnote).foregroundStyle(Atelier.textSecondary)
                        #endif
                    }
                    Spacer()
                    Button("Masquer") { dismissed = true }
                        .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .atelierPanel()
                .padding(.horizontal, Atelier.gap).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: ovisIsReading)
        .onChange(of: ovisIsReading) { reading in if !reading { dismissed = false } }
    }
}
