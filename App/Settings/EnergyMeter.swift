// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI
import UIKit

/// Relevé de batterie (#20) : un échantillon par minute et à chaque changement de niveau, seulement si
/// l'utilisateur l'allume (Réglages → Aide au diagnostic). Rien n'est mesuré app suspendue : iOS arrête le minuteur,
/// et le résumé ignore ces trous. Le fichier reste sur l'iPad (Fichiers → Kyōkasho → Diagnostics → energie.csv).
@MainActor
final class EnergyMeter {
    static let shared = EnergyMeter()
    static let enabledKey = "energy.enabled"

    private weak var model: AppModel?
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    /// Au lancement : reprend le relevé s'il était allumé.
    func attach(_ model: AppModel) {
        self.model = model
        setEnabled(UserDefaults.standard.bool(forKey: Self.enabledKey))
    }

    func setEnabled(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        UIDevice.current.isBatteryMonitoringEnabled = on
        guard on else { return }
        record()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in Task { @MainActor in EnergyMeter.shared.record() } }
        observer = NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in EnergyMeter.shared.record() }
        }
    }

    /// Ce que fait l'app en ce moment ; plusieurs activités simultanées sont réunies dans un seul libellé.
    private func activity() -> String {
        var parts: [String] = []
        let models = Set(AITaskCenter.shared.jobs.map { $0.modelId.map(AITaskCenter.modelName) ?? $0.title }).sorted()
        if !models.isEmpty { parts.append("IA : " + models.joined(separator: " + ")) }
        if DocumentAnalysisService.shared.progress != nil { parts.append("Analyse du document") }
        if parts.isEmpty { parts.append(model?.openDocumentId != nil ? "Lecture" : "Bibliothèque ou réglages") }
        return parts.joined(separator: " · ")
    }

    private func record() {
        let device = UIDevice.current
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let sample = EnergySample(date: Date(), battery: Double(device.batteryLevel),
                                  charging: device.batteryState == .charging || device.batteryState == .full,
                                  thermal: ProcessInfo.processInfo.thermalState.rawValue,
                                  lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                  brightness: Double(UIScreen.main.brightness), cpuSeconds: cpu,
                                  memoryMB: Diagnostics.footprintMB(), activity: activity())
        EnergyFile.append(EnergyLog.line(sample))
    }
}

/// Fichier du relevé, lu et écrit sur une seule file (jamais une lecture pendant une rotation), hors du fil principal.
enum EnergyFile {
    static var url: URL { Diagnostics.folder.appendingPathComponent("energie.csv") }
    private static let queue = DispatchQueue(label: "fr.noxygen59.kyokasho.energy")
    private static let limit = 1_000_000

    static func append(_ line: String) {
        let file = url
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue, size > limit,
               let data = try? Data(contentsOf: file) {
                // Trop gros : on garde la seconde moitié (la ligne coupée est ignorée à la lecture).
                try? (Data((EnergyLog.header + "\n").utf8) + data.suffix(limit / 2)).write(to: file)
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(Data((line + "\n").utf8))
                try? handle.close()
            } else {
                try? Data((EnergyLog.header + "\n" + line + "\n").utf8).write(to: file)
            }
        }
    }

    static func samples() -> [EnergySample] {
        queue.sync { EnergyLog.parse((try? String(contentsOf: url, encoding: .utf8)) ?? "") }
    }

    static func erase() {
        queue.sync { try? FileManager.default.removeItem(at: url) }
    }
}

/// Résumé du relevé : combien chaque activité coûte en batterie.
struct EnergySummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [EnergyLog.Row]?
    @State private var count = 0

    var body: some View {
        NavigationStack {
            List {
                if let rows {
                    if rows.isEmpty {
                        Group {
                            #if targetEnvironment(macCatalyst)
                            Text("Pas encore assez de mesures sur batterie. Laisse le relevé allumé, MacBook débranché, au moins 10 minutes par activité.")
                            #else
                            Text("Pas encore assez de mesures sur batterie. Laisse le relevé allumé, iPad débranché, au moins 10 minutes par activité.")
                            #endif
                        }
                        .foregroundStyle(.secondary)
                    }
                    Section {
                        ForEach(rows, id: \.activity) { row in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ui: row.activity).font(.subheadline.weight(.semibold))
                                Text(details(row)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text("\(count) mesures. Seules les périodes sur batterie comptent ; le débit s'affiche après 10 minutes d'une même activité. CPU : 100 % = un cœur occupé en continu ; le GPU (IA locale) se voit dans la batterie et la chaleur.")
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Relevé de batterie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: EnergyFile.url) { Label("Partager", systemImage: "square.and.arrow.up") }
                }
            }
            .task {
                let samples = await Task.detached { EnergyFile.samples() }.value
                count = samples.count
                rows = EnergyLog.summary(samples)
            }
        }
    }

    private func details(_ row: EnergyLog.Row) -> String {
        let minutes = Int(row.seconds / 60)
        let battery = row.batteryPerHour.map { String(format: String(localized: "%.0f %% de batterie par heure"), $0) } ?? String(localized: "durée trop courte pour la batterie")
        return String(localized: "\(minutes) min · \(battery) · CPU \(Int(row.cpuPercent)) % · chaleur \(EnergyLog.thermalName(row.maxThermal))")
    }
}
