// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation
import Vision

/// Lit le texte japonais vertical, que Vision ignore : sur une page de manga, il ne rend presque rien.
/// Mesuré sur une page réelle (05/11/2026) : 2 lignes seules (« 46 », « エェ ») avant, presque toutes les bulles après.
///
/// Méthode, en géométrie seule et sans modèle : (1) repérer les colonnes de petits traits entourés de blanc ; (2) découper
/// chaque colonne en caractères ; (3) les recoller à l'horizontale dans une bande ; (4) faire lire cette bande à Vision, qui
/// lit très bien l'horizontal. Les positions reviennent à la page par les cases de l'étape 2.
///
/// Limites connues : texte sur fond tramé ou dans l'image écarté ; petits kana (っ) parfois lus en grands ; le texte reste
/// un OCR, à relire par un modèle ou à la main.
enum VerticalTextReader {
    /// Rectangle en pixels, origine en haut à gauche, bornes incluses.
    struct Box: Equatable {
        var minX, minY, maxX, maxY: Int
        var width: Int { maxX - minX + 1 }
        var height: Int { maxY - minY + 1 }
        var midX: Double { Double(minX + maxX) / 2 }

        mutating func formUnion(_ other: Box) {
            minX = min(minX, other.minX)
            minY = min(minY, other.minY)
            maxX = max(maxX, other.maxX)
            maxY = max(maxY, other.maxY)
        }
    }

    /// Image en niveaux de gris, ligne par ligne depuis le haut.
    struct Bitmap {
        let width: Int
        let height: Int
        var pixels: [UInt8]

        func isInk(_ x: Int, _ y: Int) -> Bool { pixels[y * width + x] < inkLevel }
    }

    static let inkLevel: UInt8 = 128
    /// Au-delà, l'analyse réduit la page : le coût reste celui d'une page de manga, quelles que soient sa résolution et sa forme.
    static let workingSide = 1400
    /// Case carrée où l'on compte les petits traits : au-delà de `maximumStrokesPerCell`, c'est une trame et non du texte. La
    /// décision reste locale : une trame dans un coin ne coûte rien aux bulles ailleurs sur la page. Elle borne aussi le calcul,
    /// puisque le nombre de traits gardés ne peut plus dépasser cases × plafond.
    static let densityCell = 24
    static let maximumStrokesPerCell = 18
    /// Chaque colonne coûte un appel à Vision.
    static let maximumColumns = 150
    /// Le plus grand caractère attendu, en part de la hauteur de page. Au-dessus : cadres, décors, onomatopées dessinées.
    static let largestCharacter = 0.05
    /// Part de blanc autour d'un trait pour le croire dans une bulle plutôt que dans le dessin.
    static let minimumWhiteAround = 0.72

    // MARK: Lecture

    /// Lignes verticales trouvées hors des zones déjà lues (`known`). Rien si aucune colonne n'est plausible : une page
    /// horizontale déjà lue ne coûte que la recherche des colonnes.
    static func read(_ image: CGImage, languages: [String], skipping known: [NormBox]) throws -> [OCRLine] {
        guard languages.contains(where: { $0.hasPrefix("ja") }), image.height > 0, image.width > 0 else { return [] }
        let scale = min(1, Double(workingSide) / Double(max(image.height, image.width)))
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let bitmap = grayBitmap(image, width: width, height: height) else { return [] }
        var lines: [OCRLine] = []
        let found = try detect(in: bitmap, skipping: known)
        for column in found.columns.prefix(maximumColumns) {
            try Task.checkCancellation()
            let box = normalized(column, in: bitmap)
            guard !known.contains(where: { overlapShare(box, $0) > 0.3 }) else { continue }
            let cells = characterCells(of: column, in: bitmap)
            guard cells.count >= minimumCharacters, let strip = strip(cells, column: column, bitmap: bitmap),
                  let reading = recognize(strip, cellCount: cells.count), reading.confidence >= minimumConfidence,
                  let cleaned = cleaned(reading.characters) else { continue }
            let text = String(cleaned.map(\.character))
            let charBoxes = cleaned.map { character -> NormBox in
                var union = cells[character.cells.lowerBound]
                for index in character.cells { union.formUnion(cells[index]) }
                return normalized(union, in: bitmap)
            }
            // Furigana imprimés dans la bande à droite de la colonne. Deux traits au moins : un seul peut être une poussière.
            let ruby = found.small.filter { small in
                small.minX >= column.maxX - 2 && small.minX <= column.maxX + column.width
                    && small.maxY >= column.minY && small.minY <= column.maxY
            }.count >= 2
            // Positions annoncées mesurées seulement si Vision a donné une case à chaque caractère, dans l'ordre et sans
            // doublon ; sinon, cases proportionnelles marquées estimées (revue après recette 1.4.8, P2 3).
            let measured = !reading.estimated && inReadingOrder(cleaned)
            var line = OCRLine(text: text, box: box,
                               charBoxes: measured ? charBoxes : CharacterLayout.proportional(text, in: box, vertical: true),
                               measuredCharBoxes: measured, vertical: true, confidence: Double(reading.confidence))
            line.hasPrintedRuby = ruby ? true : nil
            lines.append(line)
        }
        return lines
    }

    static let minimumCharacters = 2
    static let minimumConfidence: Float = 0.3

    /// Un caractère lu et la case de la colonne où Vision l'a vu.
    struct ReadCharacter: Equatable {
        var character: Character
        var cells: ClosedRange<Int>
    }

    /// Vision dit où il a lu chaque caractère dans la bande : c'est ce qui relie le texte aux vraies cases. Compter les
    /// caractères ne suffit pas : un seul oublié décalait tout le reste, et le toucher tombait sur le mauvais mot.
    /// Cases de lecture fiables : chaque caractère après le précédent, sans case partagée.
    static func inReadingOrder(_ characters: [ReadCharacter]) -> Bool {
        zip(characters, characters.dropFirst()).allSatisfy { $1.cells.lowerBound > $0.cells.upperBound }
    }

    /// `estimated` : au moins un caractère sans boîte de Vision, placé par son rang.
    private static func recognize(_ strip: CGImage, cellCount: Int) -> (characters: [ReadCharacter], confidence: Float, estimated: Bool)? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP"]
        request.usesLanguageCorrection = true
        guard (try? VNImageRequestHandler(cgImage: strip, options: [:]).perform([request])) != nil else { return nil }
        let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
        guard !candidates.isEmpty else { return nil }
        var characters: [ReadCharacter] = []
        var estimated = false
        for candidate in candidates {
            let text = candidate.string
            var index = text.startIndex
            var order = characters.count
            while index < text.endIndex {
                let next = text.index(after: index)
                let box = (try? candidate.boundingBox(for: index..<next))?.boundingBox
                if box == nil { estimated = true }
                characters.append(ReadCharacter(character: text[index], cells: {
                    let cell = box.map { cellIndex(midX: $0.midX, stripWidth: strip.width, cellCount: cellCount) }
                        ?? min(order, cellCount - 1)
                    return cell...cell
                }()))
                order += 1
                index = next
            }
        }
        return (characters, candidates.map(\.confidence).max() ?? 0, estimated)
    }

    /// Case sous une position de la bande, de 0 à 1 sur sa largeur.
    static func cellIndex(midX: Double, stripWidth: Int, cellCount: Int) -> Int {
        let cellSide = Double(stripWidth - stripMargin * 2) / Double(max(cellCount, 1))
        return min(max(0, Int((midX * Double(stripWidth) - Double(stripMargin)) / cellSide)), cellCount - 1)
    }

    static let stripMargin = 16

    /// Les points de suspension verticaux sont lus comme des deux-points ou des points médians. Sans vrai caractère japonais,
    /// c'est un bout de dessin : rien.
    static func cleaned(_ characters: [ReadCharacter]) -> [ReadCharacter]? {
        let dots: Set<Character> = ["：", ":", "・", "･", ".", "．", "。", "…", "⋯", "•"]
        var result: [ReadCharacter] = []
        var index = 0
        while index < characters.count {
            var end = index
            while end + 1 < characters.count, dots.contains(characters[index].character), dots.contains(characters[end + 1].character) { end += 1 }
            let current = characters[index].character
            if end > index || current == "：" || current == ":" {
                // Vision peut placer deux caractères voisins dans le désordre : l'étendue se calcule sans supposer l'ordre.
                let cells = characters[index...end].map(\.cells)
                let first = cells.map(\.lowerBound).min() ?? 0, last = cells.map(\.upperBound).max() ?? first
                result.append(ReadCharacter(character: "…", cells: first...last))
            } else {
                result.append(characters[index])
            }
            index = end + 1
        }
        let japanese = result.filter { $0.character.unicodeScalars.contains {
            (0x3041...0x30FF).contains($0.value) || (0x3400...0x9FFF).contains($0.value)
        } }.count
        return japanese >= 2 ? result : nil
    }

    /// Forme texte, pour les tests.
    static func cleaned(_ text: String) -> String? {
        cleaned(text.enumerated().map { ReadCharacter(character: $0.element, cells: $0.offset...$0.offset) })
            .map { String($0.map(\.character)) }
    }

    // MARK: Colonnes

    static func columns(in bitmap: Bitmap, skipping known: [NormBox] = []) throws -> [Box] {
        try detect(in: bitmap, skipping: known).columns
    }

    /// Colonnes de droite à gauche, ordre de lecture japonais, et petits groupes écartés (furigana imprimés). Les zones déjà lues sont écartées dès le départ : une page horizontale
    /// ne laisse presque rien à regrouper, sans empêcher de lire une colonne ailleurs sur la même page.
    static func detect(in bitmap: Bitmap, skipping known: [NormBox] = []) throws -> (columns: [Box], small: [Box]) {
        let largest = Int(Double(bitmap.height) * largestCharacter)
        var groups = strokes(in: bitmap).filter { $0.width <= largest && $0.height <= largest && $0.width * $0.height >= 4 }
        // Zones déjà lues d'abord : le texte qu'elles contiennent ne doit pas compter comme de la trame.
        groups = groups.filter { stroke in
            let box = normalized(stroke, in: bitmap)
            return !known.contains { overlapShare(box, $0) > 0.5 }
        }
        groups = removingScreentone(groups)
        // Avant le filtre du blanc : un furigana serré contre son kanji n'a pas de blanc autour de lui.
        let strokesBeforeWhite = groups
        groups = groups.filter { whiteShare(around: $0, in: bitmap) > minimumWhiteAround }
        // Regroupement répété jusqu'à stabilité : deux morceaux peuvent ne se rejoindre qu'à travers un troisième.
        // Grille en X et en Y : seuls les voisins sont comparés, même si la page compte des dizaines de milliers de traits.
        let cell = max(1, largest)
        var changed = true
        while changed {
            try Task.checkCancellation()
            changed = false
            var merged: [Box?] = []
            var grid: [Int: [Int]] = [:]
            func key(_ x: Int, _ y: Int) -> Int { x &* 100_000 &+ y }
            for group in groups {
                var current = group
                var searching = true
                while searching {
                    searching = false
                    let column = Int(current.midX) / (cell * 2)
                    let rows = (current.minY / cell - 1)...(current.maxY / cell + 1)
                    search: for x in (column - 1)...(column + 1) {
                        for y in rows {
                            for index in grid[key(x, y)] ?? [] {
                                guard let other = merged[index], belongToSameColumn(other, current) else { continue }
                                current.formUnion(other)
                                merged[index] = nil
                                changed = true
                                searching = true
                                break search
                            }
                        }
                    }
                }
                merged.append(current)
                let column = Int(current.midX) / (cell * 2)
                for y in (current.minY / cell)...(current.maxY / cell) { grid[key(column, y), default: []].append(merged.count - 1) }
            }
            groups = merged.compactMap { $0 }
        }
        let tall = groups.filter { Double($0.height) >= Double($0.width) * 1.4 && $0.width >= minimumColumnWidth && $0.width <= largest }
        // Furigana imprimés : colonnes bien plus étroites que le texte. Le dictionnaire s'appuie sur le texte, pas sur eux.
        let widths = tall.map(\.width).sorted()
        let typical = widths.isEmpty ? 0 : widths[widths.count / 2]
        let limit = Double(typical) * 0.55
        return (tall.filter { Double($0.width) >= limit }.sorted { $0.midX > $1.midX },
                strokesBeforeWhite.filter { Double($0.width) < limit && Double($0.height) < limit })
    }

    static let minimumColumnWidth = 8

    private static func belongToSameColumn(_ a: Box, _ b: Box) -> Bool {
        let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX) + 1
        let wider = max(a.width, b.width)
        let gap = max(a.minY, b.minY) - min(a.maxY, b.maxY)
        return Double(overlap) / Double(min(a.width, b.width)) > 0.35
            && gap < max(6, min(wider, 30) * 5 / 8)
            && abs(a.midX - b.midX) < Double(wider) * 0.6
    }

    private static func removingScreentone(_ strokes: [Box]) -> [Box] {
        func cell(_ box: Box) -> Int { (box.minY / densityCell) &* 100_000 &+ box.minX / densityCell }
        var counts: [Int: Int] = [:]
        for stroke in strokes { counts[cell(stroke), default: 0] += 1 }
        return strokes.filter { (counts[cell($0)] ?? 0) <= maximumStrokesPerCell }
    }

    /// Composantes connexes de l'encre. Pile explicite : une récursion déborderait sur un grand aplat noir.
    static func strokes(in bitmap: Bitmap) -> [Box] {
        let width = bitmap.width, height = bitmap.height
        var seen = [Bool](repeating: false, count: width * height)
        var result: [Box] = []
        var stack: [Int] = []
        for start in 0..<(width * height) where bitmap.pixels[start] < inkLevel && !seen[start] {
            seen[start] = true
            stack.append(start)
            var box = Box(minX: start % width, minY: start / width, maxX: start % width, maxY: start / width)
            while let position = stack.popLast() {
                let x = position % width, y = position / width
                box.minX = min(box.minX, x)
                box.maxX = max(box.maxX, x)
                box.minY = min(box.minY, y)
                box.maxY = max(box.maxY, y)
                for ny in max(0, y - 1)...min(height - 1, y + 1) {
                    for nx in max(0, x - 1)...min(width - 1, x + 1) {
                        let next = ny * width + nx
                        if bitmap.pixels[next] < inkLevel && !seen[next] {
                            seen[next] = true
                            stack.append(next)
                        }
                    }
                }
            }
            result.append(box)
        }
        return result
    }

    private static func whiteShare(around box: Box, in bitmap: Bitmap) -> Double {
        let margin = max(4, box.height / 2)
        var white = 0, total = 0
        for y in max(0, box.minY - margin)...min(bitmap.height - 1, box.maxY + margin) {
            for x in max(0, box.minX - margin)...min(bitmap.width - 1, box.maxX + margin) {
                if x >= box.minX && x <= box.maxX && y >= box.minY && y <= box.maxY { continue }
                total += 1
                if bitmap.pixels[y * bitmap.width + x] > 200 { white += 1 }
            }
        }
        return total > 0 ? Double(white) / Double(total) : 0
    }

    // MARK: Caractères

    /// Découpe sur les lignes blanches, regroupe les morceaux d'un même caractère (二, 三, 小), et partage ce qui reste trop
    /// haut : un caractère japonais est à peu près carré, de la largeur de la colonne.
    static func characterCells(of column: Box, in bitmap: Bitmap) -> [Box] {
        var runs: [(start: Int, end: Int)] = []
        var runStart: Int?
        for y in column.minY...column.maxY {
            let hasInk = (column.minX...column.maxX).contains { bitmap.isInk($0, y) }
            if hasInk, runStart == nil { runStart = y }
            if !hasInk, let start = runStart {
                runs.append((start, y - 1))
                runStart = nil
            }
        }
        if let runStart { runs.append((runStart, column.maxY)) }
        let side = column.width
        var joined: [(start: Int, end: Int)] = []
        for run in runs {
            if let last = joined.last, run.end - last.start + 1 <= Int(Double(side) * 1.15) {
                joined[joined.count - 1].end = run.end
            } else {
                joined.append(run)
            }
        }
        var cells: [Box] = []
        for run in joined {
            let height = run.end - run.start + 1
            let parts = max(1, Int((Double(height) / Double(side)).rounded()))
            for part in 0..<parts {
                cells.append(Box(minX: column.minX, minY: run.start + height * part / parts,
                                 maxX: column.maxX, maxY: run.start + height * (part + 1) / parts - 1))
            }
        }
        return cells
    }

    /// Bande horizontale, agrandie deux fois. Un trait étroit et haut est un « ー » écrit à la verticale : couché, sinon il se
    /// lit comme un 1.
    static func strip(_ cells: [Box], column: Box, bitmap: Bitmap) -> CGImage? {
        let zoom = 2
        let cellSide = max(column.width, cells.map(\.height).max() ?? column.width, 20) * zoom + 8
        let margin = stripMargin
        let width = cellSide * cells.count + margin * 2, height = cellSide + margin * 2
        var output = [UInt8](repeating: 255, count: width * height)
        for (index, cell) in cells.enumerated() {
            let ink = inkBounds(of: cell, in: bitmap)
            let lying = Double(ink.height) >= Double(ink.width) * 2.5 && Double(ink.height) >= Double(column.width) * 0.5
            let (drawnWidth, drawnHeight) = lying ? (ink.height, ink.width) : (ink.width, ink.height)
            let originX = margin + index * cellSide + (cellSide - drawnWidth * zoom) / 2
            let originY = margin + (cellSide - drawnHeight * zoom) / 2
            for y in 0..<(drawnHeight * zoom) {
                for x in 0..<(drawnWidth * zoom) {
                    let sourceX = lying ? ink.minX + (y / zoom) : ink.minX + (x / zoom)
                    let sourceY = lying ? ink.maxY - (x / zoom) : ink.minY + (y / zoom)
                    output[(originY + y) * width + originX + x] = bitmap.pixels[sourceY * bitmap.width + sourceX]
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(output) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Le trait réel dans sa case : la largeur de la colonne, elle, vient du caractère le plus large.
    private static func inkBounds(of cell: Box, in bitmap: Bitmap) -> Box {
        var result: Box?
        for y in cell.minY...max(cell.minY, cell.maxY) {
            for x in cell.minX...cell.maxX where bitmap.isInk(x, y) {
                let point = Box(minX: x, minY: y, maxX: x, maxY: y)
                if result == nil { result = point } else { result?.formUnion(point) }
            }
        }
        return result ?? cell
    }

    // MARK: Outils

    private static func grayBitmap(_ image: CGImage, width: Int, height: Int) -> Bitmap? {
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Bitmap(width: width, height: height, pixels: pixels) : nil
    }

    private static func normalized(_ box: Box, in bitmap: Bitmap) -> NormBox {
        NormBox(x: Double(box.minX) / Double(bitmap.width), y: Double(box.minY) / Double(bitmap.height),
                w: Double(box.width) / Double(bitmap.width), h: Double(box.height) / Double(bitmap.height))
    }

    /// Part de `a` couverte par `b`.
    private static func overlapShare(_ a: NormBox, _ b: NormBox) -> Double {
        let width = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
        let height = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
        guard width > 0, height > 0, a.w > 0, a.h > 0 else { return 0 }
        return width * height / (a.w * a.h)
    }
}
