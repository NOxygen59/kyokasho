// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Fenêtre de détail automatique (PLAN-DIAG-001 E2b, DEC-02 B) : après une session non clôturée, le journal passe en
/// détail pendant 24 h, sans toucher au réglage manuel ni allumer le moniteur CPU, le relevé de batterie, la sonde ou
/// MetricKit. Posée une fois à la consommation du constat ; jamais prolongée par une simple relance.
public struct DiagnosticDetailWindow: Codable, Equatable, Sendable {
    public static let duration: TimeInterval = 24 * 3600
    public let from: Date
    public let until: Date

    public static func starting(at date: Date) -> DiagnosticDetailWindow {
        DiagnosticDetailWindow(from: date, until: date.addingTimeInterval(duration))
    }

    init(from: Date, until: Date) { self.from = from; self.until = until }

    /// Durée exacte de 24 h exigée ; une horloge reculée avant le début ne la rend pas active (pas d'extension).
    public var isWellFormed: Bool { abs(until.timeIntervalSince(from) - Self.duration) < 1 }
    public func isActive(at now: Date) -> Bool { isWellFormed && from <= now && now < until }
}

/// État de session du processus (PLAN-DIAG-001, E2a) : « armée » au premier plan, « close » au vrai arrière-plan.
/// Retrouvée armée au lancement suivant, elle dit seulement « session précédente non clôturée » : jamais
/// « plantage », ni cause, ni travail déduit (réunion DIAG du 25/11).
///
/// Contenu fermé : version du schéma, génération, état, date UTC, mémoire facultative. Aucun texte, titre, document,
/// page, identifiant de scène ni erreur.
public struct DiagnosticSessionState: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case armed, closed }

    public static let schema = 1
    public var schemaVersion: Int
    public var generation: UInt64
    public var state: Phase
    public var updatedAt: Date
    /// Empreinte mémoire au moment de l'écriture, en Mo ; absente si inconnue (jamais « 0 Mo » pour « inconnue »).
    public var memoryMB: Int?
    /// Fenêtre de détail automatique en cours (E2b), reportée telle quelle dans chaque écriture.
    public var detail: DiagnosticDetailWindow?
    /// Travaux suivis en cours à l'écriture (E2c), au plus `DiagnosticOngoing.limit` ; `ongoingTruncated` s'il y en
    /// avait davantage.
    public var ongoing: [DiagnosticOngoingEntry]?
    public var ongoingTruncated: Bool?

    public init(generation: UInt64, state: Phase, updatedAt: Date, memoryMB: Int?, detail: DiagnosticDetailWindow? = nil,
                ongoing: DiagnosticOngoing? = nil) {
        schemaVersion = Self.schema
        self.generation = generation
        self.state = state
        self.updatedAt = updatedAt
        self.memoryMB = memoryMB.flatMap { $0 > 0 ? $0 : nil }
        self.detail = detail
        if let ongoing, state == .armed, !ongoing.entries.isEmpty || ongoing.truncated {
            self.ongoing = ongoing.entries
            self.ongoingTruncated = ongoing.truncated ? true : nil
        }
    }
}

/// Automate du cycle de vie, au niveau du **processus** (jamais d'une scène) : idempotent face aux notifications
/// doublées ou réordonnées. `next` propose l'état à écrire sans rien changer ; `commit` ne l'adopte qu'après une
/// écriture réussie (revue R2 E2a, B2) : un échec laisse la transition à refaire à la notification suivante.
public struct DiagnosticSessionMachine: Sendable {
    public enum Event: Sendable, Equatable {
        /// `willEnterForeground`, `didBecomeActive`, ou application déjà au premier plan à l'installation.
        case foreground
        /// `willResignActive` / `.inactive` : sans effet (Centre de contrôle, Split View, sélecteur).
        case inactive
        /// `didEnterBackground` de l'application : la session est close, même s'il reste du travail.
        case background
    }

    public private(set) var generation: UInt64
    public private(set) var armed = false
    /// Fenêtre de détail en cours, recopiée dans chaque état écrit (E2b).
    public private(set) var detail: DiagnosticDetailWindow?
    /// Dernière projection des travaux suivis adoptée (E2c).
    public private(set) var ongoing = DiagnosticOngoing()

    public init(lastGeneration: UInt64 = 0, detail: DiagnosticDetailWindow? = nil) {
        generation = lastGeneration
        self.detail = detail
    }

    /// État à écrire pour cet événement, ou `nil` si rien ne change.
    public func next(_ event: Event, now: Date, memoryMB: Int?) -> DiagnosticSessionState? {
        switch event {
        case .foreground:
            guard !armed else { return nil }
            return DiagnosticSessionState(generation: generation &+ 1, state: .armed, updatedAt: now, memoryMB: memoryMB,
                                          detail: detail, ongoing: ongoing)
        case .inactive:
            return nil
        case .background:
            guard armed else { return nil }
            return DiagnosticSessionState(generation: generation, state: .closed, updatedAt: now, memoryMB: memoryMB,
                                          detail: detail)
        }
    }

    /// État armé à réécrire pour une nouvelle projection des travaux (E2c), ou pour une alerte mémoire ; `nil` si la
    /// session n'est pas armée ou si la projection est plus ancienne que la dernière adoptée.
    public func next(ongoing new: DiagnosticOngoing?, now: Date, memoryMB: Int?) -> DiagnosticSessionState? {
        guard armed else { return nil }
        if let new, new.revision < ongoing.revision { return nil }
        return DiagnosticSessionState(generation: generation, state: .armed, updatedAt: now, memoryMB: memoryMB,
                                      detail: detail, ongoing: new ?? ongoing)
    }

    /// Adopte une projection écrite avec succès.
    public mutating func commit(ongoing new: DiagnosticOngoing) {
        if new.revision >= ongoing.revision { ongoing = new }
    }

    /// Abandonne en mémoire une session dont la clôture n'a pas pu être écrite, au retour au premier plan : la
    /// transition suivante arme une **nouvelle** génération (revue R2 E2c, passage 5).
    public mutating func abandonAfterFailedClose() { armed = false }

    /// Adopte un état **écrit avec succès**.
    public mutating func commit(_ state: DiagnosticSessionState) {
        generation = state.generation
        armed = state.state == .armed
        detail = state.detail
    }

    /// Commodité des tests : `next` puis `commit` (écriture supposée réussie).
    public mutating func handle(_ event: Event, now: Date, memoryMB: Int?) -> DiagnosticSessionState? {
        guard let state = next(event, now: now, memoryMB: memoryMB) else { return nil }
        commit(state)
        return state
    }
}

/// Ce que le lancement apprend de la session précédente.
public enum DiagnosticPreviousSession: Equatable, Sendable {
    /// Rien à dire : pas de fichier, ou session close.
    case none
    /// Session restée armée. `ageSeconds` : temps depuis le dernier état **écrit**, `nil` si non crédible (horloge).
    case notClosed(ageSeconds: Int?, memoryMB: Int?, generation: UInt64)
    /// Fichier illisible, invalide, ou consommation impossible : aucune interruption affirmée.
    case unknown
}

/// Fichier d'état (`Application Support/KyokashoDiagnosticState/session.json` dans l'app ; dossier temporaire dans
/// les tests). Écritures atomiques, depuis une seule file.
public struct DiagnosticSessionFile: Sendable {
    public static let maxBytes = 4_096
    public let url: URL

    public init(folder: URL) { url = folder.appendingPathComponent("session.json") }

    public enum Read: Equatable, Sendable { case absent, unreadable, data(Data) }

    /// Une erreur de lecture n'est pas une absence. La lecture elle-même est bornée (au plus `maxBytes + 1` octets
    /// lus) et refuse un lien symbolique (`O_NOFOLLOW`) : revue R2 E2a, B3.
    public func read() -> Read {
        // Non bloquant : un tube nommé sans écrivain ne retient pas le lancement ; puis fichier ordinaire exigé
        // (revue R2 E2a passage 3, B3).
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return errno == ENOENT ? .absent : .unreadable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return .unreadable }
        guard let data = try? handle.read(upToCount: Self.maxBytes + 1) else { return .unreadable }
        guard data.count <= Self.maxBytes else { return .unreadable }
        return .data(data)
    }

    /// Remplacement atomique ; `false` si l'écriture échoue.
    @discardableResult
    public func write(_ state: DiagnosticSessionState) -> Bool {
        guard let data = try? DiagnosticSession.encoder.encode(state) else { return false }
        do {
            // Jamais de création du dossier ici : seul l'installateur le crée, avec l'exclusion de la sauvegarde
            // confirmée. Un dossier disparu fait échouer l'écriture (revue R2 E2a, B4).
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Résultat de la lecture du lancement.
    public struct Launch: Equatable, Sendable {
        public var previous: DiagnosticPreviousSession
        public var lastGeneration: UInt64
        /// Fenêtre de détail active pour ce lancement (posée par ce constat, ou encore en cours), sinon `nil`.
        public var detail: DiagnosticDetailWindow?
        /// Travaux suivis qui tournaient lors du dernier état écrit de la session non clôturée (E2c).
        public var ongoing: [DiagnosticOngoingEntry] = []
        public var ongoingTruncated = false
    }

    /// Lecture **une fois** au lancement : une session armée est d'abord remplacée par « close » (consommée), avec
    /// une fenêtre de détail de 24 h qui commence maintenant (E2b), puis rapportée ; si ce remplacement échoue, rien
    /// n'est affirmé (`.unknown`) et aucune fenêtre n'est ouverte. Une coupure entre les deux peut perdre le constat,
    /// jamais le doubler. Une session close garde sa fenêtre seulement si elle est encore active : une relance ne la
    /// prolonge jamais.
    public func consumeAtLaunch(now: Date) -> Launch {
        switch read() {
        case .absent: return Launch(previous: .none, lastGeneration: 0, detail: nil)
        case .unreadable: return Launch(previous: .unknown, lastGeneration: 0, detail: nil)
        case .data(let data):
            guard let state = DiagnosticSession.decode(data) else { return Launch(previous: .unknown, lastGeneration: 0, detail: nil) }
            guard state.state == .armed else {
                return Launch(previous: .none, lastGeneration: state.generation,
                              detail: state.detail.flatMap { $0.isActive(at: now) ? $0 : nil })
            }
            let window = DiagnosticDetailWindow.starting(at: now)
            let closed = DiagnosticSessionState(generation: state.generation, state: .closed, updatedAt: now, memoryMB: nil,
                                                detail: window)
            guard write(closed) else { return Launch(previous: .unknown, lastGeneration: state.generation, detail: nil) }
            return Launch(previous: .notClosed(ageSeconds: DiagnosticSession.age(from: state.updatedAt, now: now),
                                               memoryMB: state.memoryMB, generation: state.generation),
                          lastGeneration: state.generation, detail: window, ongoing: state.ongoing ?? [],
                          ongoingTruncated: state.ongoingTruncated ?? false)
        }
    }
}

public enum DiagnosticSession {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Clés permises : une clé inconnue rend l'état invalide (revue R2 E2a, B3).
    static let allowedKeys: Set<String> = ["schemaVersion", "generation", "state", "updatedAt", "memoryMB", "detail",
                                           "ongoing", "ongoingTruncated"]
    static let allowedDetailKeys: Set<String> = ["from", "until"]

    /// Validation avant usage : taille, clés, schéma, bornes. Tout écart → `nil` (état inconnu).
    public static func decode(_ data: Data) -> DiagnosticSessionState? {
        guard data.count <= DiagnosticSessionFile.maxBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: allowedKeys),
              (object["detail"].map { ($0 as? [String: Any]).map { Set($0.keys) == allowedDetailKeys } ?? false } ?? true),
              let state = try? decoder.decode(DiagnosticSessionState.self, from: data),
              state.schemaVersion == DiagnosticSessionState.schema,
              state.generation > 0,
              state.memoryMB.map({ (1...1_000_000).contains($0) }) ?? true,
              state.detail?.isWellFormed ?? true,
              (state.ongoing?.count ?? 0) <= DiagnosticOngoing.limit,
              state.ongoing?.allSatisfy({ $0.op > 0 }) ?? true,
              (object["ongoing"] as? [[String: Any]])?.allSatisfy({ Set($0.keys) == ["kind", "op"] }) ?? (object["ongoing"] == nil)
        else { return nil }
        return state
    }

    /// Âge en secondes, ou `nil` s'il n'est pas crédible (horloge reculée, ou plus d'un an).
    public static func age(from date: Date, now: Date) -> Int? {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 0, seconds <= 366 * 86_400 else { return nil }
        return Int(seconds)
    }
}
