// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import ReaderCore
import SwiftUI
import UIKit

/// Relevé de batterie (#20) : un échantillon par minute et à chaque changement de niveau, seulement si
/// l'utilisateur l'allume (Réglages → Aide au diagnostic). Rien n'est mesuré app suspendue : iOS arrête le minuteur,
/// et le résumé ignore ces trous. Le fichier reste sur l'iPad (Fichiers → Kyōkasho → Diagnostics → energie.csv).
///
/// Depuis le 10/11/2026, chaque ligne dit aussi **pourquoi** la minute coûte cher : processeur de l'app, écran allumé,
/// état thermique en clair, teinte de page, modèles IA en mémoire, tâches IA, document (8 caractères d'identifiant au
/// plus) et version. Jamais un titre de document, un texte de page ni une note : le fichier peut être partagé.
@MainActor
final class EnergyMeter {
    static let shared = EnergyMeter()
    /// Clé du réglage, lisible hors du fil principal (journal de diagnostic, bannière).
    nonisolated static let enabledKey = "energy.enabled"

    private weak var model: AppModel?
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    /// Relevé précédent : sert au pourcentage de processeur depuis la dernière ligne. `nil` au lancement, et le temps
    /// de calcul cumulé qui repart de zéro est détecté par `EnergyLog.cpuPercent`.
    private var previous: EnergySample?

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
        previous = nil
        UIDevice.current.isBatteryMonitoringEnabled = on
        guard on else { return }
        Task { await record() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in Task { @MainActor in await EnergyMeter.shared.record() } }
        observer = NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await EnergyMeter.shared.record() }
        }
    }

    /// Ce que fait l'app en ce moment ; plusieurs activités simultanées sont réunies dans un seul libellé.
    ///
    /// Les titres des tâches IA contiennent le titre du livre (« Lecture IA de « … » ») : ils ne sont donc pas repris
    /// ici, seulement le nom du modèle ou le type d'action.
    private func activity() -> String {
        var parts: [String] = []
        let models = Set(AITaskCenter.shared.jobs.map { $0.modelId.map(AITaskCenter.modelName) ?? "IA" }).sorted()
        if !models.isEmpty { parts.append("IA : " + models.joined(separator: " + ")) }
        if DocumentAnalysisService.shared.progress != nil { parts.append("Analyse du document") }
        if parts.isEmpty { parts.append(model?.openDocumentId != nil ? "Lecture" : "Bibliothèque ou réglages") }
        return parts.joined(separator: " · ")
    }

    /// Types d'action des tâches IA en cours (« lecture », « vérification »…), sans titre de document.
    private var aiTasks: String {
        AITaskCenter.shared.jobs.compactMap(\.activity).sorted().joined(separator: "+")
    }

    /// Modèles d'IA tenus en mémoire (colonne `ia_chargees`). Un seul modèle MLX est chargé à la fois ; les moteurs
    /// ONNX (Vision, PP-OCR, NDLOCR) ne sont pas listés ici.
    private func loadedModels(_ status: AIModelStatus) -> String {
        guard let loaded = status.loaded else { return "" }
        let specs: [(ModelSpec, String)] = [(.ovisocr2, "OvisOCR2"), (.glmocr, "GLM-OCR"),
                                            (.qwen3vl4b, "Qwen3-VL"), (.qwen35chat4b, "Qwen3.5")]
            + LocalModels.specs().map { ($0, $0.title) }   // modèles importés (PLAN-MODLOC-001, E3)
        return specs.filter { ModelStore.shared.directory($0.0) == loaded }.map(\.1).joined(separator: "+")
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    private func record() async {
        let device = UIDevice.current
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var sample = EnergySample(date: Date(), battery: Double(device.batteryLevel),
                                  charging: device.batteryState == .charging || device.batteryState == .full,
                                  thermal: ProcessInfo.processInfo.thermalState.rawValue,
                                  lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                  brightness: Double(UIScreen.main.brightness), cpuSeconds: cpu,
                                  memoryMB: Diagnostics.footprintMB(), activity: activity())
        sample.cpuPercent = EnergyLog.cpuPercent(previous: previous, sample)
        sample.screen = UIApplication.shared.applicationState == .active ? .active : .background
        sample.tone = model?.openDocumentId == nil ? "" : PageTone.current.rawValue
        sample.aiTasks = aiTasks
        // 8 caractères au plus, et rien hors du lecteur : ce fichier peut être partagé.
        sample.document = model?.openDocumentId.map { String($0.prefix(EnergyLog.documentPrefix)) } ?? ""
        sample.appVersion = Self.version
        sample.loadedModels = loadedModels(await GLMOCREngine.status())
        previous = sample
        EnergyFile.append(EnergyLog.line(sample))
    }
}

/// Fichier du relevé, lu et écrit sur une seule file (jamais une lecture pendant une rotation), hors du fil principal.
enum EnergyFile {
    static var url: URL { Diagnostics.folder.appendingPathComponent("energie.csv") }
    private static let queue = DispatchQueue(label: "fr.noxygen59.kyokasho.energy")
    /// Au-delà, la seconde moitié est gardée (la ligne coupée est ignorée à la lecture). Réglé **au-dessus** du seuil
    /// d'alerte de 1 Mo (`DiagnosticFiles.energyRotationBytes`) : autrement, la bannière de taille ne resterait jamais.
    private static let limit = DiagnosticFiles.energyRotationBytes

    static func append(_ line: String) {
        let file = url
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue, size > limit,
               let data = try? Data(contentsOf: file) {
                // Trop gros : on garde la seconde moitié, à partir du début d'une ligne (`EnergyLog.rotated`).
                try? EnergyLog.rotated(data, keeping: limit / 2).write(to: file)
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
        queue.sync { EnergyLog.parse((try? Data(contentsOf: url)) ?? Data()) }
    }

    static func erase() {
        queue.sync { try? FileManager.default.removeItem(at: url) }
    }
}

/// Résumé du relevé : combien chaque activité coûte en batterie, par activité, par tranche de luminosité et par
/// session sur batterie (demandes du 10/11/2026 : l'activité seule ne disait pas ce qui coûtait cher).
struct EnergySummaryView: View {
    /// Tout est calculé hors du fil principal à la présentation : douze jours de relevé font des dizaines de milliers
    /// de lignes, et le résumé se refait à chaque ouverture.
    private struct Report: Equatable {
        var count: Int
        var activities: [EnergyLog.Row]
        var bands: [EnergyLog.BandRow]
        var sessions: [EnergyLog.Session]
    }

    @Environment(\.dismiss) private var dismiss
    @State private var report: Report?

    var body: some View {
        NavigationStack {
            List {
                if let report {
                    if report.activities.isEmpty {
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
                        ForEach(report.activities, id: \.activity) { row in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ui: row.activity).font(.subheadline.weight(.semibold))
                                Text(details(row)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Par activité")
                    } footer: {
                        Text("\(report.count) mesures. Seules les périodes sur batterie comptent ; le débit s'affiche après 10 minutes d'une même activité. CPU : 100 % = un cœur occupé en continu ; le GPU (IA locale) se voit dans la batterie et la chaleur.")
                    }
                    if !report.bands.isEmpty {
                        Section {
                            ForEach(report.bands, id: \.band) { row in
                                HStack {
                                    Text(row.band.title).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(bandDetails(row)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } header: {
                            Text("Par luminosité")
                        } footer: {
                            Text("Luminosité de l'écran au moment de la mesure. C'est le plus souvent elle qui explique une consommation forte : compare les tranches à activité égale.")
                        }
                    }
                    if !report.sessions.isEmpty {
                        Section {
                            ForEach(report.sessions) { session in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sessionTitle(session)).font(.subheadline.weight(.semibold))
                                    Text(sessionDetails(session)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } header: {
                            Text("Sessions sur batterie")
                        } footer: {
                            Text("Une session s'arrête à la mise en charge, à une suspension de l'app et à un saut de mesure. Les 30 plus récentes sont affichées.")
                        }
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
                report = await Task.detached(priority: .userInitiated) {
                    Report(count: samples.count, activities: EnergyLog.summary(samples),
                           bands: EnergyLog.brightnessSummary(samples),
                           sessions: Array(EnergyLog.sessions(samples).prefix(30)))
                }.value
            }
        }
    }

    private func rate(_ value: Double?) -> String {
        value.map { String(format: String(localized: "%.0f %% de batterie par heure"), $0) } ?? String(localized: "durée trop courte pour la batterie")
    }

    private func details(_ row: EnergyLog.Row) -> String {
        let minutes = Int(row.seconds / 60)
        return String(localized: "\(minutes) min · \(rate(row.batteryPerHour)) · CPU \(Int(row.cpuPercent)) % · chaleur \(EnergyLog.thermalName(row.maxThermal))")
    }

    private func bandDetails(_ row: EnergyLog.BandRow) -> String {
        let minutes = Int(row.seconds / 60)
        return String(localized: "\(minutes) min · \(rate(row.batteryPerHour)) · CPU \(Int(row.cpuPercent)) %")
    }

    private func sessionTitle(_ session: EnergyLog.Session) -> String {
        let start = session.start.formatted(date: .abbreviated, time: .shortened)
        let end = session.end.formatted(date: .omitted, time: .shortened)
        return "\(start) → \(end)"
    }

    private func sessionDetails(_ session: EnergyLog.Session) -> String {
        let minutes = Int(session.seconds / 60)
        let lost = String(format: "%.0f", session.lostPoints)
        return String(localized: "\(minutes) min · \(lost) points de batterie · \(rate(session.batteryPerHour)) · luminosité \(Int((session.brightness * 100).rounded())) % · \(session.activity)")
    }
}
