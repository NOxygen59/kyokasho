// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Sens d'une définition en texte simple (listes de vocabulaire, cartes, export CSV).
public enum GlossaryText {
    /// `glossaryJSON` → « sens 1 ; sens 2 ; … », sans images ni balises, coupé à `limit` caractères.
    public static func plain(_ glossaryJSON: String, limit: Int = 160) -> String {
        guard let data = glossaryJSON.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return "" }
        var parts: [String] = []
        for item in items {
            var out = ""
            collect(item, into: &out)
            let t = out.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
            if !t.isEmpty { parts.append(t) }
        }
        let joined = parts.joined(separator: " ; ")
        return joined.count > limit ? String(joined.prefix(limit - 1)) + "…" : joined
    }

    /// `glossaryJSON` → un sens par élément (texte simple, sans images ni balises).
    public static func items(_ glossaryJSON: String) -> [String] {
        guard let data = glossaryJSON.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return items.compactMap { item in
            var out = ""
            collect(item, into: &out)
            let t = out.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
            return t.isEmpty ? nil : t
        }
    }

    private static func collect(_ node: Any, into out: inout String) {
        switch node {
        case let s as String:
            out += s
        case let array as [Any]:
            for n in array { collect(n, into: &out) }
        case let dict as [String: Any]:
            switch dict["type"] as? String {
            case "text": out += dict["text"] as? String ?? ""
            case "image": return
            case "structured-content": if let c = dict["content"] { collect(c, into: &out) }
            default:
                // Nœud de structured-content : on garde le texte, on saute furigana (rt) et images.
                let tag = dict["tag"] as? String
                if tag == "rt" || tag == "rp" || tag == "img" { return }
                if let c = dict["content"] {
                    let block = ["div", "li", "tr", "p", "ol", "ul", "details", "summary"].contains(tag ?? "")
                    if block, !out.isEmpty, !out.hasSuffix("\n") { out += "\n" }
                    collect(c, into: &out)
                    if block { out += "\n" }
                }
            }
        default:
            break
        }
    }
}
