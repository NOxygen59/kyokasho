// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Écran de l'app au moment du relevé (colonne `ecran`, ajoutée le 10/11/2026).
public enum EnergyScreen: String, Sendable {
    case active = "actif"
    case background = "arriere-plan"
}

/// Relevé de batterie (#20, RET-017) : mesurer **quelle fonction consomme** avant toute optimisation.
/// L'app note un échantillon par minute dans `Documents/Diagnostics/energie.csv` ; ce fichier est lu ici pour un
/// résumé par activité. iOS ne donne ni la consommation par fonction ni celle du GPU (MLX) : on l'estime par la baisse
/// du niveau de batterie pendant chaque activité, avec le temps de calcul (CPU) de l'app et la chaleur.
///
/// Colonnes ajoutées le 10/11/2026 (demande de NOxygen59) : elles disent **pourquoi** une minute coûte cher
/// (processeur de l'app, écran, chaleur, teinte de page, modèles IA en mémoire, tâches IA, document, version).
/// Elles sont écrites **à la fin** de chaque ligne : un ancien `energie.csv` de 9 colonnes reste lisible.
public struct EnergySample: Equatable, Sendable {
    public var date: Date
    /// Niveau 0…1 ; négatif si iOS ne le donne pas (jamais écrit tel quel dans le fichier).
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
    /// Processeur de l'app depuis la ligne précédente, en % d'un cœur (colonne `cpu_pct`) ; `nil` si inconnu.
    public var cpuPercent: Double?
    /// Écran actif ou app en arrière-plan (colonne `ecran`).
    public var screen: EnergyScreen
    /// Teinte de page du lecteur (`PageTone`, colonne `teinte`) ; vide hors lecteur.
    public var tone: String
    /// Modèles d'IA tenus en mémoire (colonne `ia_chargees`), séparés par « + ».
    public var loadedModels: String
    /// Tâches IA en cours (colonne `taches_ia`), séparées par « + ».
    public var aiTasks: String
    /// 8 premiers caractères de l'identifiant du document ouvert (colonne `document`) ; vide hors lecteur.
    /// Jamais un titre, jamais un texte de page : le fichier peut être partagé.
    public var document: String
    /// Version de l'app (colonne `version_app`), ex. « 1.4.2 (58) ».
    public var appVersion: String

    public init(date: Date, battery: Double, charging: Bool, thermal: Int, lowPower: Bool, brightness: Double,
                cpuSeconds: Double, memoryMB: Double, activity: String, cpuPercent: Double? = nil,
                screen: EnergyScreen = .active, tone: String = "", loadedModels: String = "", aiTasks: String = "",
                document: String = "", appVersion: String = "") {
        self.date = date
        self.battery = battery
        self.charging = charging
        self.thermal = thermal
        self.lowPower = lowPower
        self.brightness = brightness
        self.cpuSeconds = cpuSeconds
        self.memoryMB = memoryMB
        self.activity = activity
        self.cpuPercent = cpuPercent
        self.screen = screen
        self.tone = tone
        self.loadedModels = loadedModels
        self.aiTasks = aiTasks
        self.document = document
        self.appVersion = appVersion
    }
}

public enum EnergyLog {
    /// Les 9 premières colonnes sont celles du départ (rétrocompatibles) ; les 8 suivantes sont ajoutées à la fin.
    public static let header = "date,batterie,en_charge,chaleur,economie,luminosite,cpu_s,memoire_mo,activite,"
        + "cpu_pct,ecran,etat_thermique,teinte,ia_chargees,taches_ia,document,version_app"
    public static let columnCount = 17
    public static let legacyColumnCount = 9
    /// Au-delà, l'intervalle couvre une suspension de l'app (arrière-plan, verrouillage) : il n'est attribué à rien.
    public static let maxGap: TimeInterval = 180
    /// En dessous, la baisse de batterie (arrondie par iOS) ne permet pas de calculer un débit fiable.
    public static let minimumSeconds: TimeInterval = 600
    /// Plus de 5 points de batterie en une minute : mesure aberrante (iOS arrondit, un saut de plusieurs dizaines de
    /// points vient d'un changement de source d'alimentation), ignorée par le résumé comme par les sessions.
    public static let maxDropPerMinute: Double = 0.05
    /// Longueur maximale de l'identifiant de document noté : un document n'est jamais désigné par son titre.
    public static let documentPrefix = 8

    private static func formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    /// Une colonne ne contient jamais de virgule ni de retour à la ligne (ils casseraient le CSV).
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    /// Nom stable de l'état thermique (colonne en texte, lisible sans l'app et sans dépendre de la langue).
    public static func thermalToken(_ value: Int) -> String {
        ["nominal", "fair", "serious", "critical"][min(max(value, 0), 3)]
    }

    /// Une ligne CSV. Une batterie inconnue s'écrit **vide**, jamais `-1` : `-1` se lisait comme un niveau et faussait
    /// les moyennes (relevé réel de 12 jours analysé le 10/11/2026).
    public static func line(_ s: EnergySample) -> String {
        let battery = s.battery >= 0 ? String(format: "%.3f", s.battery) : ""
        return [formatter().string(from: s.date), battery, s.charging ? "1" : "0", String(s.thermal),
                s.lowPower ? "1" : "0", String(format: "%.2f", s.brightness), String(format: "%.2f", s.cpuSeconds),
                String(format: "%.0f", s.memoryMB), clean(s.activity), s.cpuPercent.map { String(format: "%.1f", $0) } ?? "",
                s.screen.rawValue, thermalToken(s.thermal), clean(s.tone), clean(s.loadedModels), clean(s.aiTasks),
                String(clean(s.document).prefix(documentPrefix)), clean(s.appVersion)].joined(separator: ",")
    }

    /// Lignes illisibles (en-tête, fichier tronqué par la rotation) ignorées ; colonnes ajoutées absentes = inconnues.
    public static func parse(_ text: String) -> [EnergySample] {
        let f = formatter()
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            let c = raw.split(separator: ",", maxSplits: columnCount - 1, omittingEmptySubsequences: false).map(String.init)
            guard c.count >= legacyColumnCount, let date = f.date(from: c[0]), let thermal = Int(c[3]),
                  let brightness = Double(c[5]), let cpu = Double(c[6]), let memory = Double(c[7]) else { return nil }
            // Case vide : batterie inconnue. Un ancien fichier pouvait écrire « -1 » : même sens, jamais compté.
            let battery = Double(c[1]) ?? -1
            func extra(_ index: Int) -> String { c.count > index ? c[index] : "" }
            return EnergySample(date: date, battery: battery, charging: c[2] == "1", thermal: thermal,
                                lowPower: c[4] == "1", brightness: brightness, cpuSeconds: cpu, memoryMB: memory,
                                activity: c[8], cpuPercent: Double(extra(9)),
                                screen: EnergyScreen(rawValue: extra(10)) ?? .active, tone: extra(12),
                                loadedModels: extra(13), aiTasks: extra(14), document: extra(15), appVersion: extra(16))
        }
    }

    /// Fichier lu tel qu'il est sur le disque. Un octet illisible (ancienne coupe au milieu d'un caractère accentué)
    /// ne fait perdre que sa ligne : décoder tout le fichier en UTF-8 strict rendait le résumé entièrement vide.
    public static func parse(_ data: Data) -> [EnergySample] {
        parse(String(decoding: data, as: UTF8.self))
    }

    /// Fichier après rotation : l'en-tête, puis la fin de `data` (`bytes` octets au plus) à partir du **début d'une
    /// ligne**. Couper au milieu d'une ligne pouvait séparer les deux octets d'un « è » (« Bibliothèque ou réglages »)
    /// et laisser un fichier que la lecture stricte refusait en entier (BUG-004).
    public static func rotated(_ data: Data, keeping bytes: Int) -> Data {
        let tail = data.suffix(max(0, bytes))
        let start = tail.firstIndex(of: 0x0A).map { tail.index(after: $0) } ?? tail.endIndex
        return Data((header + "\n").utf8) + tail[start...]
    }

    /// Part de processeur de l'app entre deux relevés, en % d'un cœur occupé en continu. `nil` au premier relevé,
    /// après une suspension et après un relancement : le temps de calcul cumulé repart alors de zéro.
    public static func cpuPercent(previous: EnergySample?, _ current: EnergySample) -> Double? {
        guard let previous else { return nil }
        let dt = current.date.timeIntervalSince(previous.date)
        guard dt > 0, dt <= maxGap, current.cpuSeconds >= previous.cpuSeconds else { return nil }
        return (current.cpuSeconds - previous.cpuSeconds) / dt * 100
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

    /// Tranche de luminosité (demande du 10/11/2026) : ≤ 60 %, 61 à 90 %, > 90 %.
    public enum BrightnessBand: String, CaseIterable, Sendable, Identifiable {
        case low, mid, high
        public var id: String { rawValue }

        /// `brightness` est le réglage de l'écran, de 0 à 1 ; `nil` si iOS ne le donne pas.
        public static func of(_ brightness: Double) -> BrightnessBand? {
            guard brightness >= 0 else { return nil }
            if brightness <= 0.60 { return .low }
            if brightness <= 0.90 { return .mid }
            return .high
        }

        /// Bornes en clair (chiffres seulement : rien à traduire).
        public var title: String {
            switch self {
            case .low: return "≤ 60 %"
            case .mid: return "61–90 %"
            case .high: return "> 90 %"
            }
        }
    }

    public struct BandRow: Equatable, Sendable {
        public var band: BrightnessBand
        public var seconds: TimeInterval
        public var batteryPerHour: Double?
        public var cpuPercent: Double
    }

    /// Une période continue sur batterie (demande du 10/11/2026) : ce que l'appareil a perdu entre le début et la fin,
    /// sans charge, sans suspension et sans saut de mesure.
    public struct Session: Equatable, Sendable, Identifiable {
        public var start: Date
        public var end: Date
        /// Points de batterie perdus (0…100).
        public var lostPoints: Double
        /// Points perdus par heure ; `nil` si la session dure moins de `minimumSeconds`.
        public var batteryPerHour: Double?
        /// Luminosité moyenne de la session, de 0 à 1.
        public var brightness: Double
        /// Activité la plus longue de la session.
        public var activity: String
        public var seconds: TimeInterval { end.timeIntervalSince(start) }
        public var id: Date { start }
    }

    /// Un intervalle exploitable : sur batterie d'un bout à l'autre, sans suspension, sans relancement, sans saut
    /// impossible. Il est attribué à l'activité et à la luminosité **notées à son début**.
    private struct Interval {
        var start: Date
        var end: Date
        var activity: String
        var band: BrightnessBand?
        var drop: Double
        var cpu: Double
        var brightness: Double
        var thermal: Int
        var seconds: TimeInterval { end.timeIntervalSince(start) }
    }

    private static func intervals(_ samples: [EnergySample]) -> [Interval] {
        let sorted = samples.sorted { $0.date < $1.date }
        return zip(sorted, sorted.dropFirst()).compactMap { a, b in
            let dt = b.date.timeIntervalSince(a.date)
            guard dt > 0, dt <= maxGap, !a.charging, !b.charging, a.battery >= 0, b.battery >= 0,
                  b.cpuSeconds >= a.cpuSeconds else { return nil }
            let drop = a.battery - b.battery
            // Une baisse impossible en ce temps (saut de mesure) et une **hausse** sans charge (bruit d'arrondi)
            // ne sont attribuées à rien : elles faussaient les moyennes du relevé réel.
            guard drop >= 0, drop <= maxDropPerMinute * max(1, dt / 60) else { return nil }
            return Interval(start: a.date, end: b.date, activity: a.activity, band: BrightnessBand.of(a.brightness),
                            drop: drop, cpu: b.cpuSeconds - a.cpuSeconds, brightness: a.brightness,
                            thermal: max(a.thermal, b.thermal))
        }
    }

    /// Débit en points de batterie par heure ; `nil` sous `minimumSeconds` de mesure.
    private static func perHour(_ drop: Double, _ seconds: TimeInterval) -> Double? {
        seconds >= minimumSeconds ? drop * 100 * 3600 / seconds : nil
    }

    /// Résumé par activité, la plus longue d'abord. Un intervalle est attribué à l'activité notée à son début ;
    /// il est ignoré s'il touche une charge, une suspension, un relancement, une batterie inconnue ou un saut.
    public static func summary(_ samples: [EnergySample]) -> [Row] {
        var seconds: [String: TimeInterval] = [:], drop: [String: Double] = [:], cpu: [String: Double] = [:]
        var thermal: [String: Int] = [:]
        for i in intervals(samples) {
            seconds[i.activity, default: 0] += i.seconds
            drop[i.activity, default: 0] += i.drop
            cpu[i.activity, default: 0] += i.cpu
            thermal[i.activity] = max(thermal[i.activity] ?? 0, i.thermal)
        }
        return seconds.map { activity, total in
            Row(activity: activity, seconds: total, batteryPerHour: perHour(drop[activity] ?? 0, total),
                cpuPercent: (cpu[activity] ?? 0) / total * 100, maxThermal: thermal[activity] ?? 0)
        }.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.activity < $1.activity }
    }

    /// Même mesure, rangée par tranche de luminosité : c'est la luminosité qui explique l'essentiel de la consommation
    /// (relevé réel du 10/11/2026 : 13 points/heure à ≤ 60 %, 36 points/heure à > 90 % en lecture).
    public static func brightnessSummary(_ samples: [EnergySample]) -> [BandRow] {
        var seconds: [BrightnessBand: TimeInterval] = [:], drop: [BrightnessBand: Double] = [:]
        var cpu: [BrightnessBand: Double] = [:]
        for i in intervals(samples) {
            guard let band = i.band else { continue }
            seconds[band, default: 0] += i.seconds
            drop[band, default: 0] += i.drop
            cpu[band, default: 0] += i.cpu
        }
        return BrightnessBand.allCases.compactMap { band in
            guard let total = seconds[band], total > 0 else { return nil }
            return BandRow(band: band, seconds: total, batteryPerHour: perHour(drop[band] ?? 0, total),
                           cpuPercent: (cpu[band] ?? 0) / total * 100)
        }
    }

    /// Sessions sur batterie, la plus récente d'abord : deux intervalles séparés de plus de `maxGap` sont deux sessions.
    public static func sessions(_ samples: [EnergySample]) -> [Session] {
        var result: [Session] = []
        var current: [Interval] = []

        func close() {
            guard let first = current.first, let last = current.last else { current = []; return }
            let seconds = last.end.timeIntervalSince(first.start)
            var weight: [String: TimeInterval] = [:]
            for i in current { weight[i.activity, default: 0] += i.seconds }
            let brightness = seconds > 0
                ? current.reduce(0) { $0 + $1.brightness * $1.seconds } / seconds
                : first.brightness
            result.append(Session(start: first.start, end: last.end,
                                  lostPoints: current.reduce(0) { $0 + $1.drop } * 100,
                                  batteryPerHour: perHour(current.reduce(0) { $0 + $1.drop }, seconds),
                                  brightness: brightness,
                                  activity: weight.max { $0.value < $1.value }?.key ?? first.activity))
            current = []
        }

        for i in intervals(samples) {
            if let last = current.last, i.start.timeIntervalSince(last.end) > maxGap { close() }
            current.append(i)
        }
        close()
        return result.sorted { $0.start > $1.start }
    }

    public static func thermalName(_ value: Int) -> String {
        [String(localized: "normale", bundle: .main), String(localized: "tiède", bundle: .main), String(localized: "chaud", bundle: .main), String(localized: "critique", bundle: .main)][min(max(value, 0), 3)]
    }
}
