// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import PDFKit
import ReaderCore
import UIKit

/// Un pas annulable : surlignages retirés puis ajoutés (une fusion fait les deux).
struct HighlightChange {
    var removed: [Highlight]
    var added: [Highlight]
}

/// Glisser en cours du mode « Surligner l'OCR » : tout ce qu'il faut pour suivre le pointeur sans rien attendre.
struct OCRHighlightDrag {
    let page: PDFPage
    let source: Int
    let ocr: OCRPage
    let frame: PageFrame
    let tolerance: Double
    let anchor: (line: Int, index: Int)
    var last: (line: Int, index: Int)
}

/// Surligner en glissant sur les zones invisibles de l'OCR (RET-020, #23) : à l'appui, le caractère sous le pointeur ;
/// au relâchement, le dernier caractère survolé ; le surlignage couvre tout entre les deux, ligne par ligne
/// (`OCRRangeSelection`). Même enregistrement que le surlignage d'une sélection (`Highlight`, repère de la page) :
/// il s'affiche, se supprime et s'exporte pareil. Une seule page par glisser ; une page sans OCR ne fait rien.
extension ReaderController {
    func setOCRHighlightMode(_ on: Bool) {
        ocrHighlightMode = on
        ocrHighlightDrag = nil
        ocrHighlightPreview = []
        if !on { ocrHighlightErasing = false }
        if on {
            if isDrawing { setDrawing(false) }
            endLookup()
            pdfView.clearSelection()
            // OCR des pages affichées, pour que le premier glisser trouve déjà ses zones.
            ensureOCR(shownSources)
        }
    }

    func ocrHighlightBegan(at point: CGPoint) async {
        ocrHighlightDrag = nil
        if ocrHighlightErasing { erase(at: point); return }
        let generation = ocrHighlightGeneration
        guard let pdf, let page = pdfView.page(for: point, nearest: false) else { return }
        let index = pdf.index(for: page)
        guard presented.indices.contains(index) else { return }
        let source = presented[index].source
        guard let box = originalBoxes[source], let frame = pageFrame(ofSource: source) else { return }
        var ocr = await realOCR(source: source)
        if ocr == nil { ocr = source == focusSource ? ocrPage : nil }
        if ocr == nil { ocr = await cachedOCR(source: source) }
        guard let ocr else {
            ensureOCR([source])
            Diagnostics.log("surligner OCR : page \(source + 1) pas encore lue, lecture lancée", "lecteur")
            return
        }
        // Même marge qu'un survol au curseur (≈ 4 pt), en fraction de la page affichée.
        let shownWidth = frame.rotation % 180 == 0 ? box.width : box.height
        let tolerance = Double(6 / max(shownWidth * pdfView.scaleFactor, 1))
        guard generation == ocrHighlightGeneration,   // déjà relâché pendant la lecture de l'OCR
              let hit = ocr.character(at: frame.normalized(pdfView.convert(point, to: page)), tolerance: tolerance) else { return }
        ocrHighlightDrag = OCRHighlightDrag(page: page, source: source, ocr: ocr, frame: frame, tolerance: tolerance,
                                            anchor: hit, last: hit)
        updateOCRHighlightPreview()
    }

    func ocrHighlightMoved(to point: CGPoint) {
        if ocrHighlightErasing { erase(at: point); return }
        guard var drag = ocrHighlightDrag else { return }
        // Hors de la page de départ : on garde le dernier caractère survolé.
        guard pdfView.page(for: point, nearest: false) == drag.page,
              let hit = drag.ocr.character(at: drag.frame.normalized(pdfView.convert(point, to: drag.page)),
                                           tolerance: drag.tolerance),
              hit != drag.last else { return }
        drag.last = hit
        ocrHighlightDrag = drag
        updateOCRHighlightPreview()
    }

    func ocrHighlightEnded(color: HighlightColor) {
        ocrHighlightGeneration += 1
        defer {
            ocrHighlightDrag = nil
            ocrHighlightPreview = []
        }
        guard let drag = ocrHighlightDrag else { return }
        let segments = OCRRangeSelection.segments(in: drag.ocr, from: drag.anchor, to: drag.last)
        let rects = OCRRangeSelection.boxes(in: drag.ocr, segments).map(drag.frame.pageRect)
        guard !rects.isEmpty else { return }
        let fresh = rects.map { PageRect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) }
        // Pas de couches (recette 62, L5) : les surlignages recouverts sont absorbés, les rectangles fusionnés.
        let covered = HighlightLayers.covered(by: fresh, among: highlights, page: drag.source)
        let text = OCRRangeSelection.text(in: drag.ocr, segments)
        let texts = covered.map(\.text).filter { !$0.isEmpty && !text.contains($0) } + [text]
        let highlight = Highlight(documentId: document.id, pageIndex: drag.source,
                                  rects: HighlightLayers.merged(covered.flatMap(\.rects) + fresh),
                                  color: color, text: texts.joined(separator: "\n"))
        apply(HighlightChange(removed: covered, added: [highlight]))
        Diagnostics.log("surligner OCR : p. \(drag.source + 1), \(highlight.text.count) caractère(s), \(covered.count) fusionné(s)", "lecteur")
    }

    /// Gomme : efface le surlignage sous le point (repère de la vue PDF).
    private func erase(at point: CGPoint) {
        guard let pdf, let page = pdfView.page(for: point, nearest: false) else { return }
        let index = pdf.index(for: page)
        guard presented.indices.contains(index) else { return }
        let p = pdfView.convert(point, to: page)
        guard let hit = HighlightLayers.hit(Double(p.x), Double(p.y), in: highlights, page: presented[index].source) else { return }
        apply(HighlightChange(removed: [hit], added: []))
        Diagnostics.log("surligner OCR : surlignage effacé p. \(presented[index].source + 1)", "lecteur")
    }

    /// Applique un pas (retraits puis ajouts) et le garde pour ⌘Z (30 pas au plus).
    private func apply(_ change: HighlightChange, record: Bool = true) {
        change.removed.forEach(deleteHighlight)
        for h in change.added {
            highlights.append(h)
            if let pdf { annotate(h, in: pdf) }
            model.persist { try $0.save(h) }
        }
        guard record else { return }
        highlightUndo.append(change)
        if highlightUndo.count > 30 { highlightUndo.removeFirst(highlightUndo.count - 30) }
    }

    /// ⌘Z : défait le dernier surlignage, fusion ou coup de gomme (les surlignages retirés reviennent tels quels).
    func undoHighlight() {
        guard let last = highlightUndo.popLast() else { return }
        apply(HighlightChange(removed: last.added, added: last.removed), record: false)
        Diagnostics.log("surligner OCR : annulation", "lecteur")
    }

    private func updateOCRHighlightPreview() {
        guard let drag = ocrHighlightDrag else { ocrHighlightPreview = []; return }
        let segments = OCRRangeSelection.segments(in: drag.ocr, from: drag.anchor, to: drag.last)
        ocrHighlightPreview = OCRRangeSelection.boxes(in: drag.ocr, segments)
            .map { pdfView.convert(drag.frame.pageRect($0), from: drag.page) }
    }
}
