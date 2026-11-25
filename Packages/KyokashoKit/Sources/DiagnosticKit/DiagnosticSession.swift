// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

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

    public init(generation: UInt64, state: Phase, updatedAt: Date, memoryMB: Int?) {
        schemaVersion = Self.schema
        self.generation = generation
        self.state = state
        self.updatedAt = updatedAt
        self.memoryMB = memoryMB.flatMap { $0 > 0 ? $0 : nil }
    }
}

/// Automate du cycle de vie, au niveau du **processus** (jamais d'une scène) : idempotent face aux notifications
/// doublées ou réordonnées. Rend l'état à écrire, ou `nil` si rien ne change.
public struct DiagnosticSessionMachine: Sendable {
    public enum Event: Sendable {
        /// `willEnterForeground`, `didBecomeActive`, ou application déjà au premier plan à l'installation.
        case foreground
        /// `willResignActive` / `.inactive` : sans effet (Centre de contrôle, Split View, sélecteur).
        case inactive
        /// `didEnterBackground` de l'application : la session est close, même s'il reste du travail.
        case background
    }

    public private(set) var generation: UInt64
    public private(set) var armed = false

    public init(lastGeneration: UInt64 = 0) { generation = lastGeneration }

    public mutating func handle(_ event: Event, now: Date, memoryMB: Int?) -> DiagnosticSessionState? {
        switch event {
        case .foreground:
            guard !armed else { return nil }
            armed = true
            generation &+= 1
            return DiagnosticSessionState(generation: generation, state: .armed, updatedAt: now, memoryMB: memoryMB)
        case .inactive:
            return nil
        case .background:
            guard armed else { return nil }
            armed = false
            return DiagnosticSessionState(generation: generation, state: .closed, updatedAt: now, memoryMB: memoryMB)
        }
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

    /// Une erreur de lecture n'est pas une absence.
    public func read() -> Read {
        do {
            return .data(try Data(contentsOf: url))
        } catch let error as NSError where (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError)
                                          || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)) {
            return .absent
        } catch {
            return .unreadable
        }
    }

    /// Remplacement atomique ; `false` si l'écriture échoue.
    @discardableResult
    public func write(_ state: DiagnosticSessionState) -> Bool {
        guard let data = try? DiagnosticSession.encoder.encode(state) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Lecture **une fois** au lancement : une session armée est d'abord remplacée par « close » (consommée), puis
    /// rapportée ; si ce remplacement échoue, rien n'est affirmé (`.unknown`). Une coupure entre les deux peut
    /// perdre le constat, jamais le doubler.
    public func consumeAtLaunch(now: Date) -> (previous: DiagnosticPreviousSession, lastGeneration: UInt64) {
        switch read() {
        case .absent: return (.none, 0)
        case .unreadable: return (.unknown, 0)
        case .data(let data):
            guard let state = DiagnosticSession.decode(data) else { return (.unknown, 0) }
            guard state.state == .armed else { return (.none, state.generation) }
            let closed = DiagnosticSessionState(generation: state.generation, state: .closed, updatedAt: now, memoryMB: nil)
            guard write(closed) else { return (.unknown, state.generation) }
            return (.notClosed(ageSeconds: DiagnosticSession.age(from: state.updatedAt, now: now), memoryMB: state.memoryMB,
                               generation: state.generation), state.generation)
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

    /// Validation avant usage : taille, schéma, bornes. Tout écart → `nil` (état inconnu).
    public static func decode(_ data: Data) -> DiagnosticSessionState? {
        guard data.count <= DiagnosticSessionFile.maxBytes,
              let state = try? decoder.decode(DiagnosticSessionState.self, from: data),
              state.schemaVersion == DiagnosticSessionState.schema,
              state.generation > 0,
              state.memoryMB.map({ (1...1_000_000).contains($0) }) ?? true
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
