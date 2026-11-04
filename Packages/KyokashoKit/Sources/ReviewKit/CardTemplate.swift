// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Petit moteur de templates « façon Handlebars », écrit pour Kyōkasho, compatible avec la
/// syntaxe des champs d'Anki pour pouvoir exporter les mêmes modèles.
///
/// - `{{Champ}}` / `{{{Champ}}}` : valeur du champ (HTML, comme dans Anki).
/// - Filtres Anki : `{{text:Champ}}` (sans balises), `{{furigana:Champ}}` (`食[た]べる` → ruby),
///   `{{kana:Champ}}`, `{{kanji:Champ}}`.
/// - `{{#if Champ}}…{{else}}…{{/if}}`, `{{#unless Champ}}…{{/unless}}`.
/// - `{{#each Champ}}…{{this}}…{{@index}}…{{/each}}` : une ligne du champ par tour.
/// - `{{FrontSide}}` au verso : le recto rendu. `{{! commentaire }}` ignoré.
/// - Anki : `{{#Champ}}…{{/Champ}}` et `{{^Champ}}…{{/Champ}}` sont aussi acceptés.
public struct CardTemplate: Sendable, Equatable {
    public let source: String
    let nodes: [Node]

    indirect enum Node: Sendable, Equatable {
        case text(String)
        case variable(name: String, filters: [String])
        case condition(name: String, negated: Bool, then: [Node], otherwise: [Node])
        case each(name: String, body: [Node])
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case unclosed(String)
        case unexpectedClose(String)
        case unterminatedTag

        public var description: String {
            switch self {
            case .unclosed(let n): return String(localized: "Bloc « \(n) » jamais fermé.", bundle: .main)
            case .unexpectedClose(let n): return String(localized: "Fermeture « \(n) » sans ouverture.", bundle: .main)
            case .unterminatedTag: return String(localized: "Accolades {{ … }} pas fermées.", bundle: .main)
            }
        }
    }

    public init(_ source: String) throws {
        self.source = source
        var parser = Parser(source)
        nodes = try parser.parse()
    }

    // MARK: Rendu

    public func render(_ fields: [String: String], extra: [String: String] = [:]) -> String {
        var out = ""
        Self.render(nodes, fields: fields.merging(extra) { $1 }, this: nil, index: nil, into: &out)
        return out
    }

    static func render(_ nodes: [Node], fields: [String: String], this: String?, index: Int?, into out: inout String) {
        for node in nodes {
            switch node {
            case .text(let t):
                out += t
            case .variable(let name, let filters):
                let value: String
                switch name {
                case "this", ".": value = this ?? ""
                case "@index": value = index.map(String.init) ?? ""
                default: value = fields[name] ?? ""
                }
                out += filters.reversed().reduce(value) { applyFilter($1, $0) }
            case .condition(let name, let negated, let then, let otherwise):
                let raw = name == "this" ? (this ?? "") : (fields[name] ?? "")
                let truthy = !Self.stripHTML(raw).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || raw.contains("<img")
                render(truthy != negated ? then : otherwise, fields: fields, this: this, index: index, into: &out)
            case .each(let name, let body):
                let lines = (fields[name] ?? "").split(whereSeparator: \.isNewline).map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                for (i, line) in lines.enumerated() {
                    render(body, fields: fields, this: line, index: i, into: &out)
                }
            }
        }
    }

    static func applyFilter(_ filter: String, _ value: String) -> String {
        switch filter {
        case "text": return stripHTML(value)
        case "furigana": return Furigana.ruby(value)
        case "kana": return Furigana.kana(value)
        case "kanji": return Furigana.kanji(value)
        default: return value
        }
    }

    static func stripHTML(_ s: String) -> String {
        guard s.contains("<") || s.contains("&") else { return s }
        var out = ""
        var inTag = false
        for c in s {
            if c == "<" { inTag = true } else if c == ">" { inTag = false } else if !inTag { out.append(c) }
        }
        return out.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Export Anki

    /// Même template en syntaxe Anki (`{{#if}}` → `{{#Champ}}`, `{{else}}` → `{{^Champ}}`…).
    /// `{{#each}}` n'existe pas dans Anki : le champ entier est affiché à la place.
    public var ankiSource: String {
        Self.anki(nodes)
    }

    static func anki(_ nodes: [Node]) -> String {
        nodes.map { node -> String in
            switch node {
            case .text(let t): return t
            case .variable(let name, let filters):
                if name == "this" || name == "." || name == "@index" { return "" }
                return "{{" + (filters + [name]).joined(separator: ":") + "}}"
            case .condition(let name, let negated, let then, let otherwise):
                var s = "{{\(negated ? "^" : "#")\(name)}}\(anki(then)){{/\(name)}}"
                if !otherwise.isEmpty { s += "{{\(negated ? "#" : "^")\(name)}}\(anki(otherwise)){{/\(name)}}" }
                return s
            case .each(let name, _):
                return "{{\(name)}}"
            }
        }.joined()
    }

    /// Champs utilisés par le template (pour vérifier qu'ils existent).
    public var referencedFields: Set<String> {
        var set = Set<String>()
        func walk(_ nodes: [Node]) {
            for n in nodes {
                switch n {
                case .text: break
                case .variable(let name, _): if !["this", ".", "@index", "FrontSide"].contains(name) { set.insert(name) }
                case .condition(let name, _, let a, let b): if name != "this" { set.insert(name) }; walk(a); walk(b)
                case .each(let name, let body): set.insert(name); walk(body)
                }
            }
        }
        walk(nodes)
        return set
    }

    // MARK: Analyse

    struct Parser {
        let chars: [Character]
        var i = 0

        init(_ s: String) { chars = Array(s) }

        enum Tag {
            case open(kind: String, name: String)
            case close(String)
            case elseTag
            case variable(String, [String])
            case comment
        }

        mutating func parse() throws -> [Node] {
            let (nodes, end) = try parseBlock(until: nil)
            if let end { throw ParseError.unexpectedClose(end) }
            return nodes
        }

        /// Lit jusqu'à `{{/nom}}` (ou la fin). Renvoie aussi les nœuds du `{{else}}`.
        mutating func parseBlock(until closing: String?) throws -> ([Node], String?) {
            let (nodes, _, end) = try parseUntilElse(closing: closing, allowElse: false)
            return (nodes, end)
        }

        mutating func parseUntilElse(closing: String?, allowElse: Bool) throws -> ([Node], Bool, String?) {
            var nodes: [Node] = []
            var text = ""
            func flush() { if !text.isEmpty { nodes.append(.text(text)); text = "" } }
            while i < chars.count {
                if chars[i] == "{", i + 1 < chars.count, chars[i + 1] == "{" {
                    let tag = try readTag()
                    switch tag {
                    case .comment: continue
                    case .variable(let name, let filters):
                        flush(); nodes.append(.variable(name: name, filters: filters))
                    case .elseTag:
                        if allowElse { flush(); return (nodes, true, nil) }
                        text += "{{else}}"
                    case .close(let name):
                        flush()
                        guard let closing else { return (nodes, false, name) }
                        if name == closing || (closing.hasPrefix("#") && name == String(closing.dropFirst())) {
                            return (nodes, false, nil)
                        }
                        throw ParseError.unexpectedClose(name)
                    case .open(let kind, let name):
                        flush()
                        let close: String
                        switch kind {
                        case "if", "unless": close = kind
                        case "each": close = "each"
                        default: close = name // Anki : {{#Champ}} … {{/Champ}}
                        }
                        if kind == "each" {
                            let (body, _, _) = try parseUntilElse(closing: close, allowElse: false)
                            nodes.append(.each(name: name, body: body))
                        } else {
                            let (then, hadElse, _) = try parseUntilElse(closing: close, allowElse: true)
                            var otherwise: [Node] = []
                            if hadElse { (otherwise, _, _) = try parseUntilElse(closing: close, allowElse: false) }
                            nodes.append(.condition(name: name, negated: kind == "unless" || kind == "^",
                                                    then: then, otherwise: otherwise))
                        }
                    }
                } else {
                    text.append(chars[i])
                    i += 1
                }
            }
            flush()
            if let closing { throw ParseError.unclosed(closing) }
            return (nodes, false, nil)
        }

        mutating func readTag() throws -> Tag {
            // Triple accolade {{{x}}} : même chose que {{x}} (les champs sont déjà du HTML).
            let triple = i + 2 < chars.count && chars[i + 2] == "{"
            i += triple ? 3 : 2
            let start = i
            let closing: [Character] = triple ? ["}", "}", "}"] : ["}", "}"]
            while i + closing.count <= chars.count, Array(chars[i..<i + closing.count]) != closing { i += 1 }
            guard i + closing.count <= chars.count else { throw ParseError.unterminatedTag }
            let inner = String(chars[start..<i]).trimmingCharacters(in: .whitespaces)
            i += closing.count
            if inner.hasPrefix("!") { return .comment }
            if inner == "else" { return .elseTag }
            if inner.hasPrefix("/") { return .close(inner.dropFirst().trimmingCharacters(in: .whitespaces)) }
            if inner.hasPrefix("#") || inner.hasPrefix("^") {
                let body = inner.dropFirst().trimmingCharacters(in: .whitespaces)
                let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
                if inner.hasPrefix("#"), let first = parts.first, ["if", "unless", "each"].contains(first), parts.count == 2 {
                    return .open(kind: first, name: parts[1].trimmingCharacters(in: .whitespaces))
                }
                return .open(kind: inner.hasPrefix("^") ? "^" : "#", name: body)
            }
            var parts = inner.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            let name = parts.removeLast()
            return .variable(name, parts)
        }
    }
}

/// Furigana au format Anki : `食[た]べる 物[もの]`.
public enum Furigana {
    /// `[(base, lecture)]` ; lecture vide pour le texte sans furigana.
    static func parse(_ s: String) -> [(String, String)] {
        var out: [(String, String)] = []
        var base = ""
        var chars = Array(s)[...]
        while let c = chars.first {
            chars = chars.dropFirst()
            if c == "[", let close = chars.firstIndex(of: "]") {
                let reading = String(chars[chars.startIndex..<close])
                chars = chars[(close + 1)...]
                // La base du furigana : depuis le dernier espace (ou le début).
                if let space = base.lastIndex(of: " ") {
                    let before = String(base[...space])
                    if !before.isEmpty { out.append((String(before.dropLast()), "")) }
                    base = String(base[base.index(after: space)...])
                }
                out.append((base, reading))
                base = ""
            } else {
                base.append(c)
            }
        }
        if !base.isEmpty { out.append((base, "")) }
        return out
    }

    public static func ruby(_ s: String) -> String {
        guard s.contains("[") else { return s }
        return parse(s).map { $0.1.isEmpty ? $0.0 : "<ruby>\($0.0)<rt>\($0.1)</rt></ruby>" }.joined()
    }

    public static func kana(_ s: String) -> String {
        guard s.contains("[") else { return s }
        return parse(s).map { $0.1.isEmpty ? $0.0 : $0.1 }.joined()
    }

    public static func kanji(_ s: String) -> String {
        guard s.contains("[") else { return s }
        return parse(s).map { $0.0 }.joined()
    }

    /// Fabrique le format Anki depuis des segments (texte, lecture).
    public static func anki(_ segments: [(text: String, reading: String)]) -> String {
        var out = ""
        for (i, seg) in segments.enumerated() {
            if seg.reading.isEmpty { out += seg.text; continue }
            if i > 0, !out.isEmpty { out += " " }
            out += "\(seg.text)[\(seg.reading)]"
        }
        return out
    }
}
