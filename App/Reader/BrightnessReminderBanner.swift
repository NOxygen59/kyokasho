// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI
import UIKit

/// Rappel de luminosité dans le lecteur (choix de NOxygen59 du 11/11/2026) : sur batterie, écran à plus de 90 %,
/// une bannière dit ce que cela coûte d'après le relevé de cet iPad. Elle ne règle rien à la place de l'utilisateur.
///
/// Affichage seul : `BrightnessReminder.shouldShow` (fonction pure testée) décide. Rien ne tourne en fond : l'état est
/// relu à l'apparition, au retour dans l'app et quand iOS annonce un changement de luminosité ou d'alimentation.
/// « OK » la ferme jusqu'au prochain lancement ; « Ne plus afficher » éteint le réglage (Réglages → Pages et gestes).
/// Sur Mac, la luminosité de l'écran n'est pas celle d'un iPad sur batterie : la bannière n'existe pas.
struct BrightnessReminderBanner: View {
    #if targetEnvironment(macCatalyst)
    var body: some View { EmptyView() }
    #else
    /// Fermé depuis le lancement : gardé hors de la vue, le lecteur est recréé à chaque changement d'onglet.
    @MainActor private static var dismissedThisLaunch = false

    @AppStorage(BrightnessReminder.enabledKey) private var enabled = true
    @State private var percent: Int?
    @Environment(\.scenePhase) private var scenePhase
    /// Lu pour être redessiné quand la palette change, comme les autres bannières.
    @Environment(\.themeRevision) private var themeRevision

    var body: some View {
        let _ = themeRevision
        Group {
            if let percent {
                HStack(spacing: 12) {
                    Image(systemName: "sun.max.fill")
                        .font(Atelier.font(22)).foregroundStyle(Atelier.Tint.annotate)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Luminosité à \(percent) % : la batterie descend plus vite.")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Atelier.textPrimary)
                        Text("Sur cet iPad, la lecture a coûté \(BrightnessReminder.measuredHighRate) points de batterie par heure au-dessus de 90 %, contre \(BrightnessReminder.measuredLowRate) à 60 % ou moins.")
                            .font(.footnote).foregroundStyle(Atelier.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Button("Ne plus afficher") { enabled = false; refresh() }
                        .font(.footnote).foregroundStyle(Atelier.textSecondary)
                    Button("OK") { Self.dismissedThisLaunch = true; refresh() }
                        .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .atelierPanel()
                .padding(.horizontal, Atelier.gap).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: percent != nil)
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { if $0 == .active { refresh() } }
        .onChange(of: enabled) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in refresh() }
    }

    private func refresh() {
        let brightness = Double(UIScreen.main.brightness)
        let show = BrightnessReminder.shouldShow(brightness: brightness, onBattery: Self.onBattery(), enabled: enabled,
                                                 dismissed: Self.dismissedThisLaunch)
        percent = show ? BrightnessReminder.percent(brightness) : nil
    }

    /// Débranché ? La surveillance de la batterie n'est allumée que le temps de la lecture quand le relevé de batterie
    /// est éteint, comme `Diagnostics.batteryPercent` : elle coûte des notifications périodiques.
    private static func onBattery() -> Bool {
        let device = UIDevice.current
        let wasEnabled = device.isBatteryMonitoringEnabled
        if !wasEnabled { device.isBatteryMonitoringEnabled = true }
        let unplugged = device.batteryState == .unplugged
        if !wasEnabled { device.isBatteryMonitoringEnabled = UserDefaults.standard.bool(forKey: EnergyMeter.enabledKey) }
        return unplugged
    }
    #endif
}
