// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Analyse d'un document entier : chaque page est lue par l'OCR habituel **et** par d'autres modèles
/// (OvisOCR2, GLM-OCR) ; chaque ligne est confirmée quand au moins deux lectures indépendantes donnent le même
/// texte. La fiabilité = part des lignes confirmées. Les désaccords gardent toutes les lectures et un choix conseillé.
public struct DocumentAnalysis: Codable, Sendable {
    public struct LineVote: Codable, Sendable, Identifiable, Equatable {
        public var id: Int { line }
        public let line: Int
        /// Texte de l'OCR habituel (tel qu'en cache).
        public let base: String
        /// Lecture de chaque autre modèle (sans espaces), quand il recouvre la ligne.
        public let readings: [String: String]
        /// Lecture choisie par le vote (ou par le dictionnaire en cas d'égalité) — peut être le texte actuel
        /// (sans espaces) ; `nil` si rien ne l'emporte.
        public var advised: String?
        /// Texte actuel sans espaces (pour savoir si le conseil est de garder la ligne telle quelle).
        public var baseKey: String { base.filter { !$0.isWhitespace && !OCRReferenceDiff.ignored.contains($0) } }
        /// Choix déjà appliqué au texte (ou écarté).
        public var settled: Bool = false
    }

    public struct Page: Codable, Sendable, Identifiable {
        public var id: Int { source }
        /// `var` : renuméroté quand des pages sont insérées avant (« Ajouter des pages… »).
        public var source: Int
        public var baseEngine: String
        public var lines: Int = 0
        public var confirmed: Int = 0
        /// Lignes que les autres modèles ne recouvrent pas (rien à comparer).
        public var unchecked: Int = 0
        public var disagreements: [LineVote] = []
        public var error: String?
        public var reliability: Double { lines - unchecked > 0 ? Double(confirmed) / Double(lines - unchecked) : 1 }

        public init(source: Int, baseEngine: String) {
            self.source = source
            self.baseEngine = baseEngine
        }
    }

    /// Un lancement d'analyse (« Dernière analyse : … », #41).
    public struct Run: Codable, Sendable, Equatable {
        public var date: Date
        public var engines: [String]
        /// Pages lues, de `firstPage` à `lastPage` (indices source, inclus).
        public var firstPage: Int
        public var lastPage: Int
        /// Pages déjà lues relues quand même.
        public var reread: Bool

        public init(date: Date, engines: [String], firstPage: Int, lastPage: Int, reread: Bool) {
            self.date = date
            self.engines = engines
            self.firstPage = firstPage
            self.lastPage = lastPage
            self.reread = reread
        }
    }

    public let documentId: String
    public var date = Date()
    public var engines: [String] = []
    public var pages: [Int: Page] = [:]
    /// Lancements, du plus ancien au plus récent (20 au plus) ; absent des rapports d'avant #41.
    public var runs: [Run]?
    /// PDF à texte intégré : lignes lues par OvisOCR2 absentes de ce texte (texte des images d'illustration), par page.
    public var imageText: [Int: [String]]?

    public init(documentId: String) { self.documentId = documentId }

    /// Fiabilité du document : lignes confirmées / lignes comparées (toutes pages).
    public var reliability: Double {
        let checked = pages.values.reduce(0) { $0 + $1.lines - $1.unchecked }
        let confirmed = pages.values.reduce(0) { $0 + $1.confirmed }
        return checked > 0 ? Double(confirmed) / Double(checked) : 1
    }

    /// Fiabilité en pourcentage, arrondie au dixième (87,3), pour l'affichage. Toujours un `Double` :
    /// un entier formaté avec `%.1f` s'affichait « 0,0 % » (RET-044, Issue #65).
    public var reliabilityPercent: Double { (reliability * 1000).rounded() / 10 }

    public var openDisagreements: Int { pages.values.reduce(0) { $0 + $1.disagreements.filter { !$0.settled }.count } }
    /// Pages en erreur, et pages qu'aucun autre modèle n'a pu comparer (rien de confirmé ni d'infirmé).
    public var errorPages: Int { pages.values.filter { $0.error != nil }.count }
    public var uncheckedPages: Int { pages.values.filter { $0.lines > 0 && $0.lines == $0.unchecked }.count }

    /// Vote d'une page. `readings` : pour chaque autre modèle, son Markdown de la page.
    /// `tieBreak` : parmi plusieurs textes à égalité, celui que le dictionnaire préfère (moins de mots inconnus).
    /// `preferred` : lecteur conseillé d'abord (OvisOCR2, décision de NOxygen59 du 28/10, #41) : sa lecture est
    /// conseillée sauf si deux autres lectures s'accordent contre elle ; sans lui, majorité puis dictionnaire.
    public static func vote(source: Int, base: OCRPage, readings: [String: String], preferred: String? = nil,
                            tieBreak: ([String]) async -> String?) async -> Page {
        var page = Page(source: source, baseEngine: base.engine)
        let aligned = readings.mapValues { OCRReferenceDiff.align(base, reference: $0) }
        for (l, line) in base.lines.enumerated() {
            let current = line.text.filter { !$0.isWhitespace && !OCRReferenceDiff.ignored.contains($0) }
            guard !current.isEmpty else { continue }
            page.lines += 1
            // Corrigée à la main : c'est toi qui as tranché.
            if line.edited == true { page.confirmed += 1; continue }
            let others = aligned.compactMapValues { $0[l] }
            guard !others.isEmpty else { page.unchecked += 1; continue }
            // Voix : l'OCR habituel + chaque autre modèle.
            var votes: [String: Int] = [current: 1]
            for text in others.values { votes[text, default: 0] += 1 }
            let best = votes.values.max() ?? 0
            let leaders = votes.filter { $0.value == best }.map(\.key).sorted()
            if best >= 2, leaders == [current] {
                page.confirmed += 1
                continue
            }
            var advised: String?
            if let preferred, let favourite = others[preferred], !(best >= 2 && leaders.count == 1 && leaders[0] != favourite) {
                advised = favourite
            } else if best >= 2, leaders.count == 1 {
                advised = leaders[0]
            } else {
                advised = await tieBreak(Array(votes.keys).sorted())
            }
            page.disagreements.append(LineVote(line: l, base: line.text, readings: others, advised: advised))
        }
        return page
    }

    /// Note un lancement (20 gardés au plus).
    public mutating func recordRun(_ run: Run) {
        var list = runs ?? []
        list.append(run)
        if list.count > 20 { list.removeFirst(list.count - 20) }
        runs = list
    }

    /// Lignes de `reading` (Markdown d'un modèle) qui n'apparaissent pas dans `base` (texte intégré au PDF) : le
    /// texte que seul le modèle voit, en pratique celui des images. Comparaison sans espaces ni ponctuation ignorée
    /// par ``OCRReferenceDiff`` ; les lignes de moins de deux caractères utiles, et celles déjà contenues dans une
    /// ligne relevée, sont laissées de côté.
    public static func textOutsideBase(_ base: String, reading: String) -> [String] {
        func key(_ text: String) -> String { text.filter { !$0.isWhitespace && !OCRReferenceDiff.ignored.contains($0) } }
        let baseKey = key(base)
        var seen: [String] = []
        return reading.split(whereSeparator: \.isNewline).compactMap { raw in
            var line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("![") { return nil }                         // image décrite, pas du texte
            while let first = line.first, "#>*-|+".contains(first) { line.removeFirst() }
            line = line.replacingOccurrences(of: "|", with: " ").replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: .whitespaces)
            let k = key(line)
            // Déjà relevée, même dans une ligne plus longue (cellule de tableau répétée en liste…).
            guard k.count >= 2, !baseKey.contains(k), !seen.contains(where: { $0.contains(k) }) else { return nil }
            seen.append(k)
            return line
        }
    }
}
