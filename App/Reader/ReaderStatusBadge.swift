// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59
//
// Anneau repris de DuoBar, sous licence MIT : https://github.com/Mikeli7666/DuoBar — Copyright (c) 2026 Mike Li.
// Voir THIRD_PARTY_NOTICES.md.

import Network
import ReaderCore
import SwiftUI
import UIKit

/// Batterie façon iPhone Duo et heure, en haut à gauche du lecteur quand les barres sont cachées (la barre d'état d'iOS l'est
/// alors aussi). Pour tous les documents, PDF ou CBZ.
///
/// Couleurs fixes, sans thème : blanc sur fond noir translucide, lisible sur n'importe quelle page. Aucun geste : les touchers
/// passent à la page. Le suivi de la batterie ne tourne que tant que le badge est affiché.
struct ReaderStatusBadge: View {
    @StateObject private var battery = BatteryWatcher()
    private static let diameter: CGFloat = 24

    var body: some View {
        VStack(spacing: 2) {
            ring
                .padding(3)
                .background(.black.opacity(0.5), in: Circle())
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(Atelier.font(9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: Atelier.corner(3), style: .continuous))
            }
        }
        .padding(.leading, 8)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Batterie \(Int(battery.ring.progress * 100)) %"))
        .onAppear { battery.start() }
        .onDisappear { battery.stop() }
    }

    /// Dans l'ouverture de l'anneau : les points s'il y a du Wi-Fi, le logo du partage de connexion à la même place.
    /// iPadOS ne donne pas la force du signal aux apps : les points disent seulement connecté ou non.
    @ViewBuilder
    private var gapIndicator: some View {
        let diameter = Self.diameter
        if battery.hotspot {
            Image(systemName: "personalhotspot")
                .font(Atelier.font(diameter * 0.26, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: diameter * 0.4)
        } else {
            let dot = diameter * DuoBatteryRing.dotDiameterRatio
            ForEach(Array(DuoBatteryRing.dotOffsets.enumerated()), id: \.offset) { _, offset in
                Circle()
                    .fill(.white)
                    .opacity(battery.wifi ? 1 : 0.3)
                    .frame(width: dot, height: dot)
                    .offset(x: offset.x * diameter, y: offset.y * diameter)
            }
        }
    }

    private var tint: Color {
        switch battery.ring.tint {
        case .normal: return .white
        case .charging: return Color(.systemGreen)
        case .lowPower: return Color(.systemYellow)
        case .low: return Color(.systemRed)
        }
    }

    private var ring: some View {
        let diameter = Self.diameter
        let line = diameter * DuoBatteryRing.strokeRatio * 1.3
        let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
        let bolt = Image(systemName: "bolt.fill").font(Atelier.font(diameter * DuoBatteryRing.boltFontRatio * 1.5, weight: .bold))
        let radius = (diameter - line) / 2
        return ZStack {
            ZStack {
                DuoRingArc(endDegrees: DuoBatteryRing.endDegrees).stroke(tint.opacity(DuoBatteryRing.trackOpacity), style: style)
                DuoRingArc(endDegrees: battery.ring.filledEndDegrees).stroke(tint, style: style)
                if battery.ring.showsBolt {
                    // L'anneau s'efface autour de l'éclair : sa silhouette, grossie par des copies décalées en cercle.
                    ForEach(0..<16, id: \.self) { index in
                        let angle = Double(index) / 16 * 2 * .pi
                        let spread = diameter * DuoBatteryRing.boltGapRatio
                        bolt.foregroundStyle(.black)
                            .offset(x: CGFloat(cos(angle)) * spread, y: -radius + CGFloat(sin(angle)) * spread)
                            .blendMode(.destinationOut)
                    }
                }
            }
            .compositingGroup()
            if battery.ring.showsBolt {
                bolt.foregroundStyle(tint).offset(y: -radius)
            }
            gapIndicator
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Arc de l'anneau, de son début jusqu'à `endDegrees`.
private struct DuoRingArc: Shape {
    let endDegrees: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard endDegrees > DuoBatteryRing.startDegrees else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        // Points calculés, sans `addArc` : son sens s'inverse dans le repère de SwiftUI.
        for index in 0...72 {
            let degrees = DuoBatteryRing.startDegrees + (endDegrees - DuoBatteryRing.startDegrees) * Double(index) / 72
            let radians = degrees * .pi / 180
            let point = CGPoint(x: center.x + CGFloat(cos(radians)) * radius, y: center.y + CGFloat(sin(radians)) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// État de la batterie d'après iPadOS. Le suivi s'arrête dès que plus rien ne l'affiche.
@MainActor
private final class BatteryWatcher: ObservableObject {
    @Published private(set) var ring = DuoBatteryRing(level: -1, charging: false, full: false, lowPowerMode: false)
    @Published private(set) var wifi = false
    @Published private(set) var hotspot = false
    private var observers: [NSObjectProtocol] = []
    private var path: NWPathMonitor?

    func start() {
        startNetwork()
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification,
                     Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    /// Wi-Fi « coûteux » : iOS marque ainsi un réseau qui passe par un partage de connexion, celui d'un iPhone notamment.
    /// C'est une indication du système, pas une preuve : un réseau Wi-Fi ordinaire peut aussi être marqué coûteux.
    private func startNetwork() {
        guard path == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] update in
            let connected = update.status == .satisfied && update.usesInterfaceType(.wifi)
            let shared = connected && update.isExpensive
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.wifi = connected
                    self.hotspot = shared
                }
            }
        }
        monitor.start(queue: .global(qos: .utility))
        path = monitor
    }

    func stop() {
        path?.cancel()
        path = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    private func refresh() {
        let device = UIDevice.current
        ring = DuoBatteryRing(level: Double(device.batteryLevel), charging: device.batteryState == .charging,
                              full: device.batteryState == .full, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}
