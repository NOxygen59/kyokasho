// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB

// PLAN-LEX-001, étape E1 (plan approuvé par NOxygen59 le 10/11/2026) : lecture paginée de **tous** les termes des
// dictionnaires installés et actifs, pour la future catégorie « Lexique ». Fondation sans écran (l'écran vient en E2).
//
// Décisions appliquées : DEC-01 A (une ligne par mot = forme + lecture, sens de chaque source regroupés), DEC-02 A
// (sens absent dans une langue = `nil`, l'écran affiche « — », rien n'est recopié ni traduit), DEC-03 A (ordre par
// lecture), DEC-04 A (pas de lecture affichée quand elle répète le mot), DEC-05 A (ligne courte + définition
// entière), DEC-06 A (l'app passe la même liste de dictionnaires que la recherche), DEC-07 A (début de mot).

/// Langue des sens d'un dictionnaire, tirée de son titre (catalogue et lexique fourni). Jamais devinée depuis le
/// texte : l'heuristique `isEnglish` des traductions de définitions n'est pas fiable pour classer une source entière.
public enum LexiconLanguage: String, Sendable, CaseIterable {
    case french = "fr", english = "en", chinese = "zh-Hans", unknown

    public static func forDictionary(title: String) -> LexiconLanguage {
        if let variant = BundledLexicon.language(forTitle: title) {
            switch variant {
            case .french: return .french
            case .english: return .english
            case .chinese: return .chinese
            }
        }
        switch DictionaryCatalog.entry(forInstalledTitle: title)?.language {
        case .french: return .french
        case .english: return .english
        case nil: return .unknown
        }
    }
}

/// Un sens d'un mot, tel qu'une source le donne.
public struct LexiconSense: Hashable, Sendable {
    public let dictionaryId: Int64
    public let dictionaryTitle: String
    public let language: LexiconLanguage
    /// Une ou deux lignes pour la liste (DEC-05).
    public let short: String
    /// Définition entière pour la fiche.
    public let full: String
}

/// Une ligne du Lexique : un mot (forme + lecture) et ses sens de toutes les sources actives (DEC-01).
public struct LexiconWord: Hashable, Sendable, Identifiable {
    public var id: String { expression + "\u{1}" + sortReading }
    public let expression: String
    /// Lecture à afficher ; `nil` quand elle répète le mot (DEC-04 : l'importeur recopie le mot faute de lecture).
    public let reading: String?
    /// Lecture qui sert au tri (toujours renseignée : l'importeur remplace une lecture vide par le mot).
    public let sortReading: String
    /// Sens triés par priorité des dictionnaires puis par entrée.
    public let senses: [LexiconSense]

    /// Premier sens court dans cette langue ; `nil` s'il n'y en a pas (DEC-02 : l'écran affiche « — »).
    public func summary(_ language: LexiconLanguage) -> String? {
        senses.first { $0.language == language && !$0.short.isEmpty }?.short
    }
}

/// Clé de reprise : la page suivante commence **après** ce mot, jamais au milieu.
public struct LexiconCursor: Hashable, Sendable, Codable {
    public let reading: String
    public let expression: String
    public init(reading: String, expression: String) {
        self.reading = reading
        self.expression = expression
    }
}

public struct LexiconPage: Sendable {
    public let words: [LexiconWord]
    /// `nil` : dernière page.
    public let next: LexiconCursor?
}

extension DictionaryDatabase {
    /// Longueur de la ligne courte d'un sens (DEC-05).
    public static let lexiconShortLength = 90

    /// Une page du Lexique, triée par (lecture, forme, entrée), sans doublon ni trou d'une page à l'autre.
    ///
    /// - Parameters:
    ///   - dictionaryIds: dictionnaires à lire, **déjà filtrés par l'app avec la même règle que la recherche**
    ///     (activés, avec des termes, variante de langue du lexique fourni retenue). Rien n'est mémorisé ici.
    ///   - after: clé de reprise de la page précédente ; `nil` pour la première page.
    ///   - prefix: début de mot (DEC-07) : en kana, comparé à la lecture ; sinon à la forme écrite.
    ///   - limit: nombre d'entrées lues au plus (une page compte souvent moins de mots, plusieurs entrées par mot).
    ///
    /// Lecture seule (pool de lecture GRDB, sans écrire) ; à appeler hors du fil principal. Une tâche annulée arrête la
    /// lecture entre deux lignes (`CancellationError`).
    public func lexiconPage(dictionaryIds: Set<Int64>, after: LexiconCursor? = nil, prefix: String = "",
                            limit: Int = 200) throws -> LexiconPage {
        guard !dictionaryIds.isEmpty else { return LexiconPage(words: [], next: nil) }
        let ids = dictionaryIds.sorted()
        let boundedLimit = max(20, min(limit, 2_000))
        return try writer.read { db in
            let infos = try DictionaryInfo.filter(ids.contains(Column("id"))).fetchAll(db)
            var titles: [Int64: String] = [:]
            var priorities: [Int64: Int] = [:]
            for info in infos {
                guard let id = info.id else { continue }
                titles[id] = info.title
                priorities[id] = info.priority
            }
            let rows = try Self.lexiconRows(db, ids: ids, after: after, prefix: prefix, limit: boundedLimit)
            var groups = Self.group(rows)
            var next: LexiconCursor?
            if rows.count == boundedLimit, let last = groups.last {
                // La dernière entrée lue peut couper un mot (homographes) : ce mot est relu en entier s'il est seul
                // sur la page, sinon reporté à la page suivante. Une page ne coupe jamais un mot.
                if groups.count == 1 {
                    let whole = try Self.lexiconRows(db, ids: ids, word: last.key)
                    groups = Self.group(whole)
                } else {
                    groups.removeLast()
                }
                if let kept = groups.last {
                    next = LexiconCursor(reading: kept.key.reading, expression: kept.key.expression)
                }
            }
            let words = groups.map { group in
                Self.word(group.key, rows: group.rows, titles: titles, priorities: priorities)
            }
            return LexiconPage(words: words, next: next)
        }
    }

    // MARK: - Lecture

    struct LexiconRow {
        let id: Int64
        let dictionaryId: Int64
        let expression: String
        let reading: String
        let glossary: String
    }

    struct WordKey: Hashable {
        let reading: String
        let expression: String
    }

    private static func lexiconRows(_ db: Database, ids: [Int64], after: LexiconCursor?, prefix: String,
                                    limit: Int) throws -> [LexiconRow] {
        var conditions = ["dictionaryId IN (\(Array(repeating: "?", count: ids.count).joined(separator: ",")))"]
        var arguments: [any DatabaseValueConvertible] = ids
        // Index imposé : sans statistiques, SQLite choisissait `term_dictionary` puis triait **toute** la table à
        // chaque page (plan mesuré le 10/11/2026). Par la lecture, il parcourt l'index et s'arrête à la page remplie
        // (seuls forme et id sont triés à l'intérieur d'une même lecture). Un début de mot en kanji passe par
        // `term_expression` : le sous-ensemble est petit, son tri par lecture aussi.
        let byExpression = !prefix.isEmpty && !isKana(prefix)
        if !prefix.isEmpty {
            let column = byExpression ? "expression" : "reading"
            conditions.append("\(column) >= ? AND \(column) < ?")
            arguments += [prefix, prefix + "\u{10FFFF}"]
        }
        if let after {
            // Après le mot entier : toutes ses entrées ont la même (lecture, forme). `reading >= ?` d'abord, pour que
            // la clé de reprise serve de point de départ dans l'index.
            conditions.append("reading >= ? AND (reading > ? OR expression > ?)")
            arguments += [after.reading, after.reading, after.expression]
        }
        let sql = """
            SELECT id, dictionaryId, expression, reading, glossary FROM term
            INDEXED BY \(byExpression ? "term_expression" : "term_reading")
            WHERE \(conditions.joined(separator: " AND "))
            ORDER BY reading, expression, id LIMIT ?
            """
        arguments.append(limit)
        return try fetch(db, sql: sql, arguments: StatementArguments(arguments))
    }

    private static func lexiconRows(_ db: Database, ids: [Int64], word: WordKey) throws -> [LexiconRow] {
        let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = """
            SELECT id, dictionaryId, expression, reading, glossary FROM term
            WHERE dictionaryId IN (\(marks)) AND reading = ? AND expression = ? ORDER BY id
            """
        var arguments: [any DatabaseValueConvertible] = ids
        arguments += [word.reading, word.expression]
        return try fetch(db, sql: sql, arguments: StatementArguments(arguments))
    }

    private static func fetch(_ db: Database, sql: String, arguments: StatementArguments) throws -> [LexiconRow] {
        var rows: [LexiconRow] = []
        let cursor = try Row.fetchCursor(db, sql: sql, arguments: arguments)
        while let r = try cursor.next() {
            if Task.isCancelled { throw CancellationError() }
            rows.append(LexiconRow(id: r[0], dictionaryId: r[1], expression: r[2], reading: r[3], glossary: r[4]))
        }
        return rows
    }

    // MARK: - Regroupement

    /// Entrées consécutives d'un même mot (la requête est triée par lecture puis forme).
    static func group(_ rows: [LexiconRow]) -> [(key: WordKey, rows: [LexiconRow])] {
        var groups: [(key: WordKey, rows: [LexiconRow])] = []
        for row in rows {
            let key = WordKey(reading: row.reading, expression: row.expression)
            if groups.last?.key == key {
                groups[groups.count - 1].rows.append(row)
            } else {
                groups.append((key, [row]))
            }
        }
        return groups
    }

    static func word(_ key: WordKey, rows: [LexiconRow], titles: [Int64: String], priorities: [Int64: Int]) -> LexiconWord {
        let ordered = rows.sorted {
            let a = priorities[$0.dictionaryId] ?? Int.max, b = priorities[$1.dictionaryId] ?? Int.max
            return a != b ? a < b : $0.id < $1.id
        }
        let senses = ordered.compactMap { row -> LexiconSense? in
            let full = GlossaryText.plain(row.glossary, limit: Int.max)
            // Glossaire vide ou `"null"` : pas de sens, mais le mot reste (une autre source peut en donner).
            guard !full.isEmpty else { return nil }
            let title = titles[row.dictionaryId] ?? ""
            return LexiconSense(dictionaryId: row.dictionaryId, dictionaryTitle: title,
                                language: LexiconLanguage.forDictionary(title: title),
                                short: shortened(full), full: full)
        }
        return LexiconWord(expression: key.expression, reading: key.reading == key.expression ? nil : key.reading,
                           sortReading: key.reading, senses: senses)
    }

    static func shortened(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard flat.count > lexiconShortLength else { return flat }
        return String(flat.prefix(lexiconShortLength - 1)) + "…"
    }

    /// Hiragana, katakana et marque de prolongation seulement.
    static func isKana(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { (0x3041...0x30FF).contains($0.value) || $0.value == 0x30FC }
    }
}
