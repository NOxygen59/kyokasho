// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreText
import Foundation
import OCRKit
import PDFKit
import ReaderCore

/// Furigana dessinés sur la page (option) : au-dessus des kanji en horizontal, à droite en vertical.
/// Positions : texte intégré du PDF (`characterBounds`) ou boîtes de caractères de l'OCR (scans).
/// Lectures : dictionnaire installé ou `Furigana` (MeCab / analyseur japonais du système).
enum FuriganaLayer {
    static let storageKey = "reader.furigana"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: storageKey) }

    /// Couleur des furigana (menu « … » → Affichage) : foncée sur la page, claire dans le panneau sombre.
    enum Tint: String, CaseIterable, Identifiable {
        case red, blue, green, purple, orange, black
        static let storageKey = "reader.furiganaColor"
        static var current: Tint { UserDefaults.standard.string(forKey: storageKey).flatMap(Tint.init) ?? .red }
        var id: String { rawValue }
        var title: String {
            switch self {
            case .red: return "Rouge"
            case .blue: return "Bleu"
            case .green: return "Vert"
            case .purple: return "Violet"
            case .orange: return "Orange"
            case .black: return "Noir"
            }
        }
        /// Sur la page (papier clair).
        var page: (r: CGFloat, g: CGFloat, b: CGFloat) {
            switch self {
            case .red: return (0.62, 0.12, 0.10)
            case .blue: return (0.10, 0.25, 0.65)
            case .green: return (0.08, 0.45, 0.20)
            case .purple: return (0.45, 0.15, 0.60)
            case .orange: return (0.80, 0.38, 0.02)
            case .black: return (0.10, 0.10, 0.10)
            }
        }
        /// Dans le panneau d'étude : couleur de la page sur un thème clair, version claire sur un thème nuit.
        var panelHex: String {
            guard !Theme.current.isLight else {
                let c = page
                return String(format: "#%02x%02x%02x", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255))
            }
            return darkPanelHex
        }
        /// Version claire, pour un panneau sombre.
        private var darkPanelHex: String {
            switch self {
            case .red: return "#ff7a6b"
            case .blue: return "#7fb2ff"
            case .green: return "#6fd28a"
            case .purple: return "#c79bff"
            case .orange: return "#ffb05c"
            case .black: return "#d9d9d9"
            }
        }
    }

    /// Une lecture, dans le repère absolu de la page (celui de `cropBox`).
    struct Mark: Sendable {
        var rect: CGRect
        var reading: String
        var vertical: Bool
        /// Taille de police maximale : place libre au-dessus (ou à droite en vertical) jusqu'à la ligne voisine.
        var maxSize: CGFloat = .greatestFiniteMagnitude
    }

    /// Place libre au-dessus du mot (horizontal) ou à sa droite (vertical), jusqu'à la ligne la plus proche
    /// qui le recouvre. Sans voisine : 60 % du caractère.
    static func room(for rect: CGRect, vertical: Bool, among lines: [CGRect]) -> CGFloat {
        let base = vertical ? rect.width : rect.height
        var gap = base * 0.6
        for other in lines where other != rect && !other.contains(CGPoint(x: rect.midX, y: rect.midY)) {
            if vertical {
                guard other.minX >= rect.maxX - base * 0.1, other.maxY > rect.minY, other.minY < rect.maxY else { continue }
                gap = min(gap, other.minX - rect.maxX)
            } else {
                guard other.minY >= rect.maxY - base * 0.1, other.maxX > rect.minX, other.minX < rect.maxX else { continue }
                gap = min(gap, other.minY - rect.maxY)
            }
        }
        return max(0, gap)
    }

    // MARK: Cache (lu par PDFKit depuis ses fils de dessin)

    private static let lock = NSLock()
    private static var marks: [String: [Mark]] = [:]
    private static var order: [String] = []
    private static let limit = 40

    static func marks(for key: String) -> [Mark]? {
        guard enabled else { return nil }
        return lock.withLock { marks[key] }
    }

    static func has(_ key: String) -> Bool { lock.withLock { marks[key] != nil } }

    static func set(_ list: [Mark], for key: String) {
        lock.withLock {
            marks[key] = list
            order.removeAll { $0 == key }
            order.append(key)
            while order.count > limit { marks[order.removeFirst()] = nil }
        }
    }

    static func clearMemory() { lock.withLock { marks = [:]; order = [] } }

    // MARK: Calcul

    /// Scan : boîtes OCR normalisées → repère de la page (rotation intrinsèque comprise, voir `PageFrame`).
    // FDR-3 : sauter les kanji qui ont déjà des furigana imprimés (lignes OCR très fines collées à la ligne) et ne pas les compter comme obstacles. Voir § 6 étape 3.
    /// `reference` : Markdown d'OvisOCR2 de la page (texte fiable). Les lignes qu'il recouvre prennent son texte
    /// (lectures justes), posé sur les boîtes de caractères de l'OCR (`OCRReferenceDiff.alignedLines`) ; les
    /// autres gardent le texte de l'OCR. Les lectures peuvent venir du même dictionnaire que le panneau OCR.
    static func marks(from ocr: OCRPage, reference: String? = nil, frame: PageFrame,
                      readings: ((String) -> [(range: Range<Int>, reading: String)])? = nil) -> [Mark] {
        let lineRects = ocr.lines.map { frame.pageRect($0.box) }
        var fromAI: [Int: OCRReferenceDiff.AlignedLine] = [:]
        if let reference { for a in OCRReferenceDiff.alignedLines(ocr, reference: reference) { fromAI[a.line] = a } }
        return ocr.lines.enumerated().flatMap { l, line -> [Mark] in
            let text: String, boxes: [NormBox?]
            if let aligned = fromAI[l] {
                text = aligned.text
                boxes = aligned.boxes
            } else {
                // Une boîte par caractère, sinon les lectures tomberaient sur les mauvais caractères.
                guard line.charBoxes.count == line.text.count else { return [] }
                text = line.text
                boxes = line.charBoxes
            }
            guard text.contains(where: Furigana.isKanji) else { return [] }
            let lineRect = lineRects[l]
            let measured = line.measuredCharBoxes && boxes.compactMap { $0 }.count >= 2
            let placed = boxes.compactMap { $0 }.map { frame.pageRect($0) }
            let stacked = measured && abs(placed.last!.midY - placed.first!.midY) >
                abs(placed.last!.midX - placed.first!.midX) * 1.5
            let vertical = frame.isVerticalOnPage(lineVertical: line.vertical) || stacked
                || (text.count >= 2 && lineRect.height > lineRect.width * 1.45)
            // Des caractères isolés empilés dans une légende verticale ne forment pas des mots :
            // le dictionnaire peut leur attribuer des lectures de prénom sans rapport.
            let verticalNeighbour = lineRects.enumerated().contains { index, other in
                guard index != l, ocr.lines[index].text.count == 1 else { return false }
                let closeX = abs(other.midX - lineRect.midX) < max(other.width, lineRect.width) * 0.65
                let gap = max(0, max(other.minY - lineRect.maxY, lineRect.minY - other.maxY))
                return closeX && gap < max(other.height, lineRect.height) * 1.7
            }
            if text.count == 1 && (lineRect.height > lineRect.width * 1.35 || verticalNeighbour) { return [] }
            let rubies = readings?(text) ?? Furigana.rubies(for: text).map { (range: $0.range, reading: $0.reading) }
            return rubies.compactMap { ruby in
                // Caractère ajouté par l'IA (sans boîte) : la lecture se pose sur ceux du groupe qui en ont une.
                let rect = boxes[ruby.range].compactMap { $0 }.reduce(CGRect.null) { $0.union(frame.pageRect($1)) }
                guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }
                // La place se mesure depuis la ligne entière (pas seulement le mot).
                let wordInLine = vertical
                    ? CGRect(x: lineRect.minX, y: rect.minY, width: lineRect.width, height: rect.height)
                    : CGRect(x: rect.minX, y: lineRect.minY, width: rect.width, height: lineRect.height)
                let others = lineRects.enumerated().filter { $0.offset != l }.map(\.element)
                return Mark(rect: rect, reading: ruby.reading, vertical: vertical,
                            maxSize: room(for: wordInLine, vertical: vertical, among: others) * 0.85)
            }
        }
    }

    /// PDF numérique : texte intégré, ligne par ligne, positions de chaque caractère.
    static func marks(from page: PDFPage) -> [Mark] {
        guard let text = page.string, !text.isEmpty else { return [] }
        let ns = text as NSString
        var out: [Mark] = []
        // (`selection(for:)` suit les index de `page.string` ; `characterBounds` compte autrement les fins de ligne.)
        func bounds(_ range: NSRange) -> CGRect { page.selection(for: range)?.bounds(for: page) ?? .null }
        var lineRanges: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, r, _, _ in
            lineRanges.append(r)
        }
        let lineRects = lineRanges.map(bounds).filter { !$0.isNull && $0.width > 0 }
        for lineRange in lineRanges {
            let rubies = Furigana.rubies(for: ns.substring(with: lineRange))
            guard !rubies.isEmpty else { continue }
            let lineRect = bounds(lineRange)
            // Sens de la ligne : deux premiers caractères visibles l'un sous l'autre → vertical.
            let visible = (lineRange.location..<NSMaxRange(lineRange)).lazy
                .map { bounds(NSRange(location: $0, length: 1)) }.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }.prefix(2)
            let pair = Array(visible)
            let vertical = pair.count == 2 && abs(pair[1].midY - pair[0].midY) > abs(pair[1].midX - pair[0].midX)
            for ruby in rubies {
                let rect = bounds(NSRange(location: lineRange.location + ruby.utf16.location, length: ruby.utf16.length))
                guard !rect.isNull, rect.width > 0, rect.height > 0 else { continue }
                let wordInLine = lineRect.isNull ? rect : vertical
                    ? CGRect(x: lineRect.minX, y: rect.minY, width: lineRect.width, height: rect.height)
                    : CGRect(x: rect.minX, y: lineRect.minY, width: rect.width, height: lineRect.height)
                out.append(Mark(rect: rect, reading: ruby.reading, vertical: vertical,
                                maxSize: room(for: wordInLine, vertical: vertical, among: lineRects.filter { $0 != lineRect }) * 0.85))
            }
        }
        return out
    }

    // MARK: Dessin

    /// Taille et bande (fond + kana) de chaque lecture, dans le repère absolu de la page.
    struct Placed {
        var reading: [Character]
        var vertical: Bool
        var size: CGFloat
        var strip: CGRect
    }

    /// Taille : 45 % du caractère (comme en 0.8.0), réduite par la place libre mais jamais sous 32 %.
    /// Une lecture longue déborde du mot ; les bandes d'une même ligne sont ensuite écartées (`spread`)
    /// pour ne jamais se chevaucher.
    static func layout(_ marks: [Mark]) -> [Placed] {
        var placed: [Placed] = marks.compactMap { mark in
            let kana = Array(mark.reading)
            guard !kana.isEmpty else { return nil }
            let count = CGFloat(kana.count)
            let base = mark.vertical ? mark.rect.width : mark.rect.height
            let span = mark.vertical ? mark.rect.height : mark.rect.width
            var size = min(base * 0.45, max(mark.maxSize, base * 0.32))
            // Très longue lecture sur un mot court : on serre un peu, jusqu'à 3 fois la largeur du mot.
            if size * count > span * 3 { size = max(base * 0.28, span * 3 / count) }
            let total = size * count
            let strip = mark.vertical
                ? CGRect(x: mark.rect.maxX + size * 0.05, y: mark.rect.midY - total / 2, width: size, height: total)
                : CGRect(x: mark.rect.midX - total / 2, y: mark.rect.maxY + size * 0.08, width: total, height: size)
            return Placed(reading: kana, vertical: mark.vertical, size: size, strip: strip)
        }
        // Lignes : même sens, bandes qui se recouvrent sur l'axe transversal.
        func cross(_ p: Placed) -> (CGFloat, CGFloat) { p.vertical ? (p.strip.minX, p.strip.maxX) : (p.strip.minY, p.strip.maxY) }
        var lines: [[Int]] = []
        for i in placed.indices.sorted(by: { cross(placed[$0]).0 < cross(placed[$1]).0 }) {
            let (lo, hi) = cross(placed[i])
            if let j = lines.indices.last(where: { k in
                let first = placed[lines[k][0]]
                let (flo, fhi) = cross(first)
                return first.vertical == placed[i].vertical && min(hi, fhi) - max(lo, flo) > (hi - lo) * 0.5
            }) {
                lines[j].append(i)
            } else {
                lines.append([i])
            }
        }
        for line in lines where line.count > 1 {
            // Position le long de la lecture : x en horizontal, -y en vertical (de haut en bas).
            let vertical = placed[line[0]].vertical
            let order = line.sorted {
                vertical ? placed[$0].strip.maxY > placed[$1].strip.maxY : placed[$0].strip.minX < placed[$1].strip.minX
            }
            let gap = (order.map { placed[$0].size }.min() ?? 0) * 0.3
            let starts = spread(order.map { i in
                let s = placed[i].strip
                return vertical ? (start: -s.maxY, length: s.height) : (start: s.minX, length: s.width)
            }, gap: gap)
            for (i, start) in zip(order, starts) {
                if vertical { placed[i].strip.origin.y = -start - placed[i].strip.height } else { placed[i].strip.origin.x = start }
            }
        }
        return placed
    }

    /// Écarte des intervalles triés (début voulu, longueur) pour qu'ils restent séparés de `gap`, en bougeant
    /// le moins possible : les intervalles qui se touchent forment un bloc posé sur la moyenne de leurs positions.
    static func spread(_ items: [(start: CGFloat, length: CGFloat)], gap: CGFloat) -> [CGFloat] {
        typealias Block = (offsets: [CGFloat], sum: CGFloat, length: CGFloat)
        func start(_ b: Block) -> CGFloat { b.sum / CGFloat(b.offsets.count) }
        var blocks: [Block] = []
        for item in items {
            var block: Block = ([0], item.start, item.length)
            while let last = blocks.last, start(last) + last.length + gap > start(block) {
                blocks.removeLast()
                let shift = last.length + gap
                block = (last.offsets + block.offsets.map { $0 + shift },
                         last.sum + block.sum - shift * CGFloat(block.offsets.count), shift + block.length)
            }
            blocks.append(block)
        }
        return blocks.flatMap { b in b.offsets.map { start(b) + $0 } }
    }

    /// Dans le repère de la page (y vers le haut), déjà transformé par l'appelant.
    /// Fond couleur papier sous les kana, pour rester lisible sur un dessin ou une trame.
    // FDR-3 : texte vertical jamais vérifié (kana à droite de la colonne, de haut en bas ; `room` mesure la colonne de droite). Voir § 6 étape 3.
    static func draw(_ marks: [Mark], in context: CGContext) {
        context.saveGState()
        context.textMatrix = .identity
        let color = Tint.current.page
        for mark in layout(marks) {
            let size = mark.size, strip = mark.strip
            let font = CTFontCreateWithName("HiraginoSans-W5" as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ]
            // Pas de fond derrière les lectures (demande de l'utilisateur) : texte seul, dans la couleur choisie.
            context.setFillColor(red: color.r, green: color.g, blue: color.b, alpha: 1)
            for (i, c) in mark.reading.enumerated() {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(c), attributes: attributes))
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                if mark.vertical {
                    context.textPosition = CGPoint(x: strip.minX + (size - width) / 2, y: strip.maxY - CGFloat(i + 1) * size + size * 0.14)
                } else {
                    context.textPosition = CGPoint(x: strip.minX + CGFloat(i) * size + (size - width) / 2, y: strip.minY + size * 0.14)
                }
                CTLineDraw(line, context)
            }
        }
        context.restoreGState()
    }
}
