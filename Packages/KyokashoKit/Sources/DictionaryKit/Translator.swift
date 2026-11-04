// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import YomitanKit

/// Résultat d'une recherche : un mot (expression + lecture) avec ses définitions de tous les
/// dictionnaires actifs, ses fréquences, son accent.
public struct TermResult: Identifiable, Sendable, Equatable {
    public var id: String { expression + "|" + reading }
    public let expression: String
    public let reading: String
    /// Texte de la page reconnu (ex. « 食べさせられた »).
    public let matchedText: String
    public var matchLength: Int { matchedText.count }
    /// Transformations depuis la forme du dictionnaire (identifiants Yomitan).
    public let inflectionRules: [String]
    public var definitions: [Definition]
    public var frequencies: [Frequency]
    public var pitches: [Pitch]
    public var ipa: [IPA]

    public struct Definition: Sendable, Equatable {
        public let dictionaryId: Int64
        public let dictionaryTitle: String
        public let tags: [TagRow]
        public let termTags: [TagRow]
        public let rules: [String]
        /// Tableau `glossary` (JSON) tel quel : rendu par `GlossaryRenderer`.
        public let glossaryJSON: String
        public let score: Int
        public let sequence: Int
    }

    public struct Frequency: Sendable, Equatable {
        public let dictionaryTitle: String
        public let display: String
        public let value: Int?
    }

    public struct Pitch: Sendable, Equatable {
        public let dictionaryTitle: String
        /// Position de la chute (0 = plat) ; ou motif « HLL » s'il est donné.
        public let downstep: Int?
        public let pattern: String?
        public let tags: [String]
    }

    public struct IPA: Sendable, Equatable {
        public let dictionaryTitle: String
        public let transcription: String
    }
}

public struct KanjiResult: Sendable, Equatable {
    public let character: String
    public let entries: [Entry]
    public let frequencies: [TermResult.Frequency]

    public struct Entry: Sendable, Equatable {
        public let dictionaryTitle: String
        public let onyomi: [String]
        public let kunyomi: [String]
        public let meanings: [String]
        public let stats: [String: String]
        public let tags: [String]
    }
}

/// Options de recherche (une partie d'un profil).
public struct LookupOptions: Codable, Sendable, Equatable {
    /// Nombre de caractères examinés à partir du point touché.
    public var scanLength = 16
    public var maxResults = 24
    /// Filtrer par partie du discours (comme Yomitan) : évite les fausses déconjugaisons.
    public var partsOfSpeechFilter = true
    /// Dictionnaires désactivés pour ce profil (en plus de ceux désactivés globalement).
    public var excludedDictionaryIds: Set<Int64> = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LookupOptions()
        scanLength = min(40, max(1, try c.decodeIfPresent(Int.self, forKey: .scanLength) ?? d.scanLength))
        maxResults = min(100, max(1, try c.decodeIfPresent(Int.self, forKey: .maxResults) ?? d.maxResults))
        partsOfSpeechFilter = try c.decodeIfPresent(Bool.self, forKey: .partsOfSpeechFilter) ?? d.partsOfSpeechFilter
        excludedDictionaryIds = try c.decodeIfPresent(Set<Int64>.self, forKey: .excludedDictionaryIds) ?? []
    }
}

/// Mémo borné et sûr entre fils, clé texte. `Box` : `NSCache` ne garde que des objets.
private final class Memo<Value>: @unchecked Sendable {
    private final class Box { let value: Value; init(_ value: Value) { self.value = value } }
    private let cache = NSCache<NSString, Box>()

    init(limit: Int) { cache.countLimit = limit }

    subscript(key: String) -> Value? {
        get { cache.object(forKey: key as NSString)?.value }
        set {
            if let newValue { cache.setObject(Box(newValue), forKey: key as NSString) }
            else { cache.removeObject(forKey: key as NSString) }
        }
    }

    func removeAll() { cache.removeAllObjects() }
}

/// Recherche de mots à la Yomitan : pour chaque longueur (de la plus longue à la plus courte),
/// variantes du texte (kana, demi-chasse, emphase…), formes de base par déconjugaison, une seule
/// requête SQL pour toutes les formes, puis tri (plus long d'abord).
public final class Translator: @unchecked Sendable {
    public let database: DictionaryDatabase
    let transformer: LanguageTransformer

    private var dictionaryCache: [Int64: DictionaryInfo]?
    private let lock = NSLock()
    /// Formes de base d'un texte : calcul pur, le plus coûteux de la recherche. Bornes basses : l'iPad doit garder sa
    /// mémoire pour les modèles d'IA, et `NSCache` se vide seul sous pression.
    private let deinflectionMemo = Memo<[Deinflection]>(limit: 2000)
    /// Mot retenu à une position du texte, par réglages et par génération : refaire une page déjà lue ne coûte plus
    /// rien. Sans glossaire, inutile au découpage : le mémo reste léger.
    private let segmentMemo = Memo<TermResult?>(limit: 2000)
    /// Tests seulement : entre la fin d'une recherche et son écriture, le moment où une invalidation peut survenir.
    var beforeSegmentMemoWrite: (() -> Void)?
    /// Avancée par `invalidate()`, sous `lock`, en même temps que `dictionaryCache` est vidé. Elle entre dans la clé du
    /// mémo : une recherche lancée avant l'invalidation écrit sous une clé que plus personne ne lit.
    private var memoGeneration = 0

    public init(database: DictionaryDatabase, transformer: LanguageTransformer = .japanese) {
        self.database = database
        self.transformer = transformer
    }

    /// À appeler après un import, une suppression ou un changement d'activation/priorité.
    public func invalidate() {
        lock.lock()
        dictionaryCache = nil
        memoGeneration += 1
        lock.unlock()
        segmentMemo.removeAll()
        database.clearCaches()
    }

    func dictionaries() throws -> [Int64: DictionaryInfo] {
        lock.lock()
        defer { lock.unlock() }
        if let dictionaryCache { return dictionaryCache }
        let all = try database.dictionaries()
        let map = Dictionary(uniqueKeysWithValues: all.compactMap { d in d.id.map { ($0, d) } })
        dictionaryCache = map
        return map
    }

    // MARK: Variantes de texte (préprocesseurs de Yomitan)

    static func variants(of text: String) -> Set<String> {
        let processors: [(String) -> [String]] = [
            { [$0, JapaneseText.halfWidthKanaToFullWidth($0)] },
            { [$0, JapaneseText.fullWidthAlphanumericToNormal($0), JapaneseText.alphanumericToFullWidth($0)] },
            { [$0, JapaneseText.hiraganaToKatakana($0), JapaneseText.katakanaToHiragana($0)] },
            { [$0, JapaneseText.collapseEmphaticSequences($0, full: false), JapaneseText.collapseEmphaticSequences($0, full: true)] },
            { [$0, JapaneseText.normalizeCombiningCharacters($0)] },
            { [$0, JapaneseText.normalizeCJKCompatibilityCharacters($0)] },
        ]
        var current: Set<String> = [text]
        for process in processors {
            var next = Set<String>()
            for v in current { for out in process(v) where !out.isEmpty { next.insert(out) } }
            current = next
        }
        return current
    }

    struct Deinflection {
        let matchedText: String
        let text: String
        let conditions: UInt32
        let rules: [String]
    }

    // MARK: Recherche

    /// Mots qui commencent au début de `text` (le texte touché et ce qui suit).
    public func findTerms(_ text: String, options: LookupOptions = LookupOptions()) throws -> [TermResult] {
        try search(text, options: options, withMeta: true)
    }

    /// Toutes les formes de base candidates de `raw`, mémorisées : le découpage repasse sans cesse sur les mêmes textes.
    private func deinflections(of raw: String) -> [Deinflection] {
        if let known = deinflectionMemo[raw] { return known }
        let found = Self.variants(of: raw).flatMap { variant in
            transformer.transform(variant).map {
                Deinflection(matchedText: raw, text: $0.text, conditions: $0.conditions, rules: $0.inflectionRules)
            }
        }
        deinflectionMemo[raw] = found
        return found
    }

    /// `withMeta` : fréquences, accents et API, inutiles au découpage et coûteux (JSON de chaque entrée).
    private func search(_ text: String, options: LookupOptions, withMeta: Bool) throws -> [TermResult] {
        let source = String(text.prefix(options.scanLength))
        guard !source.isEmpty else { return [] }
        let dictionaries = try dictionaries()
        let enabled = Set(dictionaries.values.filter { $0.enabled && $0.termCount > 0 }.compactMap(\.id))
            .subtracting(options.excludedDictionaryIds)
        guard !enabled.isEmpty else { return [] }

        // 1. Toutes les formes de base candidates, pour chaque longueur.
        var byText: [String: [Deinflection]] = [:]
        let chars = Array(source)
        for length in stride(from: chars.count, through: 1, by: -1) {
            let raw = String(chars[0..<length])
            // Pas de mot qui commence ou finit par une ponctuation / espace.
            if let first = raw.first, first.isWhitespace || first.isPunctuation { break }
            for d in deinflections(of: raw) { byText[d.text, default: []].append(d) }
        }

        // 2. Une requête pour toutes les formes.
        let rows = try database.terms(matching: Array(byText.keys), dictionaryIds: enabled)

        // 3. Associe chaque entrée à sa meilleure déconjugaison (plus long texte, moins de règles).
        struct Match { let row: TermRow; let d: Deinflection }
        var matches: [Match] = []
        for row in rows {
            let flags = transformer.conditionFlags(partsOfSpeech: row.rules.split(separator: " ").map(String.init))
            var best: Deinflection?
            for d in (byText[row.expression] ?? []) + (row.reading == row.expression ? [] : (byText[row.reading] ?? [])) {
                // Une forme conjuguée doit correspondre à la partie du discours de l'entrée.
                if options.partsOfSpeechFilter, !LanguageTransformer.conditionsMatch(d.conditions, flags) { continue }
                if best == nil || d.matchedText.count > best!.matchedText.count
                    || (d.matchedText.count == best!.matchedText.count && d.rules.count < best!.rules.count) {
                    best = d
                }
            }
            if let best { matches.append(Match(row: row, d: best)) }
        }

        // 4. Regroupement par (expression, lecture).
        var groups: [String: (row: TermRow, d: Deinflection, defs: [Match])] = [:]
        for m in matches {
            let key = m.row.expression + "\u{1}" + m.row.reading
            if var g = groups[key] {
                g.defs.append(m)
                if m.d.matchedText.count > g.d.matchedText.count { g.d = m.d }
                groups[key] = g
            } else {
                groups[key] = (m.row, m.d, [m])
            }
        }

        var results: [TermResult] = []
        for (_, g) in groups {
            let defs = g.defs.sorted {
                let p0 = dictionaries[$0.row.dictionaryId]?.priority ?? 0
                let p1 = dictionaries[$1.row.dictionaryId]?.priority ?? 0
                return p0 != p1 ? p0 < p1 : $0.row.score > $1.row.score
            }.map { m -> TermResult.Definition in
                let tags = (try? database.tags(dictionaryId: m.row.dictionaryId)) ?? [:]
                func resolve(_ s: String) -> [TagRow] {
                    s.split(separator: " ").map { name in
                        tags[String(name)] ?? TagRow(name: String(name), category: "", order: 0, notes: "", score: 0)
                    }
                }
                return TermResult.Definition(dictionaryId: m.row.dictionaryId,
                                             dictionaryTitle: dictionaries[m.row.dictionaryId]?.title ?? "?",
                                             tags: resolve(m.row.definitionTags), termTags: resolve(m.row.termTags),
                                             rules: m.row.rules.split(separator: " ").map(String.init),
                                             glossaryJSON: m.row.glossary, score: m.row.score, sequence: m.row.sequence)
            }
            results.append(TermResult(expression: g.row.expression, reading: g.row.reading, matchedText: g.d.matchedText,
                                      inflectionRules: g.d.rules, definitions: defs, frequencies: [], pitches: [], ipa: []))
        }

        // 5. Tri : plus long texte reconnu, moins de transformations, texte identique à l'expression,
        //    dictionnaire prioritaire, score.
        results.sort { a, b in
            if a.matchLength != b.matchLength { return a.matchLength > b.matchLength }
            if a.inflectionRules.count != b.inflectionRules.count { return a.inflectionRules.count < b.inflectionRules.count }
            let ea = a.expression == a.matchedText, eb = b.expression == b.matchedText
            if ea != eb { return ea }
            let pa = a.definitions.map { dictionaries[$0.dictionaryId]?.priority ?? 0 }.min() ?? 0
            let pb = b.definitions.map { dictionaries[$0.dictionaryId]?.priority ?? 0 }.min() ?? 0
            if pa != pb { return pa < pb }
            return (a.definitions.map(\.score).max() ?? 0) > (b.definitions.map(\.score).max() ?? 0)
        }
        results = Array(results.prefix(options.maxResults))

        // 6. Fréquences, accents, API.
        if withMeta { try attachMeta(&results, dictionaries: dictionaries, options: options) }
        return results
    }

    private func attachMeta(_ results: inout [TermResult], dictionaries: [Int64: DictionaryInfo], options: LookupOptions) throws {
        guard !results.isEmpty else { return }
        let metaDicts = Set(dictionaries.values.filter { $0.enabled && $0.termMetaCount > 0 }.compactMap(\.id))
            .subtracting(options.excludedDictionaryIds)
        guard !metaDicts.isEmpty else { return }
        let metas = try database.termMeta(for: results.map(\.expression), dictionaryIds: metaDicts)
        let byExpression = Dictionary(grouping: metas, by: \.expression)
        for i in results.indices {
            let r = results[i]
            for meta in byExpression[r.expression] ?? [] {
                let title = dictionaries[meta.dictionaryId]?.title ?? "?"
                guard let data = try? JSONSerialization.jsonObject(with: Data(meta.data.utf8), options: [.fragmentsAllowed]) else { continue }
                switch meta.mode {
                case "freq":
                    if let f = Self.parseFrequency(data, reading: r.reading) {
                        results[i].frequencies.append(TermResult.Frequency(dictionaryTitle: title, display: f.display, value: f.value))
                    }
                case "pitch":
                    guard let obj = data as? [String: Any], (obj["reading"] as? String) == r.reading,
                          let pitches = obj["pitches"] as? [[String: Any]] else { continue }
                    for p in pitches {
                        let tags = p["tags"] as? [String] ?? []
                        if let n = p["position"] as? Int {
                            results[i].pitches.append(TermResult.Pitch(dictionaryTitle: title, downstep: n, pattern: nil, tags: tags))
                        } else if let s = p["position"] as? String {
                            results[i].pitches.append(TermResult.Pitch(dictionaryTitle: title, downstep: Self.downstep(fromPattern: s),
                                                                       pattern: s, tags: tags))
                        }
                    }
                case "ipa":
                    guard let obj = data as? [String: Any], (obj["reading"] as? String) == r.reading,
                          let list = obj["transcriptions"] as? [[String: Any]] else { continue }
                    for t in list { if let ipa = t["ipa"] as? String { results[i].ipa.append(TermResult.IPA(dictionaryTitle: title, transcription: ipa)) } }
                default:
                    break
                }
            }
        }
    }

    /// Formats de fréquence Yomitan : nombre, texte, {value, displayValue}, {reading, frequency}.
    static func parseFrequency(_ data: Any, reading: String) -> (display: String, value: Int?)? {
        if let obj = data as? [String: Any], let r = obj["reading"] as? String {
            guard r == reading, let f = obj["frequency"] else { return nil }
            return parseFrequency(f, reading: reading)
        }
        switch data {
        case let n as NSNumber: return (n.stringValue, n.intValue)
        case let s as String: return (s, Int(s.prefix { $0.isNumber }))
        case let obj as [String: Any]:
            let value = (obj["value"] as? NSNumber)?.intValue
            let display = (obj["displayValue"] as? String) ?? value.map(String.init) ?? "?"
            return (display, value)
        default: return nil
        }
    }

    /// « LHHL » → 3 (position de la chute), « LHHH » → 0.
    static func downstep(fromPattern p: String) -> Int? {
        let chars = Array(p)
        for i in 1..<max(chars.count, 1) where chars[i - 1] == "H" && chars[i] == "L" { return i }
        return chars.first == "L" ? 0 : nil
    }

    // MARK: Kanji

    public func findKanji(_ character: String) throws -> KanjiResult? {
        let dictionaries = try dictionaries()
        let kanjiDicts = Set(dictionaries.values.filter { $0.enabled && ($0.kanjiCount > 0 || $0.kanjiMetaCount > 0) }.compactMap(\.id))
        let rows = try database.kanji(character, dictionaryIds: kanjiDicts)
        let metas = try database.kanjiMeta(character, dictionaryIds: kanjiDicts)
        guard !rows.isEmpty || !metas.isEmpty else { return nil }
        let entries = rows.sorted { (dictionaries[$0.dictionaryId]?.priority ?? 0) < (dictionaries[$1.dictionaryId]?.priority ?? 0) }.map {
            KanjiResult.Entry(dictionaryTitle: dictionaries[$0.dictionaryId]?.title ?? "?",
                              onyomi: $0.onyomi.split(separator: " ").map(String.init),
                              kunyomi: $0.kunyomi.split(separator: " ").map(String.init),
                              meanings: $0.meanings, stats: $0.stats,
                              tags: $0.tags.split(separator: " ").map(String.init))
        }
        let freqs = metas.compactMap { m -> TermResult.Frequency? in
            guard m.mode == "freq", let data = try? JSONSerialization.jsonObject(with: Data(m.data.utf8), options: [.fragmentsAllowed]),
                  let f = Self.parseFrequency(data, reading: "") else { return nil }
            return TermResult.Frequency(dictionaryTitle: dictionaries[m.dictionaryId]?.title ?? "?", display: f.display, value: f.value)
        }
        return KanjiResult(character: character, entries: entries, frequencies: freqs)
    }

    // MARK: Segmentation

    public struct Segment: Sendable, Equatable {
        public let text: String
        public let term: TermResult?
    }

    /// Découpe un texte en mots (plus long mot à chaque position) : vocabulaire d'une page. Les mots rendus ne portent
    /// ni définitions ni fréquences : `findTerms` les donne.
    // FDR-6.1 : mémo des positions déjà cherchées pendant un appel (une recherche par caractère non trouvé). Voir § 6 étape 6.
    public func segment(_ text: String, options: LookupOptions = LookupOptions()) throws -> [Segment] {
        var opts = options
        opts.maxResults = 1
        let generation = lock.withLock { memoGeneration }
        let optionsKey = "\(generation)|\(opts.scanLength)|\(opts.partsOfSpeechFilter)|\(opts.excludedDictionaryIds.sorted())|"
        let chars = Array(text)
        var segments: [Segment] = []
        var i = 0
        var pending = ""
        while i < chars.count {
            if Task.isCancelled { break }
            let c = chars[i]
            guard JapaneseText.isJapanese(c), !c.isPunctuation else {
                pending.append(c)
                i += 1
                continue
            }
            let rest = String(chars[i..<min(chars.count, i + opts.scanLength)])
            let key = optionsKey + rest
            let found: TermResult?
            if let known = segmentMemo[key] {
                found = known
            } else {
                found = try search(rest, options: opts, withMeta: false).first.map {
                    TermResult(expression: $0.expression, reading: $0.reading, matchedText: $0.matchedText,
                               inflectionRules: $0.inflectionRules, definitions: [], frequencies: [], pitches: [], ipa: [])
                }
                beforeSegmentMemoWrite?()
                segmentMemo[key] = .some(found)
            }
            if let best = found {
                if !pending.isEmpty { segments.append(Segment(text: pending, term: nil)); pending = "" }
                segments.append(Segment(text: best.matchedText, term: best))
                i += max(1, best.matchLength)
            } else {
                pending.append(c)
                i += 1
            }
        }
        if !pending.isEmpty { segments.append(Segment(text: pending, term: nil)) }
        return segments
    }

    /// Nom lisible d'une transformation (« past », « negative »…).
    public func inflectionName(_ id: String) -> String {
        transformer.info(forTransform: id)?.name ?? id
    }
}
