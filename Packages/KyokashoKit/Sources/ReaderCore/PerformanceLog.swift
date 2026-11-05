// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Un relevé du moniteur, une fois par seconde, seulement tant qu'il est affiché.
public struct PerformanceSample: Equatable, Sendable {
    public var date: Date
    /// Somme des fils de l'app, 100 % = un cœur plein.
    public var cpu: Double
    public var mainThreadCPU: Double
    public var ramMB: Double
    public var fps: Double
    public var inReader: Bool
    /// Secondes de processeur des travaux finis depuis le relevé précédent, par activité.
    public var activitySeconds: [String: Double]

    public init(date: Date, cpu: Double, mainThreadCPU: Double, ramMB: Double, fps: Double, inReader: Bool, activitySeconds: [String: Double]) {
        self.date = date
        self.cpu = cpu
        self.mainThreadCPU = mainThreadCPU
        self.ramMB = ramMB
        self.fps = fps
        self.inReader = inReader
        self.activitySeconds = activitySeconds
    }
}

/// Un épisode de processeur élevé, du premier relevé au-dessus du seuil au premier en dessous.
///
/// Deux mesures côte à côte, **jamais soustraites l'une de l'autre** : le total est un relevé instantané du système, alors
/// qu'une activité reçoit son temps processeur d'un bloc à la fin de son travail. Un dessin de 2 s peut donc se terminer dans
/// un épisode d'une seconde : aucun « reste » n'aurait de sens. Un travail commencé avant le pic y est compté en entier.
public struct PerformancePeak: Codable, Equatable, Sendable {
    public var start: Date
    public var seconds: Int
    public var maxCPU: Double
    public var averageCPU: Double
    public var mainThreadCPU: Double
    public var ramMB: Double
    public var lowestFPS: Double
    /// Contexte du relevé le plus haut.
    public var inReader: Bool
    /// Secondes de processeur créditées aux travaux finis jusqu'au premier relevé après l'épisode, par activité.
    public var activitySeconds: [String: Double]
}

/// Résumé d'une journée.
public struct PerformanceDay: Codable, Equatable, Sendable {
    public var day: Date
    public var maxCPU: Double
    public var maxRAM: Double
    public var lowestFPS: Double
    public var samples: Int
    public var cpuSum: Double

    public var averageCPU: Double { samples > 0 ? cpuSum / Double(samples) : 0 }
}

/// Historique borné des mesures de l'app : quelques dizaines de Ko au plus. Rien n'est relevé moniteur fermé : l'historique
/// décrit donc les moments où le moniteur était affiché, pas toute l'utilisation.
public struct PerformanceLog: Codable, Equatable, Sendable {
    public static let peakThreshold: Double = 150
    public static let maxDays = 90
    public static let maxPeaks = 100

    public private(set) var days: [PerformanceDay] = []
    /// Du plus ancien au plus récent.
    public private(set) var peaks: [PerformancePeak] = []
    /// Épisode encore ouvert. Pas enregistré tant qu'il dure : un arrêt brutal perd seulement ce pic-là.
    private var open: OpenPeak?

    private struct OpenPeak: Equatable, Sendable {
        var start: Date
        var last: Date
        var samples = 0
        var cpuSum = 0.0
        var mainSum = 0.0
        var activitySum: [String: Double] = [:]
        var maxCPU = 0.0
        var ramMB = 0.0
        var lowestFPS = Double.infinity
        var inReader = false
    }

    private enum CodingKeys: String, CodingKey { case days, peaks }

    public init() {}

    /// Vrai si un pic vient de se terminer : bon moment pour enregistrer.
    @discardableResult
    public mutating func add(_ sample: PerformanceSample, calendar: Calendar = .current) -> Bool {
        addToDay(sample, calendar: calendar)
        guard sample.cpu >= Self.peakThreshold else {
            // Un travail du pic peut ne finir, donc n'être compté, qu'au premier relevé redescendu.
            open?.activitySum.merge(sample.activitySeconds, uniquingKeysWith: +)
            return finishPeak()
        }
        var peak = open ?? OpenPeak(start: sample.date, last: sample.date)
        peak.last = sample.date
        peak.samples += 1
        peak.cpuSum += sample.cpu
        peak.mainSum += sample.mainThreadCPU
        peak.activitySum.merge(sample.activitySeconds, uniquingKeysWith: +)
        peak.lowestFPS = min(peak.lowestFPS, sample.fps)
        if sample.cpu >= peak.maxCPU {
            peak.maxCPU = sample.cpu
            peak.ramMB = sample.ramMB
            peak.inReader = sample.inReader
        }
        open = peak
        return false
    }

    /// Moniteur arrêté : le pic en cours s'arrête au dernier relevé.
    @discardableResult
    public mutating func finishPeak() -> Bool {
        guard let peak = open else { return false }
        open = nil
        let samples = Double(peak.samples)
        peaks.append(PerformancePeak(start: peak.start, seconds: Int(peak.last.timeIntervalSince(peak.start).rounded()) + 1,
                                     maxCPU: peak.maxCPU, averageCPU: peak.cpuSum / samples, mainThreadCPU: peak.mainSum / samples,
                                     ramMB: peak.ramMB, lowestFPS: peak.lowestFPS, inReader: peak.inReader,
                                     activitySeconds: peak.activitySum))
        if peaks.count > Self.maxPeaks { peaks.removeFirst(peaks.count - Self.maxPeaks) }
        return true
    }

    private mutating func addToDay(_ sample: PerformanceSample, calendar: Calendar) {
        let day = calendar.startOfDay(for: sample.date)
        if var last = days.last, last.day == day {
            last.maxCPU = max(last.maxCPU, sample.cpu)
            last.maxRAM = max(last.maxRAM, sample.ramMB)
            last.lowestFPS = min(last.lowestFPS, sample.fps)
            last.samples += 1
            last.cpuSum += sample.cpu
            days[days.count - 1] = last
        } else {
            days.append(PerformanceDay(day: day, maxCPU: sample.cpu, maxRAM: sample.ramMB, lowestFPS: sample.fps,
                                       samples: 1, cpuSum: sample.cpu))
            if days.count > Self.maxDays { days.removeFirst(days.count - Self.maxDays) }
        }
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// Données absentes ou illisibles : historique vide. Ce n'est qu'une mesure, rien de l'utilisateur.
    public static func decode(_ data: Data?) -> PerformanceLog {
        guard let data, let log = try? JSONDecoder().decode(PerformanceLog.self, from: data) else { return PerformanceLog() }
        return log
    }
}
