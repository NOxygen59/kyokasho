// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import ReaderCore
import SwiftUI

/// Carte de l'accueil sur la consommation de l'IA locale (RET-018, #21) ; règle d'affichage : ``LocalAIEnergyNotice``.
struct LocalAIEnergyCard: View {
    static let acknowledgedKey = "ai.energyNoticeAcknowledged"

    @AppStorage(LocalAIEnergyCard.acknowledgedKey) private var acknowledged = false
    @ObservedObject private var center = AITaskCenter.shared
    @ObservedObject private var analysis = DocumentAnalysisService.shared
    @State private var onBattery = false

    /// Modèles MLX (lourds) ; les moteurs ONNX légers ne comptent pas.
    private var modelInstalled: Bool {
        [ModelSpec.glmocr, .ovisocr2, .qwen3vl4b, .qwen35chat].contains { ModelStore.shared.isInstalled($0) }
    }

    private var state: LocalAIEnergyNotice {
        LocalAIEnergyNotice.state(modelInstalled: modelInstalled, acknowledged: acknowledged,
                                  aiActive: !center.jobs.isEmpty || analysis.progress != nil, onBattery: onBattery)
    }

    var body: some View {
        Group {
            switch state {
            case .hidden:
                EmptyView()
            case .general:
                VStack(alignment: .leading, spacing: 6) {
                    Label("IA locale et batterie", systemImage: "bolt.batteryblock")
                        .font(Atelier.font(13, weight: .semibold)).foregroundStyle(Atelier.Tint.ai)
                    Text("Les modèles d'IA locaux (OvisOCR2, GLM-OCR, Qwen) font travailler la puce à plein : la batterie baisse vite et l'iPad chauffe. Branche-le pour les longues analyses.")
                        .font(Atelier.font(12)).foregroundStyle(Atelier.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Compris") { acknowledged = true }
                        .font(Atelier.font(12, weight: .semibold))
                }
                .padding(12)
                .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.corner(14), style: .continuous))
            case .activeOnBattery:
                Label("IA locale en cours sur batterie", systemImage: "bolt.batteryblock")
                    .font(Atelier.font(12, weight: .semibold)).foregroundStyle(Atelier.Tint.ai)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.corner(14), style: .continuous))
                    .accessibilityHint("La batterie baisse vite pendant ce travail")
            }
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            updateBattery()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            updateBattery()
        }
    }

    private func updateBattery() {
        onBattery = UIDevice.current.batteryState == .unplugged
    }
}
