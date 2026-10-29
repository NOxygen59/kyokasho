// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Relevé de batterie (#20, RET-017) : mesurer **quelle fonction consomme** avant toute optimisation.
/// L'app note un échantillon par minute dans `Documents/Diagnostics/energie.csv` ; ce fichier est lu ici pour un
/// résumé par activité. iOS ne donne ni la consommation par fonction ni celle du GPU (MLX) : on l'estime par la baisse
/// du niveau de batterie pendant chaque activité, avec le temps de calcul (CPU) de l'app et la chaleur.
public struct EnergySample: Equatable, Sendable {
    public var date: Date
    /// Niveau 0…1 ; négatif si iOS ne le donne pas.
    public var battery: Double
    public var charging: Bool
    /// `ProcessInfo.ThermalState` : 0 normal, 1 tiède, 2 chaud, 3 critique.
    public var thermal: Int
    public var lowPower: Bool
    public var brightness: Double
    /// Temps de calcul cumulé de l'app depuis son lancement (utilisateur + système), en secondes.
    public var cpuSeconds: Double
    public var memoryMB: Double
    /// Ce que faisait l'app pendant la minute qui suit (« Lecture », « IA : OvisOCR2 », …).
    public var activity: String

    public init(date: Date, battery: Double, charging: Bool, thermal: Int, lowPower: Bool, brightness: Double,
                cpuSeconds: Double, memoryMB: Double, activity: String) {
        self.date = date
        self.battery = battery
        self.charging = charging
        self.thermal = thermal
        self.lowPower = lowPower
        self.brightness = brightness
        self.cpuSeconds = cpuSeconds
        self.memoryMB = memoryMB
        self.activity = activity
    }
}

public enum EnergyLog {
    public static let header = "date,batterie,en_charge,chaleur,economie,luminosite,cpu_s,memoire_mo,activite"
    /// Au-delà, l'intervalle couvre une suspension de l'app (arrière-plan, verrouillage) : il n'est attribué à rien.
    public static let maxGap: TimeInterval = 180
    /// En dessous, la baisse de batterie (arrondie par iOS) ne permet pas de calculer un débit fiable.
    public static let minimumSeconds: TimeInterval = 600

    private static func formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    /// Une ligne CSV. L'activité ne contient jamais de virgule ni de retour à la ligne (remplacés).
    public static func line(_ s: EnergySample) -> String {
        let activity = s.activity.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "\n", with: " ")
        return [formatter().string(from: s.date), String(format: "%.3f", s.battery), s.charging ? "1" : "0", String(s.thermal),
                s.lowPower ? "1" : "0", String(format: "%.2f", s.brightness), String(format: "%.2f", s.cpuSeconds),
                String(format: "%.0f", s.memoryMB), activity].joined(separator: ",")
    }

    /// Lignes illisibles (en-tête, fichier tronqué par la rotation) ignorées.
    public static func parse(_ text: String) -> [EnergySample] {
        let f = formatter()
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            let c = raw.split(separator: ",", maxSplits: 8, omittingEmptySubsequences: false).map(String.init)
            guard c.count == 9, let date = f.date(from: c[0]), let battery = Double(c[1]), let thermal = Int(c[3]),
                  let brightness = Double(c[5]), let cpu = Double(c[6]), let memory = Double(c[7]) else { return nil }
            return EnergySample(date: date, battery: battery, charging: c[2] == "1", thermal: thermal, lowPower: c[4] == "1",
                                brightness: brightness, cpuSeconds: cpu, memoryMB: memory, activity: c[8])
        }
    }

    public struct Row: Equatable, Sendable {
        public var activity: String
        /// Temps mesuré sur batterie.
        public var seconds: TimeInterval
        /// Points de batterie perdus par heure ; `nil` si moins de `minimumSeconds` mesurées.
        public var batteryPerHour: Double?
        /// Temps de calcul / temps écoulé (100 % = un cœur occupé en continu).
        public var cpuPercent: Double
        public var maxThermal: Int
    }

    /// Résumé par activité, la plus longue d'abord. Un intervalle est attribué à l'activité notée à son début ;
    /// il est ignoré s'il touche une charge, une suspension ou un relancement (temps de calcul qui repart de zéro).
    public static func summary(_ samples: [EnergySample]) -> [Row] {
        var seconds: [String: TimeInterval] = [:], drop: [String: Double] = [:], cpu: [String: Double] = [:]
        var thermal: [String: Int] = [:]
        let sorted = samples.sorted { $0.date < $1.date }
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let dt = b.date.timeIntervalSince(a.date)
            guard dt > 0, dt <= maxGap, !a.charging, !b.charging, a.battery >= 0, b.battery >= 0,
                  b.cpuSeconds >= a.cpuSeconds else { continue }
            seconds[a.activity, default: 0] += dt
            drop[a.activity, default: 0] += a.battery - b.battery
            cpu[a.activity, default: 0] += b.cpuSeconds - a.cpuSeconds
            thermal[a.activity] = max(thermal[a.activity] ?? 0, a.thermal, b.thermal)
        }
        return seconds.map { activity, total in
            Row(activity: activity, seconds: total,
                batteryPerHour: total >= minimumSeconds ? (drop[activity] ?? 0) * 100 * 3600 / total : nil,
                cpuPercent: (cpu[activity] ?? 0) / total * 100, maxThermal: thermal[activity] ?? 0)
        }.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.activity < $1.activity }
    }

    public static func thermalName(_ value: Int) -> String {
        ["normale", "tiède", "chaud", "critique"][min(max(value, 0), 3)]
    }
}
