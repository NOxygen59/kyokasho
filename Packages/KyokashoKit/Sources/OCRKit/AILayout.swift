// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Mise en page d'une page par l'IA (Markdown d'OvisOCR2 : titres `#`, paragraphes, listes, tableaux en HTML,
/// figures en `<img src="images/bbox_l_t_r_b.jpg">`) → blocs **sûrs** : seul du texte et une structure connue sortent
/// d'ici (aucune balise de l'IA n'est recopiée telle quelle dans la page affichée).
public enum AILayout {
    public enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case list([String])
        case table([[Cell]])
        /// Figure de la page, coordonnées sur 1000 (gauche, haut, droite, bas) dans l'image de la page.
        case figure(left: Int, top: Int, right: Int, bottom: Int)
    }

    public struct Cell: Equatable, Sendable {
        public var text: String
        public var colspan = 1
        public var rowspan = 1
        public var header = false
    }

    public static func blocks(_ markdown: String) -> [Block] {
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        // 1. Tableaux et figures sortis à part (ils peuvent tenir sur plusieurs lignes), remplacés par des repères.
        var tables: [[[Cell]]] = []
        text = replace(#"<table\b[^>]*>(.*?)</table>"#, in: text) { groups in
            tables.append(rows(groups[1]))
            return "\n\u{1}T\(tables.count - 1)\n"
        }
        text = replace(#"<img\b[^>]*bbox_(\d+)_(\d+)_(\d+)_(\d+)[^>]*>"#, in: text) { g in
            "\n\u{1}F\(g[1]) \(g[2]) \(g[3]) \(g[4])\n"
        }
        // 2. Lignes : titres, listes, paragraphes (lignes voisines réunies : pas d'espace en japonais).
        var out: [Block] = []
        var paragraph: [String] = []
        var items: [String] = []
        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined())); paragraph = [] }
            if !items.isEmpty { out.append(.list(items)); items = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("\u{1}T"), let i = Int(line.dropFirst(2)), tables.indices.contains(i) {
                flush(); out.append(.table(tables[i])); continue
            }
            if line.hasPrefix("\u{1}F") {
                let n = line.dropFirst(2).split(separator: " ").compactMap { Int($0) }
                flush()
                if n.count == 4, n[2] > n[0], n[3] > n[1] { out.append(.figure(left: n[0], top: n[1], right: n[2], bottom: n[3])) }
                continue
            }
            if let m = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flush()
                let level = line[m].filter { $0 == "#" }.count
                let title = inline(String(line[m.upperBound...]))
                if !title.isEmpty { out.append(.heading(level: level, text: title)) }
                continue
            }
            if let m = line.range(of: #"^([-*•・]|\d+[.)])\s+"#, options: .regularExpression) {
                if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined())); paragraph = [] }
                let item = inline(String(line[m.upperBound...]))
                if !item.isEmpty { items.append(item) }
                continue
            }
            if !items.isEmpty { out.append(.list(items)); items = [] }
            let clean = inline(line)
            if !clean.isEmpty { paragraph.append(clean) }
        }
        flush()
        return out
    }

    /// Texte d'une ligne : sans gras / italique / code Markdown, sans aucune balise, entités HTML décodées.
    public static func inline(_ s: String) -> String {
        var t = s
        for mark in ["**", "__", "`"] { t = t.replacingOccurrences(of: mark, with: "") }
        t = t.replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        return entities(t).trimmingCharacters(in: .whitespaces)
    }

    static func entities(_ s: String) -> String {
        var t = s
        for (k, v) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        return t
    }

    static func rows(_ html: String) -> [[Cell]] {
        var result: [[Cell]] = []
        for row in matches(#"<tr\b[^>]*>(.*?)</tr>"#, in: html) {
            var cells: [Cell] = []
            for cell in matches(#"<(t[dh])\b([^>]*)>(.*?)</t[dh]>"#, in: row[1]) {
                func attr(_ name: String) -> Int {
                    guard let m = matches(name + #"\s*=\s*"?(\d+)"#, in: cell[2]).first, let v = Int(m[1]) else { return 1 }
                    return min(max(v, 1), 50)
                }
                cells.append(Cell(text: inline(cell[3]), colspan: attr("colspan"), rowspan: attr("rowspan"), header: cell[1] == "th"))
            }
            if !cells.isEmpty { result.append(cells) }
        }
        return result
    }

    // MARK: Expressions (insensibles à la casse, `.` traverse les lignes)

    static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }

    static func replace(_ pattern: String, in text: String, with make: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += make((0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) })
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }
}
