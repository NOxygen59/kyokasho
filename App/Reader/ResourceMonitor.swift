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

/// Panneau flottant du moniteur : compact (trois valeurs) ou détaillé (courbe de la mesure choisie).
struct ResourceMonitorPanel: View {
    let area: CGSize
    @ObservedObject private var monitor = ResourceMonitor.shared
    @AppStorage(ResourceMonitor.shownKey) private var shown = false
    @AppStorage("monitor.detailed") private var detailed = false
    @AppStorage("monitor.metric") private var metric = ResourceMonitor.Metric.cpu
    @AppStorage("monitor.x") private var x = 20.0
    @AppStorage("monitor.y") private var y = 80.0
    @GestureState private var drag: CGSize = .zero
    @State private var size: CGSize = CGSize(width: 260, height: 40)

    var body: some View {
        let left = min(max(0, x + drag.width), max(0, area.width - size.width))
        let top = min(max(0, y + drag.height), max(0, area.height - size.height))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(Atelier.Tint.read)
                if let s = monitor.last {
                    value("CPU", String(format: "%.0f %%", s.cpu))
                    value("RAM", String(format: "%.0f Mo", s.ramMB))
                    value("FPS", String(format: "%.0f", s.fps))
                } else {
                    Text("Mesure…").foregroundStyle(Atelier.textTertiary)
                }
                Button { detailed.toggle() } label: { Image(systemName: detailed ? "chevron.up" : "chart.xyaxis.line") }
                    .accessibilityLabel(detailed ? "Mode compact" : "Mode graphique")
                Button { shown = false } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Fermer le moniteur")
            }
            .buttonStyle(.plain)
            if detailed {
                Picker("Mesure", selection: $metric) {
                    ForEach(ResourceMonitor.Metric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Chart(monitor.samples) { s in
                    LineMark(x: .value("t", s.id), y: .value(metric.title, metric.value(s)))
                        .foregroundStyle(Atelier.Tint.read)
                        .interpolationMethod(.monotone)
                    AreaMark(x: .value("t", s.id), y: .value(metric.title, metric.value(s)))
                        .foregroundStyle(Atelier.Tint.read.opacity(0.15))
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
                .frame(width: 280, height: 120)
                Text("90 dernières secondes · \(metric.unit)").font(.caption2).foregroundStyle(Atelier.textTertiary)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(Atelier.textPrimary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .atelierPanel(radius: 14)
        .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { size = $0 } })
        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($drag) { v, s, _ in s = v.translation }
            .onEnded { v in
                x = min(max(0, x + v.translation.width), max(0, area.width - size.width))
                y = min(max(0, y + v.translation.height), max(0, area.height - size.height))
            })
        .offset(x: left, y: top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transaction { if drag != .zero { $0.animation = nil } }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func value(_ label: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(Atelier.textTertiary)
            Text(text)
        }
    }
}
