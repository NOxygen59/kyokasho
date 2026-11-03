// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation

// MARK: - Zones de tap

public enum TapAction: Equatable, Sendable {
    case previous, next, toggleBars
}

public enum TapZones {
    /// Action d'un tap à la position horizontale `x` (0 = bord gauche, 1 = bord droit).
    /// Tiers gauche / tiers droit = tourner la page, centre = afficher ou masquer les barres.
    /// En lecture de droite à gauche, le côté gauche avance (comme un livre japonais).
    public static func action(atFraction x: Double, settings: ReaderSettings) -> TapAction {
        guard settings.tapZonesEnabled else { return .toggleBars }
        let side: TapAction
        if x < 1.0 / 3.0 {
            side = .previous
        } else if x > 2.0 / 3.0 {
            side = .next
        } else {
            return .toggleBars
        }
        var forward = side == .next
        if settings.direction == .rightToLeft { forward.toggle() }
        if settings.invertTapZones { forward.toggle() }
        return forward ? .next : .previous
    }
}

// MARK: - Pages présentées (découpe des scans de double page)

/// Une page telle qu'affichée : une page source entière, ou l'une de ses deux moitiés.
public struct PresentedPage: Equatable, Hashable, Sendable {
    public enum Part: Int, Codable, Sendable { case whole, left, right }
    public var source: Int
    public var part: Part

    public init(source: Int, part: Part) {
        self.source = source
        self.part = part
    }
}

public enum PresentationLayout {
    /// Liste des pages à afficher, dans l'ordre de lecture du document.
    /// - Parameters:
    ///   - pageCount: nombre de pages du PDF.
    ///   - splitPages: pages sources à couper en deux.
    ///   - rightToLeft: en lecture droite → gauche, la moitié droite d'un scan se lit en premier.
    public static func pages(pageCount: Int, splitPages: Set<Int>, rightToLeft: Bool) -> [PresentedPage] {
        var result: [PresentedPage] = []
        result.reserveCapacity(pageCount + splitPages.count)
        for index in 0..<pageCount {
            if splitPages.contains(index) {
                if rightToLeft {
                    result.append(PresentedPage(source: index, part: .right))
                    result.append(PresentedPage(source: index, part: .left))
                } else {
                    result.append(PresentedPage(source: index, part: .left))
                    result.append(PresentedPage(source: index, part: .right))
                }
            } else {
                result.append(PresentedPage(source: index, part: .whole))
            }
        }
        return result
    }

    /// Première page présentée qui correspond à la page source `source` (reprise de lecture).
    public static func presentedIndex(ofSource source: Int, in pages: [PresentedPage]) -> Int {
        pages.firstIndex { $0.source >= source } ?? max(0, pages.count - 1)
    }

    /// Rectangle visible d'une moitié dans la boîte de la page (coordonnées PDF, y vers le haut).
    /// `rotation` : sens d'affichage de la page. « Gauche » et « droite » sont ceux de l'écran : sur une page tournée,
    /// ils correspondent à d'autres côtés de la boîte (même convention que `PageGeometry.pageToView`).
    public static func box(for part: PresentedPage.Part, in box: CGRect, rotation: Int = 0) -> CGRect {
        guard part != .whole else { return box }
        let lowHalf: Bool
        let splitsHeight: Bool
        switch ((rotation % 360) + 360) % 360 {
        case 90: lowHalf = part == .left; splitsHeight = true
        case 180: lowHalf = part == .right; splitsHeight = false
        case 270: lowHalf = part == .right; splitsHeight = true
        default: lowHalf = part == .left; splitsHeight = false
        }
        if splitsHeight {
            return CGRect(x: box.minX, y: lowHalf ? box.minY : box.midY, width: box.width, height: box.height / 2)
        }
        return CGRect(x: lowHalf ? box.minX : box.midX, y: box.minY, width: box.width / 2, height: box.height)
    }

    /// Ordre des pages pour afficher une double page de droite à gauche **sans** l'option RTL de
    /// PDFKit (qui intervertit les tailles des deux pages quand elles diffèrent) : dans chaque paire,
    /// la page lue en second passe à gauche. `order[k]` = position de lecture affichée en k-ième.
    public static func rightToLeftSpreadOrder(count: Int, firstPageAlone: Bool) -> [Int] {
        var order = Array(0..<max(0, count))
        var i = firstPageAlone ? 1 : 0
        while i + 1 < count {
            order.swapAt(i, i + 1)
            i += 2
        }
        return order
    }

    /// Une page est « large » (probable scan de double page) si sa largeur dépasse sa hauteur de 15 %.
    public static func isWide(_ size: CGSize) -> Bool {
        size.height > 0 && size.width / size.height > 1.15
    }
}

// MARK: - Rognage automatique

public enum ContentBounds {
    /// Cherche le rectangle du contenu (pixels plus sombres que le fond) dans une image en niveaux
    /// de gris, et renvoie des fractions (origine en haut à gauche) avec une petite marge.
    /// - Parameters:
    ///   - pixels: niveaux de gris 0 (noir) … 255 (blanc), ligne par ligne.
    ///   - bytesPerRow: octets par ligne (≥ width).
    ///   - threshold: écart au fond à partir duquel un pixel compte comme contenu.
    ///   - minInkPerLine: nombre de pixels de contenu nécessaires pour qu'une ligne/colonne compte
    ///     (ignore poussières et taches isolées des scans).
    /// - Returns: `nil` si la page est vide.
    public static func detect(pixels: UnsafeBufferPointer<UInt8>, width: Int, height: Int, bytesPerRow: Int,
                              threshold: UInt8 = 40, minInkPerLine: Int = 2, padding: Double = 0.01) -> NormalizedRect? {
        guard width > 0, height > 0, pixels.count >= bytesPerRow * height else { return nil }
        // Fond = valeur la plus claire des quatre coins (pages blanches ou crème).
        let corners = [pixels[0], pixels[width - 1], pixels[(height - 1) * bytesPerRow], pixels[(height - 1) * bytesPerRow + width - 1]]
        let background = Int(corners.max() ?? 255)
        let limit = max(0, background - Int(threshold))

        var columnInk = [Int](repeating: 0, count: width)
        var rowInk = [Int](repeating: 0, count: height)
        for y in 0..<height {
            let row = y * bytesPerRow
            var count = 0
            for x in 0..<width where Int(pixels[row + x]) < limit {
                count += 1
                columnInk[x] += 1
            }
            rowInk[y] = count
        }
        guard let top = rowInk.firstIndex(where: { $0 >= minInkPerLine }),
              let bottom = rowInk.lastIndex(where: { $0 >= minInkPerLine }),
              let left = columnInk.firstIndex(where: { $0 >= minInkPerLine }),
              let right = columnInk.lastIndex(where: { $0 >= minInkPerLine }) else {
            return nil
        }
        let x0 = max(0, Double(left) / Double(width) - padding)
        let y0 = max(0, Double(top) / Double(height) - padding)
        let x1 = min(1, Double(right + 1) / Double(width) + padding)
        let y1 = min(1, Double(bottom + 1) / Double(height) + padding)
        return NormalizedRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Applique un rognage (fractions, origine en haut) à une boîte PDF (origine en bas).
    /// Ne rogne pas si le résultat serait minuscule (page presque vide).
    public static func apply(_ crop: NormalizedRect, to box: CGRect) -> CGRect {
        guard crop.width > 0.2, crop.height > 0.2 else { return box }
        return CGRect(x: box.minX + crop.x * box.width,
                      y: box.minY + (1 - crop.y - crop.height) * box.height,
                      width: crop.width * box.width,
                      height: crop.height * box.height)
    }
}

// MARK: - Géométrie de page

public enum PageGeometry {
    /// Transformation du repère de page PDF (points, y vers le haut) vers le repère d'une vue
    /// (y vers le bas, origine en haut à gauche de la boîte visible), rotation comprise.
    /// Les dessins sont stockés dans le repère PDF : ils restent justes si on change le rognage,
    /// la découpe ou la rotation.
    public static func pageToView(box: CGRect, rotation: Int) -> CGAffineTransform {
        let r = ((rotation % 360) + 360) % 360
        // 1. origine au coin bas-gauche de la boîte
        var t = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        // 2. rotation (sens horaire à l'écran, comme PDFKit) puis remise en positif
        switch r {
        case 90:
            t = t.concatenating(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: box.width))
        case 180:
            t = t.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: box.width, ty: box.height))
        case 270:
            t = t.concatenating(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: box.height, ty: 0))
        default:
            break
        }
        // 3. y vers le bas
        let rotatedHeight = (r == 90 || r == 270) ? box.width : box.height
        return t.concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rotatedHeight))
    }
}

// MARK: - Export Markdown

public enum MarkdownExporter {
    /// Commentaires (et surlignages) d'un document en Markdown, page par page.
    public static func export(title: String, comments: [PageComment], highlights: [Highlight] = [],
                              bookmarks: [Bookmark] = [], date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        var out = "# \(title)\n\n_Notes exportées le \(formatter.string(from: date))._\n"
        let pages = Set(comments.map(\.pageIndex)).union(highlights.map(\.pageIndex)).union(bookmarks.map(\.pageIndex)).sorted()
        if pages.isEmpty {
            return out + "\nAucune note.\n"
        }
        for page in pages {
            out += "\n## Page \(page + 1)\n"
            for bookmark in bookmarks where bookmark.pageIndex == page {
                out += "\n🔖 \(bookmark.title)\n"
            }
            let pageHighlights = highlights.filter { $0.pageIndex == page && !$0.text.isEmpty }
            if !pageHighlights.isEmpty {
                out += "\n"
                for h in pageHighlights {
                    out += "> \(h.text.replacingOccurrences(of: "\n", with: " "))\n>\n"
                }
                out.removeLast(2)
            }
            for comment in comments.filter({ $0.pageIndex == page }).sorted(by: { $0.createdAt < $1.createdAt }) {
                out += "\n\(comment.body.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            }
        }
        return out
    }
}
