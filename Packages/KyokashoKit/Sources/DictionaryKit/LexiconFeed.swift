// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import YomitanKit

// PLAN-LEX-001, étape E2 : état de la liste du Lexique, sans SwiftUI pour être testé sur Mac. L'écran
// (`App/Dictionary/LexiconView.swift`) ne fait qu'afficher cet état et demander la page suivante.

/// Liste paginée du Lexique : les mots déjà lus, la clé de la page suivante, et la **demande** en cours.
///
/// Invariants :
/// - une page n'est ajoutée que si elle répond à la demande en cours (`request`) : après un changement de recherche
///   ou de dictionnaires, la réponse tardive d'une ancienne lecture est jetée (`accept` renvoie `false`) ;
/// - un mot n'apparaît qu'une fois, même si la base a changé entre deux pages (dictionnaire installé pendant le
///   défilement) : un identifiant déjà affiché n'est pas ajouté de nouveau ;
/// - une seule lecture à la fois (`isLoading`), jamais de seconde demande pour la même page.
public struct LexiconFeed: Equatable, Sendable {
    /// Entrées lues par page (une page compte souvent moins de mots : plusieurs entrées par mot).
    public static let pageSize = 200
    /// Nombre de lignes avant la fin à partir duquel la page suivante est demandée (défilement sans attente).
    public static let prefetchDistance = 40

    public private(set) var words: [LexiconWord] = []
    public private(set) var next: LexiconCursor?
    public private(set) var reachedEnd = false
    public private(set) var isLoading = false
    /// Début de mot cherché (DEC-07), déjà nettoyé ; vide : toute la liste.
    public private(set) var prefix = ""
    /// Change à chaque `reset` : identifie la demande à laquelle une page répond.
    public private(set) var request = 0
    private var shown: Set<String> = []

    public init() {}

    /// Nettoie le texte tapé : espaces autour retirés (un espace seul ne cherche rien).
    public static func cleanPrefix(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Repart d'une liste vide (nouvelle recherche, dictionnaires changés). Renvoie le numéro de la nouvelle demande.
    @discardableResult
    public mutating func reset(prefix: String = "") -> Int {
        words = []
        shown = []
        next = nil
        reachedEnd = false
        isLoading = false
        self.prefix = Self.cleanPrefix(prefix)
        request &+= 1
        return request
    }

    /// Une lecture peut-elle partir maintenant ? Si oui, elle est notée en cours et sa demande est renvoyée avec la
    /// clé de reprise à passer à `DictionaryDatabase.lexiconPage`.
    public mutating func beginLoading() -> (request: Int, after: LexiconCursor?, prefix: String)? {
        guard !isLoading, !reachedEnd else { return nil }
        isLoading = true
        return (request, next, prefix)
    }

    /// Ajoute la page si elle répond à la demande en cours. `false` : réponse d'une ancienne demande, jetée.
    @discardableResult
    public mutating func accept(_ page: LexiconPage, request: Int) -> Bool {
        guard request == self.request else { return false }
        isLoading = false
        for word in page.words where shown.insert(word.id).inserted { words.append(word) }
        next = page.next
        reachedEnd = page.next == nil
        return true
    }

    /// Lecture en échec ou annulée pour la demande en cours : la liste reste, une nouvelle tentative est possible.
    public mutating func fail(request: Int) {
        guard request == self.request else { return }
        isLoading = false
    }

    /// La ligne `id` vient d'apparaître : faut-il lire la page suivante ? Vrai près de la fin de la liste.
    public func shouldLoadMore(appearing id: String) -> Bool {
        guard !isLoading, !reachedEnd else { return false }
        let tail = words.suffix(Self.prefetchDistance)
        return tail.contains { $0.id == id }
    }
}

extension LexiconWord {
    /// Forme japonaise découpée pour l'affichage, lecture répartie au-dessus des kanji (même fonction que les fiches
    /// du dictionnaire). Sans lecture à afficher (DEC-04) : la forme seule.
    public var furigana: [JapaneseText.FuriganaSegment] {
        guard let reading else { return [JapaneseText.FuriganaSegment(expression, "")] }
        return JapaneseText.distributeFurigana(expression, reading)
    }
}
