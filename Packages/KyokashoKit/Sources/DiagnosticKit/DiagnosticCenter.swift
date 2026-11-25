// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Lignes du journal (contrat lu par les outils et les agents, `docs/DEBOGAGE.md`) : heure ISO, niveau, zone, puis
/// soit les champs d'un événement typé, soit l'ancien message. Une ligne tient toujours sur **une** ligne.
public enum DiagnosticLine {
    /// Relevé d'un moniteur (CPU, fils) : même en-tête que les événements (`op`, `étape`), puis les mesures. Le texte
    /// des mesures n'est fait que de nombres et de noms de fils filtrés (`DiagnosticThreads.safeName`) par
    /// `DiagnosticCPULog` (AV-DIAG-001, AV-03).
    public static func monitor(_ level: DiagnosticLevel, zone: DiagnosticZone, op: DiagnosticOperation, step: StaticString,
                               measures: String, at date: Date, timeZone: TimeZone = .current) -> String {
        "\(stamp(date, timeZone)) [\(level.rawValue)] [\(zone.rawValue)] op=\(op.text) étape=\(step) issue=etape \(oneLine(measures))"
    }

    /// Ancien format : `ISO [niveau] [zone] message` (compatibilité de lecture, PLAN-DIAG-001 E1).
    public static func legacy(_ level: DiagnosticLevel, area: String, message: String, at date: Date,
                              timeZone: TimeZone = .current) -> String {
        "\(stamp(date, timeZone)) [\(level.rawValue)] [\(area)] \(oneLine(message))"
    }

    /// Événement typé : `ISO [niveau] [zone] op=… parent=… étape=… issue=… cause=… t=…ms mem=…Mo doc=… nom=valeur…`.
    /// Les champs absents ne sont pas écrits.
    public static func event(_ e: DiagnosticEvent, at date: Date, timeZone: TimeZone = .current) -> String {
        var parts = ["\(stamp(date, timeZone)) [\(e.level.rawValue)] [\(e.zone.rawValue)]"]
        if let op = e.op { parts.append("op=\(op.text)") }
        if let parent = e.parent { parts.append("parent=\(parent.text)") }
        parts.append("étape=\(oneLine(e.step.description).replacingOccurrences(of: " ", with: "_"))")
        parts.append("issue=\(e.outcome.rawValue)")
        if e.cause != .aucune { parts.append("cause=\(e.cause.text)") }
        if let ms = e.durationMs { parts.append("t=\(ms)ms") }
        if let mb = e.memoryMB { parts.append("mem=\(mb)Mo") }
        if let ref = e.ref { parts.append("doc=\(ref.text)") }
        for count in e.counts { parts.append("\(count.name.description)=\(count.value)") }
        return parts.joined(separator: " ")
    }

    static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func stamp(_ date: Date, _ timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// Point d'entrée des événements pour l'app **et** les paquets (PLAN-DIAG-001, E1). Sans récepteur branché, rien ne
/// se passe. Le filtrage (`info` seulement en mode diagnostic) se fait **avant** de construire l'événement.
///
/// Concurrence : l'état est sous un `NSLock` ; le récepteur est appelé **hors du verrou**, il peut donc lui-même
/// émettre sans interblocage. Une émission depuis l'intérieur du récepteur (même fil) est ignorée et comptée : un
/// récepteur qui journalise ses propres erreurs ne peut pas boucler.
public final class DiagnosticCenter: @unchecked Sendable {
    public typealias Sink = @Sendable (DiagnosticEvent) -> Void

    /// Centre de l'app. Les tests créent leurs propres centres (pas d'état global partagé entre tests parallèles).
    public static let shared = DiagnosticCenter()

    private let lock = NSLock()
    private var sink: Sink?
    private var detailed = false
    /// Fenêtre de détail automatique (E2b) : s'ajoute au mode manuel, sans le changer.
    private var autoDetail: DiagnosticDetailWindow?
    private let now: @Sendable () -> Date
    private var salt: UInt64 = 0
    private var reentrantDrops = 0
    private static let reentrancyKey = "fr.noxygen59.kyokasho.diagnostic.inSink"

    /// `now` : horloge injectable (tests de l'échéance) ; l'échéance est vérifiée à chaque émission, même sans relance.
    public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

    /// Branche le récepteur, une seule fois : un second branchement est refusé (`false`), pour qu'un module ne puisse
    /// pas détourner le journal.
    @discardableResult
    public func install(sink: @escaping Sink, salt: UInt64) -> Bool {
        lock.withLock {
            guard self.sink == nil else { return false }
            self.sink = sink
            self.salt = salt
            return true
        }
    }

    /// Mode diagnostic : les événements `info` ne passent que s'il est allumé (ou pendant une fenêtre automatique).
    public func setDetailed(_ on: Bool) { lock.withLock { detailed = on } }

    /// Fenêtre de détail automatique après une session non clôturée (E2b) ; `nil` pour aucune.
    public func setAutoDetail(_ window: DiagnosticDetailWindow?) { lock.withLock { autoDetail = window } }

    /// Vrai pendant une fenêtre automatique valide à cet instant.
    public var autoDetailActive: Bool { lock.withLock { autoDetailNow() } }

    /// Fenêtre active ? Une fois l'échéance atteinte, la fenêtre est oubliée : reculer l'horloge ne la rouvre pas
    /// (revue R2 E2b, B2). À appeler sous le verrou.
    private func autoDetailNow() -> Bool {
        guard let window = autoDetail else { return false }
        let current = now()
        if current >= window.until { autoDetail = nil; return false }
        return window.isActive(at: current)
    }

    /// Détail effectif : manuel OU fenêtre automatique valide. À appeler sous le verrou.
    private var detailNow: Bool { detailed || autoDetailNow() }

    /// Référence courte et salée d'un document pour ce journal (`DiagnosticRef`).
    public func ref(_ documentId: String) -> DiagnosticDocumentRef {
        DiagnosticDocumentRef(text: DiagnosticRef.short(documentId, salt: lock.withLock { salt }))
    }

    /// Vrai si un événement de ce niveau serait écrit : permet d'éviter un calcul coûteux (mémoire, durée).
    public func wants(_ level: DiagnosticLevel) -> Bool {
        lock.withLock { sink != nil && (level != .info || detailNow) }
    }

    /// Émissions ignorées parce qu'elles venaient du récepteur lui-même (lu et remis à zéro).
    public func takeReentrantDrops() -> Int { lock.withLock { defer { reentrantDrops = 0 }; return reentrantDrops } }

    /// Émet un événement. `make` n'est évalué que si le niveau passe le filtre.
    public func emit(_ level: DiagnosticLevel, _ make: @autoclosure () -> DiagnosticEvent) {
        let thread = Thread.current.threadDictionary
        let target: Sink? = lock.withLock {
            guard let sink, level != .info || detailNow else { return nil }
            if thread[Self.reentrancyKey] != nil { reentrantDrops += 1; return nil }
            return sink
        }
        guard let target else { return }
        var event = make()
        event.level = level
        thread[Self.reentrancyKey] = true
        defer { thread.removeObject(forKey: Self.reentrancyKey) }
        target(event)
    }
}

/// Règles du fichier journal, sans accès au disque (testées) : rotation (DEC-06). La mise à l'écart des anciens
/// fichiers (DEC-07) est dans `DiagnosticFileMigration`.
public enum DiagnosticJournalPolicy {
    /// DEC-06 B : au-delà de 5 Mo, le journal devient `journal.1.txt` (l'ancien `journal.1.txt` est remplacé) et un
    /// nouveau journal commence.
    public static let rotationBytes = 5_000_000
    public static let currentName = "journal.txt"
    public static let previousName = "journal.1.txt"

    public static func shouldRotate(currentBytes: Int) -> Bool { currentBytes > rotationBytes }

    /// File d'écriture bornée : au-delà, les lignes sont perdues et comptées (une ligne d'alerte le dit ensuite).
    public static let maxPendingLines = 2_000
}
