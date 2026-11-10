// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import Foundation
import SwiftUI

/// Traductions françaises des définitions anglaises (DeepL), gardées sur l'appareil avec ton avis :
/// 👍 validée, 👎 à revoir, ✏️ corrigée à la main (la correction remplace la traduction, pour toujours).
@MainActor
final class DefinitionTranslations: ObservableObject {
    static let shared = DefinitionTranslations()
    static let autoKey = "dictionary.autoTranslateFR"

    /// Avis sur la traduction : 👍 validée, 👎 à revoir, ✏️ corrigée à la main (la correction remplace la traduction,
    /// pour toujours). Défini dans `DictionaryKit` (`TranslationReview`) : la règle de conservation d'un avis lors d'une
    /// nouvelle traduction automatique y est testée.
    typealias Status = TranslationReview

    struct Entry: Codable, Equatable {
        var text: String
        var status: Status
        /// Définitions traduites (C1.2, audit du 09/11/2026) : une mise à jour du dictionnaire qui change la définition
        /// rend la traduction automatique périmée. Absent des traductions enregistrées avant ce champ.
        var source: String? = nil
    }

    /// Traduction à afficher pour ce mot, ou `nil` si elle ne correspond plus à la définition actuelle
    /// (une correction à la main reste toujours ; règle dans `TranslationFreshness`).
    func entry(for term: TermResult) -> Entry? {
        guard let entry = entries[Self.key(term)] else { return nil }
        return TranslationFreshness.isCurrent(edited: entry.status == .edited, storedSource: entry.source,
                                              currentSource: Self.source(term)) ? entry : nil
    }

    @Published private(set) var entries: [String: Entry] = [:]
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("definition-translations.json")
    }()

    private init() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        } else {
            // Fichier illisible : mis de côté plutôt qu'écrasé (tes corrections restent récupérables).
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("bak"))
        }
    }

    static func key(_ term: TermResult) -> String {
        "\(term.expression)|\(term.reading)|\(term.definitions.first?.dictionaryTitle ?? "")"
    }

    /// Définitions en texte simple (celles du premier dictionnaire du mot).
    static func source(_ term: TermResult) -> String {
        guard let title = term.definitions.first?.dictionaryTitle else { return "" }
        return term.definitions.filter { $0.dictionaryTitle == title }
            .map { GlossaryText.plain($0.glossaryJSON, limit: 200) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: " ; ")
    }

    /// Définition surtout en lettres latines (et pas de kana/kanji) : anglaise.
    static func isEnglish(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 3 else { return false }
        let latin = letters.filter { $0.isASCII }.count
        return Double(latin) / Double(letters.count) > 0.8
    }

    func translate(_ term: TermResult) async throws {
        let source = Self.source(term)
        guard !source.isEmpty else { return }
        let text = try await DeepLService.shared.translate(source, target: "FR")
        // Revue DeepSeek #3 (C1.2) : la définition a changé, la traduction d'avant ne s'affiche donc plus — mais l'avis
        // 👍/👎 donné par l'utilisateur ne doit pas disparaître en silence quand la traduction automatique est refaite.
        // Il passe sur la nouvelle traduction (le texte, lui, est bien remplacé : il ne correspond plus à la définition).
        // Une correction ✏️ n'arrive jamais ici : `entry(for:)` la garde toujours courante, donc aucun écran ne propose
        // de la retraduire.
        let key = Self.key(term)
        let review = entries[key]?.status.keptWhenRetranslated ?? .machine
        set(key, Entry(text: text, status: review, source: source))
    }

    func set(_ key: String, _ entry: Entry?) {
        entries[key] = entry
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}

/// Bloc « Français » posé dans la fiche du premier mot (sous son en-tête), dans la fenêtre du dictionnaire.
/// Les boutons renvoient `{type:'fr', action}` (translate / like / dislike / edit) à `LookupPopup`.
enum DefinitionTranslationHTML {
    static func block(entry: DefinitionTranslations.Entry?, hasKey: Bool, busy: Bool, error: String?) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        var h = "<div class=\"fr-tr\"><span class=\"fr-tag\">FR</span>"
        if let entry {
            let liked = entry.status == .liked || entry.status == .edited
            h += "<span class=\"fr-text\">\(esc(entry.text))</span><span class=\"fr-act\">"
            h += "<button data-fr=\"like\" class=\"\(liked ? "on" : "")\" title=\"\(String(localized: "Bonne traduction"))\">👍</button>"
            h += "<button data-fr=\"dislike\" class=\"\(entry.status == .disliked ? "on" : "")\" title=\"\(String(localized: "Mauvaise : corriger"))\">👎</button>"
            h += "<button data-fr=\"edit\" title=\"\(String(localized: "Modifier"))\">✏️</button></span>"
        } else if busy {
            h += "<span class=\"fr-text dim\">\(String(localized: "Traduction…"))</span>"
        } else if hasKey {
            h += "<button data-fr=\"translate\" class=\"fr-go\">\(String(localized: "Traduire en français"))</button>"
        } else {
            h += "<span class=\"fr-text dim\">\(String(localized: "Ajoute ta clé DeepL (Réglages → Traduction) pour la traduction française."))</span>"
        }
        if let error { h += "<div class=\"fr-text dim\">\(esc(error))</div>" }
        return h + "</div>"
    }

    static let style = """
    <style>
    .fr-tr{margin:8px 0 4px;padding:8px 10px;border-radius:10px;background:rgba(160,120,255,.12);display:flex;flex-wrap:wrap;gap:6px;align-items:baseline;font-size:15px}
    .fr-tag{font:700 11px -apple-system,sans-serif;color:#b79bff}
    .fr-text{flex:1 1 200px} .fr-text.dim{opacity:.6;font-size:13px}
    .fr-act button,.fr-go{border:none;border-radius:8px;background:rgba(255,255,255,.08);padding:3px 7px;font-size:14px;color:inherit}
    .fr-act button.on{background:rgba(160,120,255,.45)} .fr-go{color:#b79bff;font-weight:600}
    </style>
    <script>
    document.addEventListener('click',function(e){var b=e.target.closest('[data-fr]');if(!b)return;
      e.stopPropagation();window.webkit.messageHandlers.kyokasho.postMessage({type:'fr',action:b.dataset.fr})},true);
    </script>
    """

    /// Insère le bloc après le premier en-tête de mot (`</header>` du premier `<article class="term">`).
    static func inject(_ block: String, into html: String) -> String {
        guard let article = html.range(of: "<article class=\"term\""),
              let header = html.range(of: "</header>", range: article.upperBound..<html.endIndex) else { return html }
        var out = html
        out.insert(contentsOf: block, at: header.upperBound)
        if let body = out.range(of: "</body>") { out.insert(contentsOf: style, at: body.lowerBound) } else { out += style }
        return out
    }
}
