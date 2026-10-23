// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GLMOCRKit
import OCRKit
import ReaderCore

/// Recherche locale dans les pages déjà lues par OvisOCR2. Aucun PDF ni modèle n'est relu ici.
enum DocumentKnowledge {
    struct Passage: Sendable {
        let page: Int
        let text: String
        let score: Int
    }

    static func readCount(_ document: LibraryDocument) -> Int {
        (0..<document.pageCount).filter {
            let file = DocumentAnalysisService.rawURL(document.id, ModelSpec.ovisocr2.id, $0)
            return ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        }.count
    }

    static func isReady(_ document: LibraryDocument) -> Bool {
        document.pageCount > 0 && readCount(document) == document.pageCount
    }

    /// La reformulation japonaise vient de Qwen ; seuls les mots effectivement présents dans le manuel comptent.
    static func passages(for document: LibraryDocument, question: String, japaneseTerms: String,
                         limit: Int = 4) -> [Passage] {
        let terms = searchTerms(question + " " + japaneseTerms)
        let cited = explicitPages(question, document: document)
        var matches: [Passage] = []
        for page in 0..<document.pageCount {
            guard let content = try? String(contentsOf: DocumentAnalysisService.rawURL(document.id, ModelSpec.ovisocr2.id, page), encoding: .utf8) else { continue }
            if cited.contains(page) {
                matches.append(Passage(page: page, text: String(content.prefix(1500)), score: 100))
                continue
            }
            let blocks = content.components(separatedBy: "\n\n")
            for block in blocks {
                let clean = block.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }
                let normalized = clean.folding(options: String.CompareOptions([.caseInsensitive, .diacriticInsensitive]), locale: .current)
                let score = terms.reduce(0) { $0 + (normalized.contains($1) ? max(1, $1.count / 2) : 0) }
                if score > 0 {
                    let hit = terms.first { normalized.contains($0) }
                    let start = hit.flatMap { clean.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }
                        .flatMap { clean.index($0.lowerBound, offsetBy: -150, limitedBy: clean.startIndex) } ?? clean.startIndex
                    let end = clean.index(start, offsetBy: 700, limitedBy: clean.endIndex) ?? clean.endIndex
                    matches.append(Passage(page: page, text: String(clean[start..<end]), score: score))
                }
            }
        }
        // Éviter que cinq paragraphes de la même page masquent les autres sources.
        var selected: [Passage] = []
        for passage in matches.sorted(by: { $0.score == $1.score ? $0.page < $1.page : $0.score > $1.score }) {
            if !selected.contains(where: { $0.page == passage.page }) { selected.append(passage) }
            if selected.count == limit { break }
        }
        return selected
    }

    private static func searchTerms(_ input: String) -> [String] {
        let folded = input.folding(options: String.CompareOptions([.caseInsensitive, .diacriticInsensitive]), locale: .current)
        return Array(Set(folded.split { $0.isWhitespace || $0.isPunctuation }.map(String.init)
            .filter { $0.count >= 2 && !["page", "pages", "comment", "faire", "dans", "avec", "pour", "quel", "quelle", "what", "the", "les", "des", "une", "est"].contains($0) }))
            .sorted { $0.count > $1.count }
    }

    private static func explicitPages(_ question: String, document: LibraryDocument) -> Set<Int> {
        guard let expression = try? NSRegularExpression(pattern: #"(?i)(?:p\.|pages?\s+)(\d+)"#) else { return [] }
        let range = NSRange(question.startIndex..<question.endIndex, in: question)
        return Set(expression.matches(in: question, range: range).compactMap { match in
            guard let numberRange = Range(match.range(at: 1), in: question),
                  let number = Int(question[numberRange]) else { return nil }
            return (0..<document.pageCount).first { document.pageLabel($0) == String(number) }
        })
    }
}
