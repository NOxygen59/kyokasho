// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation

/// Mise en forme du texte OCR : lignes → blocs (colonnes) → paragraphes, titres et tableaux, puis Markdown.
/// Même idée que la chaîne de Marker (blocs de mise en page, ordre de lecture, fusion des lignes,
/// détection des tableaux), réécrite en Swift et en géométrie seule : tout se fait sur l'iPad, sans modèle.
public enum OCRLayout {
    public enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case table([[String]])
    }

    /// Zone repérée par un modèle de mise en page (PP-DocLayout, DocLayout-YOLO), cadre normalisé de la page.
    public struct Region: Sendable, Hashable {
        public enum Kind: Sendable, Hashable { case title(level: Int), text, table, caption, figure, formula, ignored }
        public var box: NormBox
        public var kind: Kind
        /// Ordre de lecture donné par le modèle (`nil` : ordre des lignes du moteur OCR).
        public var order: Double?

        public init(box: NormBox, kind: Kind, order: Double?) {
            self.box = box
            self.kind = kind
            self.order = order
        }
    }

    /// Avec des zones de mise en page : chaque ligne OCR va dans la zone qui la contient, la zone décide
    /// (titre, paragraphes, tableau ; en-têtes / pieds de page écartés). Lignes hors zones : géométrie seule.
    public static func blocks(_ page: OCRPage, regions: [Region]) -> [Block] {
        let lines = page.lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty, !regions.isEmpty else { return blocks(page) }
        var members = [[Int]](repeating: [], count: regions.count)
        var loose: [OCRLine] = []
        for (i, line) in lines.enumerated() {
            let area = max(line.box.w * line.box.h, 1e-9)
            let best = regions.indices.map { r -> (Int, Double) in
                let b = regions[r].box
                let inter = overlap(line.box.x, line.box.x + line.box.w, b.x, b.x + b.w) * overlap(line.box.y, line.box.y + line.box.h, b.y, b.y + b.h)
                return (r, inter / area)
            }.max { $0.1 < $1.1 }
            if let best, best.1 >= 0.5 { members[best.0].append(i) } else { loose.append(line) }
        }
        let sizes = lines.map(size).sorted()
        let median = sizes[sizes.count / 2]
        var items: [(order: Double, block: Block)] = []
        for (r, region) in regions.enumerated() where !members[r].isEmpty {
            let regionLines = members[r].map { lines[$0] }
            let order = region.order ?? Double(members[r].min() ?? 0)
            switch region.kind {
            case .ignored: continue
            case .title(let level): items.append((order, .heading(level: level, text: join(sorted(regionLines)))))
            case .table:
                if let table = tables(regionLines, median: median).first, table.members.count == regionLines.count {
                    items.append((order, .table(table.rows)))
                } else {
                    // Tableau que la géométrie ne sait pas découper : une rangée par ligne.
                    items.append((order, .table(sorted(regionLines).map { [$0.text] })))
                }
            case .text, .caption, .figure, .formula:
                for paragraph in paragraphs(sorted(regionLines)) { items.append((order, .paragraph(paragraph))) }
            }
        }
        if !loose.isEmpty {
            let extra = blocks(OCRPage(engine: page.engine, lines: loose, durationMs: 0))
            // Sans ordre du modèle pour elles : placées après les zones.
            let last = (items.map(\.order).max() ?? 0) + 1
            items += extra.map { (last, $0) }
        }
        return items.enumerated().sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }.map(\.element.block)
    }

    public static func blocks(_ page: OCRPage) -> [Block] {
        let lines = page.lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return [] }
        let sizes = lines.map(size).sorted()
        let median = sizes[sizes.count / 2]

        // 1. Tableaux : rangées d'au moins deux cellules horizontales bien séparées, sur deux rangées ou plus.
        var used = Set<Int>()
        var items: [(order: Int, block: Block)] = []
        for table in tables(lines, median: median) {
            used.formUnion(table.members)
            items.append((table.members.min() ?? 0, .table(table.rows)))
        }

        // 2. Blocs : lignes voisines de même sens et de même taille (union-find).
        let rest = lines.indices.filter { !used.contains($0) }
        var parent = Dictionary(uniqueKeysWithValues: rest.map { ($0, $0) })
        func root(_ i: Int) -> Int { var i = i; while parent[i]! != i { i = parent[i]! }; return i }
        for (k, i) in rest.enumerated() {
            for j in rest[(k + 1)...] where sameBlock(lines[i], lines[j]) {
                let a = root(i), b = root(j)
                if a != b { parent[max(a, b)] = min(a, b) }
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in rest { groups[root(i), default: []].append(i) }

        // 3. Chaque bloc : titre ou paragraphes. Ordre de lecture = celui du moteur (première ligne du bloc).
        for members in groups.values {
            let blockLines = members.map { lines[$0] }
            let order = members.min() ?? 0
            let blockSize = blockLines.map(size).reduce(0, +) / Double(blockLines.count)
            if blockLines.count <= 2, blockSize > median * 1.3 {
                let text = join(sorted(blockLines))
                items.append((order, .heading(level: blockSize > median * 1.8 ? 1 : 2, text: text)))
            } else {
                for paragraph in paragraphs(sorted(blockLines)) { items.append((order, .paragraph(paragraph))) }
            }
        }
        // Tri stable : les paragraphes d'un même bloc gardent leur ordre.
        return items.enumerated().sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }.map(\.element.block)
    }

    /// Colonnes d'une page verticale dans l'ordre de lecture, sans dépendre de l'ordre du moteur : les lignes voisines
    /// forment des blocs, les blocs à la même hauteur une bande. Bandes de haut en bas, blocs de droite à gauche.
    public static func verticalReadingOrder(_ page: OCRPage) -> [OCRLine] {
        let lines = page.lines
        let groups = readingGroups(lines)
        struct Section { let lines: [OCRLine]; let top: Double; let bottom: Double; let right: Double }
        let sections = groups.values.map { group in
            Section(lines: sorted(group), top: group.map(\.box.y).min() ?? 0,
                    bottom: group.map { $0.box.y + $0.box.h }.max() ?? 0, right: group.map { $0.box.x + $0.box.w }.max() ?? 0)
        }.sorted { ($0.top, -$0.right) < ($1.top, -$1.right) }
        var bands: [(bottom: Double, top: Double, sections: [Section])] = []
        for section in sections {
            if let last = bands.indices.last,
               overlap(bands[last].top, bands[last].bottom, section.top, section.bottom) > 0.5 * min(bands[last].bottom - bands[last].top, section.bottom - section.top) {
                bands[last].sections.append(section)
                bands[last].bottom = max(bands[last].bottom, section.bottom)
            } else {
                bands.append((section.bottom, section.top, [section]))
            }
        }
        return bands.flatMap { $0.sections.sorted { $0.right > $1.right }.flatMap(\.lines) }
    }

    /// Blocs de lignes voisines. Balayage presque linéaire sur une vraie page ; quadratique seulement si toutes les lignes
    /// se chevauchent, ce qu'une page ne fait pas : limite acceptée, une page garde quelques centaines de lignes.
    static func readingGroups(_ lines: [OCRLine]) -> [Int: [OCRLine]] {
        var parent = Array(lines.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        // Balayage : `sameBlock` exige un écart inférieur à 1,2 fois la plus grande taille. Triées par début, les lignes
        // au-delà de cette distance sont donc ignorées, ainsi que toutes les suivantes. Seules les voisines sont comparées.
        let reach = (lines.map(size).max() ?? 0) * 1.2
        for vertical in [true, false] {
            func start(_ i: Int) -> Double { vertical ? lines[i].box.x : lines[i].box.y }
            func end(_ i: Int) -> Double { vertical ? lines[i].box.x + lines[i].box.w : lines[i].box.y + lines[i].box.h }
            let order = lines.indices.filter { lines[$0].vertical == vertical }.sorted { start($0) < start($1) }
            var active: [Int] = []
            for j in order {
                active.removeAll { start(j) - end($0) >= reach }
                for i in active where sameBlock(lines[i], lines[j]) {
                    let a = root(i), b = root(j)
                    if a != b { parent[b] = a }
                }
                active.append(j)
            }
        }
        var groups: [Int: [OCRLine]] = [:]
        for i in lines.indices { groups[root(i), default: []].append(lines[i]) }
        return groups
    }

    public static func markdown(_ page: OCRPage) -> String {
        markdown(blocks(page))
    }

    public static func markdown(_ blocks: [Block]) -> String {
        blocks.map { block -> String in
            switch block {
            case .heading(let level, let text): return String(repeating: "#", count: level) + " " + text
            case .paragraph(let text): return text
            case .table(let rows):
                guard let first = rows.first else { return "" }
                let width = rows.map(\.count).max() ?? first.count
                func row(_ r: [String]) -> String {
                    "| " + (r + Array(repeating: "", count: width - r.count)).map { $0.replacingOccurrences(of: "|", with: "\\|") }
                        .joined(separator: " | ") + " |"
                }
                return ([row(first), "|" + Array(repeating: " --- |", count: width).joined()] + rows.dropFirst().map(row))
                    .joined(separator: "\n")
            }
        }.joined(separator: "\n\n")
    }

    // MARK: Géométrie

    /// Taille d'un caractère : hauteur d'une ligne horizontale, largeur d'une colonne verticale.
    static func size(_ l: OCRLine) -> Double { l.vertical ? l.box.w : l.box.h }

    static func overlap(_ a0: Double, _ a1: Double, _ b0: Double, _ b1: Double) -> Double {
        max(0, min(a1, b1) - max(a0, b0))
    }

    static func sameBlock(_ a: OCRLine, _ b: OCRLine) -> Bool {
        guard a.vertical == b.vertical else { return false }
        let sa = size(a), sb = size(b)
        guard min(sa, sb) / max(sa, sb) > 0.7 else { return false }
        let s = max(sa, sb)
        if a.vertical {
            // Colonnes voisines (droite → gauche) qui se recouvrent en hauteur.
            let gap = max(a.box.x, b.box.x) - min(a.box.x + a.box.w, b.box.x + b.box.w)
            let common = overlap(a.box.y, a.box.y + a.box.h, b.box.y, b.box.y + b.box.h)
            return gap < s * 1.2 && common > 0.3 * min(a.box.h, b.box.h)
        } else {
            let gap = max(a.box.y, b.box.y) - min(a.box.y + a.box.h, b.box.y + b.box.h)
            let common = overlap(a.box.x, a.box.x + a.box.w, b.box.x, b.box.x + b.box.w)
            return gap < s * 1.2 && common > 0.3 * min(a.box.w, b.box.w)
        }
    }

    /// Lignes d'un bloc dans l'ordre : de haut en bas (horizontal), de droite à gauche (vertical).
    static func sorted(_ lines: [OCRLine]) -> [OCRLine] {
        lines.sorted { $0.vertical ? $0.box.midX > $1.box.midX : $0.box.midY < $1.box.midY }
    }

    /// Coupe un bloc en paragraphes : alinéa (retrait d'un caractère) ou ligne précédente courte.
    // FDR-5 : texte vertical (classe `vertical_text` de PP-DocLayout) → ordre droite → gauche. Voir § 6 étape 5.
    static func paragraphs(_ lines: [OCRLine]) -> [String] {
        guard let first = lines.first else { return [] }
        let s = lines.map(size).reduce(0, +) / Double(lines.count)
        let start = lines.map { $0.vertical ? $0.box.y : $0.box.x }.min() ?? 0
        let end = lines.map { $0.vertical ? $0.box.y + $0.box.h : $0.box.x + $0.box.w }.max() ?? 1
        var out: [[OCRLine]] = [[first]]
        for (prev, line) in zip(lines, lines.dropFirst()) {
            let indent = (line.vertical ? line.box.y : line.box.x) - start > s * 0.7
            let prevShort = end - (prev.vertical ? prev.box.y + prev.box.h : prev.box.x + prev.box.w) > s * 1.5
            if indent || prevShort { out.append([line]) } else { out[out.count - 1].append(line) }
        }
        return out.map(join)
    }

    /// Lignes recollées : rien entre deux caractères japonais, une espace entre deux mots latins.
    static func join(_ lines: [OCRLine]) -> String {
        var text = ""
        for line in lines {
            let piece = line.text.trimmingCharacters(in: .whitespaces)
            if let last = text.last, let next = piece.first, last.isASCII, next.isASCII, last.isLetter || last.isNumber,
               next.isLetter || next.isNumber {
                text += " "
            }
            text += piece
        }
        return text
    }

    struct Table { var rows: [[String]]; var members: Set<Int> }

    /// Tableaux : lignes horizontales groupées en rangées (même hauteur), cellules séparées par un vide
    /// de plus de deux caractères, cellules courtes ; au moins deux rangées voisines d'au moins deux cellules.
    // FDR-5 : cellules exactes par PP-Structure SLANet (ONNX, demander le téléchargement). Voir § 6 étape 5.
    static func tables(_ lines: [OCRLine], median: Double) -> [Table] {
        let horizontal = lines.indices.filter { !lines[$0].vertical }.sorted { lines[$0].box.midY < lines[$1].box.midY }
        var rows: [[Int]] = []
        for i in horizontal {
            let l = lines[i]
            if let last = rows.last, let ref = last.first,
               overlap(l.box.y, l.box.y + l.box.h, lines[ref].box.y, lines[ref].box.y + lines[ref].box.h) > 0.5 * min(l.box.h, lines[ref].box.h) {
                rows[rows.count - 1].append(i)
            } else {
                rows.append([i])
            }
        }
        func isTableRow(_ row: [Int]) -> Bool {
            guard row.count >= 2 else { return false }
            let cells = row.sorted { lines[$0].box.x < lines[$1].box.x }
            // Cellules courtes (≤ ~12 caractères) : deux colonnes de texte ne sont pas un tableau.
            guard cells.allSatisfy({ lines[$0].box.w < 12 * median }) else { return false }
            return zip(cells, cells.dropFirst()).allSatisfy { a, b in
                lines[b].box.x - (lines[a].box.x + lines[a].box.w) > 2 * median
            }
        }
        var tables: [Table] = []
        var run: [[Int]] = []
        func flush() {
            defer { run = [] }
            guard run.count >= 2 else { return }
            // Colonnes : bords gauches de la rangée la plus remplie ; chaque cellule va à la plus proche.
            let widest = run.max { $0.count < $1.count }!.sorted { lines[$0].box.x < lines[$1].box.x }
            let columns = widest.map { lines[$0].box.midX }
            var rowsText: [[String]] = []
            for row in run {
                var cells = [String](repeating: "", count: columns.count)
                for i in row.sorted(by: { lines[$0].box.x < lines[$1].box.x }) {
                    let mid = lines[i].box.midX
                    let c = columns.indices.min { abs(columns[$0] - mid) < abs(columns[$1] - mid) }!
                    cells[c] = cells[c].isEmpty ? lines[i].text : cells[c] + " " + lines[i].text
                }
                rowsText.append(cells)
            }
            tables.append(Table(rows: rowsText, members: Set(run.joined())))
        }
        for row in rows {
            if isTableRow(row), let last = run.last?.first,
               lines[row[0]].box.y - (lines[last].box.y + lines[last].box.h) < 2.5 * median {
                run.append(row)
            } else {
                flush()
                if isTableRow(row) { run = [row] }
            }
        }
        flush()
        return tables
    }
}
