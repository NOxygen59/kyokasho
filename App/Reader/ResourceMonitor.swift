// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Charts
import Darwin
import QuartzCore
import GLMOCRKit
import ReaderCore
import SwiftUI

/// Mesures de l'app (pas du système entier) : CPU des fils de l'app, mémoire comptée par iOS (`phys_footprint`,
/// celle qui déclenche les fermetures), images par seconde. API publiques de Mach et `CADisplayLink`.
@MainActor
final class ResourceMonitor: ObservableObject {
    static let shared = ResourceMonitor()
    static let enabledKey = "monitor.enabled"
    static let shownKey = "monitor.shown"

    struct Sample: Identifiable {
        let id: Int
        let cpu: Double
        let ramMB: Double
        let fps: Double
    }

    enum Metric: String, CaseIterable, Identifiable {
        case cpu, ram, fps
        var id: String { rawValue }
        var title: String { self == .cpu ? "CPU" : self == .ram ? "RAM" : "FPS" }
        var unit: String { self == .cpu ? "%" : self == .ram ? String(localized: "Mo") : "i/s" }
        func value(_ s: Sample) -> Double { self == .cpu ? s.cpu : self == .ram ? s.ramMB : s.fps }
    }

    @Published private(set) var samples: [Sample] = []
    /// Activités du dernier relevé. Une seule lecture du registre par seconde : un second lecteur fausserait les parts.
    @Published private(set) var activities: [ActivityLedger.Row] = []
    /// Historique du tableau de bord, relevé seulement moniteur affiché.
    private(set) var log = PerformanceLog.decode(UserDefaults.standard.data(forKey: ResourceMonitor.logKey))
    static let logKey = "stats.v2.performance"
    private var timer: Timer?
    private var link: CADisplayLink?
    private var frames = 0
    private var lastTick = CACurrentMediaTime()
    private var counter = 0
    private var users = 0

    var last: Sample? { samples.last }

    /// Démarre à la première vue qui l'affiche, s'arrête à la dernière (rien ne tourne panneau fermé).
    func start() {
        users += 1
        guard users == 1 else { return }
        // Point de départ : le travail fait moniteur fermé ne doit pas compter dans le premier relevé.
        _ = ActivityCenter.shared.snapshot()
        lastTick = CACurrentMediaTime()
        frames = 0
        let link = CADisplayLink(target: FrameCounter { [weak self] in self?.frames += 1 }, selector: #selector(FrameCounter.tick))
        link.add(to: .main, forMode: .common)
        self.link = link
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        timer?.invalidate(); timer = nil
        link?.invalidate(); link = nil
        log.finishPeak()
        saveLog()
    }

    private func saveLog() { UserDefaults.standard.set(log.encoded(), forKey: Self.logKey) }

    private func sample() {
        let now = CACurrentMediaTime()
        let fps = Double(frames) / max(now - lastTick, 0.001)
        frames = 0
        lastTick = now
        counter += 1
        // `sample` tourne sur le fil principal : son propre fil est celui de l'interface.
        let cpu = Self.cpuUsage(mainThread: pthread_mach_thread_np(pthread_self()))
        let ram = Diagnostics.footprintMB()
        samples.append(Sample(id: counter, cpu: cpu.total, ramMB: ram, fps: fps))
        if samples.count > 90 { samples.removeFirst(samples.count - 90) }
        activities = ActivityCenter.shared.snapshot()
        record(cpu: cpu, ram: ram, fps: fps)
    }

    private func record(cpu: (total: Double, main: Double), ram: Double, fps: Double) {
        var measured: [String: Double] = [:]
        for row in activities { if let seconds = row.cpuSeconds, seconds > 0 { measured[row.kind] = seconds } }
        let sample = PerformanceSample(date: Date(), cpu: cpu.total, mainThreadCPU: cpu.main, ramMB: ram, fps: fps,
                                       inReader: ReadingTimeTracker.shared.isReading, activitySeconds: measured)
        let peakEnded = log.add(sample)
        if peakEnded, let peak = log.peaks.last {
            let parts = peak.activitySeconds.map { "\($0.key) \(String(format: "%.1f", $0.value)) s" }.sorted().joined(separator: ", ")
            Diagnostics.log("pic CPU \(Int(peak.maxCPU)) % (moyenne \(Int(peak.averageCPU)) %) pendant \(peak.seconds) s, fil principal \(Int(peak.mainThreadCPU)) %, travaux finis : \(parts)", "performances")
        }
        // Une écriture toutes les minutes, ou à la fin d'un pic.
        if peakEnded || counter % 60 == 0 { saveLog() }
    }

    /// Somme de l'usage CPU des fils de l'app (100 % = un cœur plein).
    nonisolated static func cpuPercent() -> Double { cpuUsage().total }

    /// Somme de l'usage CPU des fils de l'app, et part de `mainThread`, le fil de l'interface s'il est donné.
    nonisolated static func cpuUsage(mainThread: mach_port_t? = nil) -> (total: Double, main: Double) {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return (0, 0) }
        defer {
            // Une référence de port par fil, à rendre, puis le tableau lui-même.
            for i in 0..<Int(count) { mach_port_deallocate(mach_task_self_, threads[i]) }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)),
                          vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        }
        var total = 0.0, main = 0.0
        for i in 0..<Int(count) {
            var info = thread_basic_info()
            var size = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &size)
                }
            }
            guard result == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 else { continue }
            let usage = Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            total += usage
            if threads[i] == mainThread { main = usage }
        }
        return (total, main)
    }

}

/// Cible du `CADisplayLink` (qui retient sa cible) : compte les images.
private final class FrameCounter: NSObject {
    let onFrame: () -> Void
    init(_ onFrame: @escaping () -> Void) { self.onFrame = onFrame }
    @objc func tick() { onFrame() }
}

/// Moniteur de ressources, petit par défaut : CPU, RAM et FPS sur une ligne. La flèche déroule la courbe de la
/// mesure choisie (touchée parmi les trois), avec une animation. Recette 1.3.2 (62), L9 : dans le lecteur, il est
/// rangé dans la barre du haut à droite et se déroule **vers le bas** ; dans la bibliothèque, il reste en bas à
/// gauche (`ActivityDock`) et se déroule vers le haut. La courbe est à 50 % d'opacité, avec un fondu vers son bord
/// extérieur ; les valeurs restent nettes.
struct ResourceMonitorPanel: View {
    /// `true` : sous la barre du lecteur (la courbe s'ouvre en dessous) ; `false` : en bas d'écran (au-dessus).
    var expandsDown = false
    /// Prend toute la largeur proposée (sous la capsule d'actions du lecteur) ; sinon, la taille de son contenu.
    var fillsWidth = false
    /// Dans la capsule d'actions du lecteur : pas de fond ni de bord à lui, la capsule s'allonge.
    var embedded = false
    /// Accueil seulement : la liste des activités, relevée tant que le panneau reste déplié.
    var showsActivities = false
    @ObservedObject private var monitor = ResourceMonitor.shared
    @AppStorage(ResourceMonitor.shownKey) private var shown = false
    @AppStorage("monitor.detailed") private var detailed = false
    @AppStorage("monitor.metric") private var metric = ResourceMonitor.Metric.cpu
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if detailed && !expandsDown { chart }
            header
            if detailed && expandsDown { chart }
            if detailed && showsActivities { MonitorActivityList() }
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(Atelier.textPrimary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .modifier(MonitorBackground(embedded: embedded))
        // Même ressort que la capsule : la courbe se déroule dans le prolongement du même mouvement.
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.9), value: detailed)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(Atelier.Tint.read)
            if let s = monitor.last {
                value(.cpu, String(format: "%.0f %%", s.cpu))
                value(.ram, String(format: String(localized: "%.0f Mo"), s.ramMB))
                value(.fps, String(format: "%.0f", s.fps))
            } else {
                Text("Mesure…").foregroundStyle(Atelier.textTertiary)
            }
            if fillsWidth { Spacer(minLength: 4) }
            // Cibles de 40 pt au doigt, écartées : la croix touchée par erreur fermait le moniteur à côté du panneau OCR.
            Button { detailed.toggle() } label: {
                Image(systemName: "chevron.down")
                    .font(Atelier.font(14, weight: .bold))
                    .rotationEffect(.degrees((detailed ? 180 : 0) + (expandsDown ? 0 : 180)))
                    .frame(width: 40, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(detailed ? String(localized: "Replier le graphique") : String(localized: "Dérouler le graphique"))
            Button { shown = false } label: {
                Image(systemName: "xmark")
                    .font(Atelier.font(14, weight: .bold))
                    .frame(width: 40, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Fermer le moniteur")
            .padding(.trailing, 6)
        }
        .buttonStyle(.plain)
    }

    private var chart: some View {
        Chart(monitor.samples) { s in
            LineMark(x: .value("t", s.id), y: .value(metric.title, metric.value(s)))
                .foregroundStyle(Atelier.Tint.read)
                .interpolationMethod(.monotone)
            AreaMark(x: .value("t", s.id), y: .value(metric.title, metric.value(s)))
                .foregroundStyle(Atelier.Tint.read.opacity(0.3))
        }
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
        .frame(width: fillsWidth ? nil : 260, height: 110)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        // Seul le graphique est atténué : 50 %, avec un fondu vers son bord extérieur.
        .opacity(0.5)
        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: expandsDown ? .bottom : .top,
                             endPoint: expandsDown ? .top : .bottom))
        .overlay(alignment: expandsDown ? .bottomTrailing : .topTrailing) {
            Text("90 s · \(metric.unit)").font(.caption2).foregroundStyle(Atelier.textTertiary)
        }
        .accessibilityLabel("\(metric.title), 90 dernières secondes")
        // Révélée par le haut (la forme qui la porte s'allonge), sans glisser par-dessus les valeurs.
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1, anchor: expandsDown ? .top : .bottom)))
    }

    /// Valeur de l'en-tête ; en mode détaillé, la toucher choisit la courbe affichée (mesure choisie mise en avant).
    @ViewBuilder
    private func value(_ m: ResourceMonitor.Metric, _ text: String) -> some View {
        let label = HStack(spacing: 3) {
            Text(m.title).foregroundStyle(detailed && metric == m ? Atelier.Tint.read : Atelier.textTertiary)
            Text(text)
        }
        if detailed {
            Button { metric = m } label: {
                label.padding(.horizontal, 5).padding(.vertical, 2)
                    .background(metric == m ? Atelier.Tint.read.opacity(0.15) : .clear, in: Capsule())
            }
            .accessibilityLabel("Courbe \(m.title)")
            .accessibilityAddTraits(metric == m ? .isSelected : [])
        } else {
            label
        }
    }
}

/// Bas gauche de la bibliothèque et du lecteur (#47) : le moniteur (s'il est affiché), puis les pastilles des IA
/// locales, qui sortent de sa droite en glissant (sans mouvement si « Réduire les animations » est activé).
struct ActivityDock: View {
    /// Lecteur : le moniteur est dans la barre du haut (recette 62, L9) ; seules les pastilles restent ici.
    var showsMonitor = true
    @AppStorage(ResourceMonitor.enabledKey) private var monitorEnabled = false
    @AppStorage(ResourceMonitor.shownKey) private var monitorShown = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if showsMonitor && monitorEnabled && monitorShown {
                ResourceMonitorPanel().transition(.opacity)
            }
            AITaskPill()
        }
    }
}

/// Fond du moniteur : le sien quand il est seul (accueil), aucun quand il prolonge la capsule d'actions.
private struct MonitorBackground: ViewModifier {
    let embedded: Bool
    func body(content: Content) -> some View {
        if embedded { content } else { content.atelierPanel(radius: 14) }
    }
}

/// Détail du panneau déplié de l'accueil. Le total CPU et mémoire reste celui de toute l'app, en tête du panneau.
/// iPadOS ne donne ni le CPU ni la mémoire par fonction. Chaque valeur dit donc d'où elle vient : « mesuré » pour le temps
/// processeur du travail instrumenté, compté à la fin de chaque travail et donc jamais retranché du total instantané, « estimé » pour les images d'après leurs dimensions, « compteur MLX » pour le chiffre
/// partagé de MLX. La mémoire reste affichée à part, jamais soustraite : ces compteurs ne mesurent pas la même chose.
private struct MonitorActivityList: View {
    @ObservedObject private var monitor = ResourceMonitor.shared
    @ObservedObject private var tasks = AITaskCenter.shared
    @State private var modelMB: Int?
    @State private var modelName: String?
    @State private var cacheMB = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if monitor.activities.isEmpty && tasks.jobs.isEmpty && modelName == nil {
                Text("Aucune tâche coûteuse en cours").foregroundStyle(Atelier.textSecondary)
            }
            ForEach(monitor.activities, id: \.kind) { row in
                line(ActivityCenter.Kind(rawValue: row.kind)?.title ?? row.kind, detail: row.detail, value: value(row))
            }
            ForEach(tasks.jobs) { job in
                line(job.title, detail: job.activity, value: job.progress.map { "\($0.done)/\($0.total)" } ?? String(localized: "en cours"))
            }
            if let modelName {
                line(String(localized: "Modèle IA chargé"), detail: modelName,
                     value: modelMB.map { String(localized: "compteur MLX \($0) Mo") } ?? String(localized: "chargé"))
            }
            if cacheMB > 0 {
                line(String(localized: "Images de pages gardées"), detail: nil, value: String(localized: "\(cacheMB) Mo estimés"))
            }
            if let last = monitor.last {
                // Le compteur MLX est partagé, et compte autrement que l'empreinte : rien n'en est soustrait (contre-revue de ff60a3a).
                line(String(localized: "Empreinte totale de l'app"), detail: nil, value: String(localized: "\(Int(last.ramMB)) Mo"))
            }
        }
        .font(Atelier.font(11))
        .foregroundStyle(Atelier.textPrimary)
        .onAppear(perform: refresh)
        .onChange(of: monitor.last?.id) { _ in refresh() }
    }

    private func value(_ row: ActivityLedger.Row) -> String {
        if let seconds = row.cpuSeconds { return String(format: String(localized: "%.2f s de calcul finies"), seconds) }
        return String(localized: "\(Int(row.busyShare * 100)) % du temps")
    }

    private func refresh() {
        cacheMB = (ToneCache.estimatedBytes + ScanSharpening.estimatedBytes) / 1_048_576
        Task {
            let status = await GLMOCREngine.status()
            modelName = status.loaded?.lastPathComponent
            modelMB = status.loaded == nil ? nil : status.gpuActiveMB
        }
    }

    private func line(_ title: String, detail: String?, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(ui: title).lineLimit(1)
                if let detail { Text(ui: detail).foregroundStyle(Atelier.textTertiary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            Text(ui: value).foregroundStyle(Atelier.textSecondary).lineLimit(1)
        }
    }
}
