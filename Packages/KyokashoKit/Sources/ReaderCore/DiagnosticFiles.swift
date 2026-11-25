// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DiagnosticKit
import Foundation

/// Niveau d'une ligne du journal : déplacé dans `DiagnosticKit` (PLAN-DIAG-001, E1), alias gardé pour les appelants.
public typealias DiagnosticLevel = DiagnosticKit.DiagnosticLevel

/// Fichiers de diagnostic (journal et relevé de batterie) : quand ils deviennent trop gros, l'utilisateur doit le
/// savoir et pouvoir les partager puis les effacer. Décision pure, testée, sans accès au disque.
///
/// Demande de NOxygen59 du 10/11/2026 : une bannière **permanente**, dans la bibliothèque comme dans le lecteur,
/// tant que les fichiers dépassent les seuils ; elle disparaît d'elle-même une fois les fichiers effacés.
public enum DiagnosticFiles {
    /// Rotation du journal : au-delà, il devient `journal.1.txt` et un nouveau journal commence (DEC-06 B, 5 Mo).
    public static let journalRotationBytes = DiagnosticJournalPolicy.rotationBytes
    /// Rotation du relevé de batterie : **au-dessus** du seuil d'alerte (1 Mo), sinon le fichier serait coupé avant de
    /// pouvoir dépasser 1 Mo et la bannière ne resterait jamais affichée (relevé de 12 jours ≈ 1,5 Mo).
    public static let energyRotationBytes = 2_000_000
    /// Seuil d'avertissement du journal : 1,5 Mo.
    public static let journalWarningBytes = 1_500_000
    /// Seuil d'avertissement du relevé : 1 Mo.
    public static let energyWarningBytes = 1_000_000

    public struct Warning: Equatable, Sendable {
        public var journalBytes: Int
        public var energyBytes: Int
        /// Total des deux fichiers en Mo, arrondi à 0,1 Mo près : la valeur affichée dans la bannière.
        public var megabytes: Double
    }

    /// `nil` tant que **les deux** fichiers restent sous leur seuil : la bannière n'a alors rien à dire, et elle
    /// disparaît dès que « Effacer » a ramené les deux fichiers sous les seuils.
    public static func warning(journalBytes: Int, energyBytes: Int) -> Warning? {
        guard journalBytes > journalWarningBytes || energyBytes > energyWarningBytes else { return nil }
        let total = Double(max(0, journalBytes) + max(0, energyBytes)) / 1_000_000
        return Warning(journalBytes: journalBytes, energyBytes: energyBytes, megabytes: (total * 10).rounded() / 10)
    }

    /// Une ligne du journal : heure ISO, niveau, zone, message. Contrat lu par les outils et les agents
    /// (`docs/DEBOGAGE.md`) : le message tient toujours sur **une** ligne, sinon un événement compterait pour plusieurs.
    public static func journalLine(_ level: DiagnosticLevel, area: String, message: String, at date: Date,
                                   timeZone: TimeZone = .current) -> String {
        DiagnosticLine.legacy(level, area: area, message: message, at: date, timeZone: timeZone)
    }
}
