// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Charts
import Darwin
import QuartzCore
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
        var unit: String { self == .cpu ? "%" : self == .ram ? "Mo" : "i/s" }
        func value(_ s: Sample) -> Double { self == .cpu ? s.cpu : self == .ram ? s.ramMB : s.fps }
    }

    @Published private(set) var samples: [Sample] = []
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
    }

    private func sample() {
        let now = CACurrentMediaTime()
        let fps = Double(frames) / max(now - lastTick, 0.001)
        frames = 0
        lastTick = now
        counter += 1
        samples.append(Sample(id: counter, cpu: Self.cpuPercent(), ramMB: Self.footprintMB(), fps: fps))
        if samples.count > 90 { samples.removeFirst(samples.count - 90) }
    }

    /// Somme de l'usage CPU des fils de l'app (100 % = un cœur plein).
    nonisolated static func cpuPercent() -> Double {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return 0 }
        defer {
            // Une référence de port par fil, à rendre, puis le tableau lui-même.
            for i in 0..<Int(count) { mach_port_deallocate(mach_task_self_, threads[i]) }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)),
                          vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        }
        var total = 0.0
        for i in 0..<Int(count) {
            var info = thread_basic_info()
            var size = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &size)
                }
            }
            guard result == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 else { continue }
            total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
        }
        return total
    }

    /// Mémoire de l'app comptée par iOS (Mo).
    nonisolated static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
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
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(Atelier.textPrimary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .atelierPanel(radius: 14)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85), value: detailed)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(Atelier.Tint.read)
            if let s = monitor.last {
                value(.cpu, String(format: "%.0f %%", s.cpu))
                value(.ram, String(format: "%.0f Mo", s.ramMB))
                value(.fps, String(format: "%.0f", s.fps))
            } else {
                Text("Mesure…").foregroundStyle(Atelier.textTertiary)
            }
            if fillsWidth { Spacer(minLength: 4) }
            Button { detailed.toggle() } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees((detailed ? 180 : 0) + (expandsDown ? 0 : 180)))
            }
            .accessibilityLabel(detailed ? "Replier le graphique" : "Dérouler le graphique")
            Button { shown = false } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Fermer le moniteur")
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
        .transition(reduceMotion ? .opacity
                    : .move(edge: expandsDown ? .top : .bottom).combined(with: .opacity))
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
