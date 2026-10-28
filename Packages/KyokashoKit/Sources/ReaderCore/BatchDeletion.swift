// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Suppression de plusieurs documents à la fois, avec **double confirmation** (demande de NOxygen59, recette
/// 1.3.2 (61)). Sans UIKit pour être testée sur Mac.
///
/// Rien n'est effacé tant que les deux confirmations n'ont pas été données dans l'ordre ; une annulation à n'importe
/// quelle étape revient à la sélection, intacte. La liste effacée est celle de la sélection au moment de la seconde
/// confirmation, limitée aux documents qui existent encore.
public struct BatchDeletion: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// Choix des documents (cases à cocher sur l'accueil).
        case selecting
        /// Première question : « Supprimer N documents ? »
        case firstConfirmation
        /// Seconde question, plus explicite : effacement définitif.
        case secondConfirmation
    }

    public private(set) var selected: Set<String> = []
    public private(set) var step: Step = .selecting

    public init() {}

    public mutating func toggle(_ id: String) {
        guard step == .selecting else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    public mutating func selectAll(_ ids: [String]) {
        guard step == .selecting else { return }
        selected = Set(ids)
    }

    /// « Supprimer (N) » : première question, seulement s'il y a une sélection.
    public mutating func requestDeletion() {
        guard step == .selecting, !selected.isEmpty else { return }
        step = .firstConfirmation
    }

    /// Réponse « Oui » à la première question : seconde question.
    public mutating func confirmFirst() {
        guard step == .firstConfirmation else { return }
        step = .secondConfirmation
    }

    /// Réponse « Effacer » à la seconde question : identifiants à effacer (ceux qui existent encore), puis la
    /// sélection est vidée. Hors de la seconde question : rien.
    public mutating func confirmSecond(existing: Set<String>) -> [String] {
        guard step == .secondConfirmation else { return [] }
        let ids = selected.intersection(existing).sorted()
        selected = []
        step = .selecting
        return ids
    }

    /// Annuler à n'importe quelle étape : retour à la sélection, intacte.
    public mutating func cancel() { step = .selecting }
}
