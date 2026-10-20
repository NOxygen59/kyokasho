// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024-2026  Yomitan Authors
// Swift port: Copyright (C) 2026 NOxygen59
//
// Porté de yomidevs/yomitan, ext/js/language/language-transformer.js
// (commit 876253ca12e38aa6b0be3617e84827db5d9782b3). Les règles japonaises
// (ext/js/language/ja/japanese-transforms.js) sont exportées en données dans
// Resources/japanese-transforms.json par scripts/export_yomitan_transforms.mjs.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import Foundation

/// Déconjugaison : 食べさせられなかった → 食べる (+ la chaîne de transformations).
public final class LanguageTransformer: @unchecked Sendable {
    public struct Frame: Equatable, Sendable {
        public let transform: String
        public let ruleIndex: Int
        public let text: String
    }

    public struct TransformedText: Sendable {
        public let text: String
        /// Conditions (bits) que doit remplir l'entrée du dictionnaire ; 0 = aucune.
        public let conditions: UInt32
        /// Transformations appliquées, de la dernière à la première (comme Yomitan).
        public let trace: [Frame]

        /// Noms des transformations dans l'ordre de lecture (ex. « causative », « passive », « past »).
        public var inflectionRules: [String] { trace.map(\.transform) }
    }

    struct Rule {
        enum Kind: String { case suffix, prefix, wholeWord }
        let kind: Kind
        let from: String
        let to: String
        let fromCount: Int
        let conditionsIn: UInt32
        let conditionsOut: UInt32
    }

    struct Transform {
        let id: String
        let name: String
        let description: String?
        let rules: [Rule]
        /// Règles « suffixe » indexées par leur dernier caractère (test rapide).
        let suffixByLast: [Character: [Int]]
        let otherRules: [Int]
    }

    private(set) var transforms: [Transform] = []
    private var conditionFlags: [String: UInt32] = [:]
    private var partOfSpeechFlags: [String: UInt32] = [:]

    public init() {}

    /// Transformateur japonais (règles de Yomitan), chargé une fois.
    public static let japanese: LanguageTransformer = {
        let transformer = LanguageTransformer()
        if let url = Bundle.module.url(forResource: "japanese-transforms", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            try? transformer.addDescriptor(json: data)
        }
        return transformer
    }()

    // MARK: Chargement

    struct Descriptor: Decodable {
        struct Condition: Decodable {
            let name: String
            let isDictionaryForm: Bool
            let subConditions: [String]?
        }
        struct RuleJSON: Decodable {
            let type: String
            let from: String
            let to: String
            let conditionsIn: [String]
            let conditionsOut: [String]
        }
        struct TransformJSON: Decodable {
            let id: String
            let name: String
            let description: String?
            let rules: [RuleJSON]
        }
        let conditions: [String: Condition]
        let transforms: [TransformJSON]
    }

    public enum LoadError: Error { case tooManyConditions, invalidConditions(String) }

    func addDescriptor(json: Data) throws {
        let descriptor = try JSONDecoder().decode(Descriptor.self, from: json)
        // Bits : une condition simple = un bit ; une condition composée = union de ses sous-conditions.
        var flags: [String: UInt32] = conditionFlags
        var nextBit = flags.values.reduce(0) { $0 | $1 }.nonzeroBitCount
        var pending = descriptor.conditions.sorted { $0.key < $1.key }
        while !pending.isEmpty {
            var next: [(String, Descriptor.Condition)] = []
            for (key, condition) in pending {
                if let subs = condition.subConditions {
                    var union: UInt32 = 0
                    var ready = true
                    for sub in subs {
                        guard let f = flags[sub] else { ready = false; break }
                        union |= f
                    }
                    if ready { flags[key] = union } else { next.append((key, condition)) }
                } else {
                    guard nextBit < 32 else { throw LoadError.tooManyConditions }
                    flags[key] = 1 << UInt32(nextBit)
                    nextBit += 1
                }
            }
            if next.count == pending.count { throw LoadError.tooManyConditions }
            pending = next
        }
        func mask(_ names: [String]) throws -> UInt32 {
            var m: UInt32 = 0
            for n in names {
                guard let f = flags[n] else { throw LoadError.invalidConditions(n) }
                m |= f
            }
            return m
        }
        for t in descriptor.transforms {
            var rules: [Rule] = []
            var suffixByLast: [Character: [Int]] = [:]
            var other: [Int] = []
            for (i, r) in t.rules.enumerated() {
                guard let kind = Rule.Kind(rawValue: r.type) else { continue }
                rules.append(Rule(kind: kind, from: r.from, to: r.to, fromCount: r.from.count,
                                  conditionsIn: try mask(r.conditionsIn), conditionsOut: try mask(r.conditionsOut)))
                if kind == .suffix, let last = r.from.last {
                    suffixByLast[last, default: []].append(i)
                } else {
                    other.append(i)
                }
            }
            transforms.append(Transform(id: t.id, name: t.name, description: t.description, rules: rules,
                                        suffixByLast: suffixByLast, otherRules: other))
        }
        conditionFlags = flags
        for (key, condition) in descriptor.conditions where condition.isDictionaryForm {
            partOfSpeechFlags[key] = flags[key]
        }
    }

    // MARK: Conditions

    public static func conditionsMatch(_ current: UInt32, _ next: UInt32) -> Bool {
        current == 0 || (current & next) != 0
    }

    /// Bits correspondant aux parties du discours d'une entrée (ex. « v5 vt » → v5).
    public func conditionFlags(partsOfSpeech: [String]) -> UInt32 {
        partsOfSpeech.reduce(0) { $0 | (partOfSpeechFlags[$1] ?? 0) }
    }

    public func conditionFlags(types: [String]) -> UInt32 {
        types.reduce(0) { $0 | (conditionFlags[$1] ?? 0) }
    }

    /// Nom lisible et description d'une transformation (pour l'affichage).
    public func info(forTransform id: String) -> (name: String, description: String?)? {
        transforms.first { $0.id == id }.map { ($0.name, $0.description) }
    }

    // MARK: Transformation

    /// Toutes les formes « de base » possibles du texte (le texte lui-même en premier).
    public func transform(_ source: String) -> [TransformedText] {
        var results = [TransformedText(text: source, conditions: 0, trace: [])]
        var i = 0
        while i < results.count {
            let current = results[i]
            i += 1
            let text = current.text
            guard let last = text.last else { continue }
            for transform in transforms {
                let candidates = (transform.suffixByLast[last] ?? []) + transform.otherRules
                for j in candidates {
                    let rule = transform.rules[j]
                    guard Self.conditionsMatch(current.conditions, rule.conditionsIn) else { continue }
                    let deinflected: String
                    switch rule.kind {
                    case .suffix:
                        guard text.hasSuffix(rule.from) else { continue }
                        deinflected = String(text.dropLast(rule.fromCount)) + rule.to
                    case .prefix:
                        guard text.hasPrefix(rule.from) else { continue }
                        deinflected = rule.to + String(text.dropFirst(rule.fromCount))
                    case .wholeWord:
                        guard text == rule.from else { continue }
                        deinflected = rule.to
                    }
                    let isCycle = current.trace.contains { $0.transform == transform.id && $0.ruleIndex == j && $0.text == text }
                    if isCycle { continue }
                    results.append(TransformedText(text: deinflected, conditions: rule.conditionsOut,
                                                   trace: [Frame(transform: transform.id, ruleIndex: j, text: text)] + current.trace))
                }
            }
        }
        return results
    }
}
