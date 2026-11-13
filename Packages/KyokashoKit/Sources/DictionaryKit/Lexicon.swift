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

    public init(words: [LexiconWord] = [], next: LexiconCursor? = nil) {
        self.words = words
        self.next = next
    }
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

    /// Mots précis du Lexique (filtre « Mes mots » : les mots que l'utilisateur a enregistrés d'une étoile), triés
    /// comme la liste (lecture, puis forme). Un mot absent des dictionnaires passés (désactivé, autre variante de
    /// langue, mot enregistré depuis un dictionnaire supprimé) n'est pas renvoyé : rien n'est inventé pour lui.
    ///
    /// - Parameter entries: (forme, lecture) ; une lecture vide vaut la forme, comme à l'import des dictionnaires.
    ///
    /// Lecture seule, à appeler hors du fil principal ; une tâche annulée arrête la lecture (`CancellationError`).
    public func lexiconWords(dictionaryIds: Set<Int64>,
                             entries: [(expression: String, reading: String)]) throws -> [LexiconWord] {
        guard !dictionaryIds.isEmpty, !entries.isEmpty else { return [] }
        let ids = dictionaryIds.sorted()
        return try writer.read { db in
            let infos = try DictionaryInfo.filter(ids.contains(Column("id"))).fetchAll(db)
            var titles: [Int64: String] = [:]
            var priorities: [Int64: Int] = [:]
            for info in infos {
                guard let id = info.id else { continue }
                titles[id] = info.title
                priorities[id] = info.priority
            }
            var seen = Set<WordKey>()
            var words: [LexiconWord] = []
            for entry in entries {
                if Task.isCancelled { throw CancellationError() }
                let key = WordKey(reading: entry.reading.isEmpty ? entry.expression : entry.reading, expression: entry.expression)
                guard seen.insert(key).inserted else { continue }
                let rows = try Self.lexiconRows(db, ids: ids, word: key)
                guard !rows.isEmpty else { continue }
                words.append(Self.word(key, rows: rows, titles: titles, priorities: priorities))
            }
            return words.sorted { ($0.sortReading, $0.expression) < ($1.sortReading, $1.expression) }
        }
    }

    /// Mots d'une page (PLAN-CARTES-001, E2) : pour chaque forme, le mot des dictionnaires donnés qui l'écrit ainsi,
    /// en une seule lecture de la base (index `term_expression`). Plusieurs lectures pour une forme (上手 じょうず /
    /// うわて) : celle de `readingHint` si une source la donne, sinon celle de la source la plus prioritaire.
    /// Formes absentes de tous les dictionnaires : pas de clé dans le résultat (DEC-CA-02 : seuls les mots trouvés
    /// sont proposés). Annuler la tâche appelante arrête la lecture entre deux formes.
    public func lexiconWords(dictionaryIds: Set<Int64>,
                             expressions: [(expression: String, readingHint: String)]) throws -> [String: LexiconWord] {
        guard !dictionaryIds.isEmpty, !expressions.isEmpty else { return [:] }
        let ids = dictionaryIds.sorted()
        return try writer.read { db in
            var titles: [Int64: String] = [:]
            var priorities: [Int64: Int] = [:]
            for info in try DictionaryInfo.filter(ids.contains(Column("id"))).fetchAll(db) {
                guard let id = info.id else { continue }
                titles[id] = info.title
                priorities[id] = info.priority
            }
            let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let sql = """
                SELECT id, dictionaryId, expression, reading, glossary FROM term INDEXED BY term_expression
                WHERE expression = ? AND dictionaryId IN (\(marks)) ORDER BY reading, id
                """
            var found: [String: LexiconWord] = [:]
            for (expression, hint) in expressions where found[expression] == nil {
                if Task.isCancelled { throw CancellationError() }
                var arguments: [any DatabaseValueConvertible] = [expression]
                arguments += ids
                let groups = Self.group(try Self.fetch(db, sql: sql, arguments: StatementArguments(arguments)))
                guard !groups.isEmpty else { continue }
                // Revue D-07 F10 : lecture comparée en hiragana des deux côtés (un dictionnaire peut stocker des katakana).
                let hiraganaHint = Self.hiragana(hint)
                let best = groups.first { !hint.isEmpty && Self.hiragana($0.key.reading) == hiraganaHint } ?? groups.min { a, b in
                    let pa = a.rows.map { priorities[$0.dictionaryId] ?? Int.max }.min() ?? Int.max
                    let pb = b.rows.map { priorities[$0.dictionaryId] ?? Int.max }.min() ?? Int.max
                    return pa != pb ? pa < pb : a.rows.count > b.rows.count
                }!
                let word = Self.word(best.key, rows: best.rows, titles: titles, priorities: priorities)
                if !word.senses.isEmpty { found[expression] = word }
            }
            return found
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

    static func hiragana(_ text: String) -> String {
        text.applyingTransform(.hiraganaToKatakana, reverse: true) ?? text
    }

    /// Hiragana, katakana et marque de prolongation seulement.
    static func isKana(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { (0x3041...0x30FF).contains($0.value) || $0.value == 0x30FC }
    }
}
