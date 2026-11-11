// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import GLMOCRKit
import OCRKit
import PDFKit
import PencilKit
import ReaderCore
import UIKit

/// `ReaderController` : notes, surlignages, signets.
extension ReaderController {
    // MARK: Notes (fenêtre flottante, ancres)

    /// Nouvelle note sur la page de travail, ouverte tout de suite dans la fenêtre flottante.
    func newNote() {
        let note = PageComment(documentId: document.id, pageIndex: focusSource, body: "")
        notes.append(note)
        model.persist { try $0.save(note) }
        openNote = note
    }

    /// Enregistre une note modifiée (texte, dessin ou ancre) et met son ancre à jour sur la page.
    func saveNote(_ note: PageComment) {
        var note = note
        note.updatedAt = Date()
        let old = notes.first { $0.id == note.id }
        if let i = notes.firstIndex(where: { $0.id == note.id }) { notes[i] = note } else { notes.append(note) }
        if openNote?.id == note.id { openNote = note }
        model.persist { try $0.save(note) }
        // Pastille refaite seulement si l'ancre a bougé (pas à chaque mot tapé).
        if let pdf, old?.anchorRect != note.anchorRect || old?.pageIndex != note.pageIndex {
            if let old { removeAnchor(old, in: pdf) }
            annotateAnchor(note, in: pdf)
        }
    }

    func deleteNote(_ note: PageComment) {
        notes.removeAll { $0.id == note.id }
        if openNote?.id == note.id { openNote = nil }
        if placingAnchorFor?.id == note.id { placingAnchorFor = nil }
        if let pdf { removeAnchor(note, in: pdf) }
        model.persist { try $0.deleteComment(id: note.id) }
    }

    /// Notes rechargées (ajoutées depuis le panneau d'étude).
    func placeAnchor(for note: PageComment, at point: CGPoint) {
        guard let pdf, let page = pdfView.page(for: point, nearest: false) else { return }
        let index = pdf.index(for: page)
        guard presented.indices.contains(index) else { return }
        let pagePoint = pdfView.convert(point, to: page)
        guard var note = notes.first(where: { $0.id == note.id }) else { return }
        // Mot sous le doigt (texte du PDF), sinon un petit carré autour du point.
        let word = page.selectionForWord(at: pagePoint)
        let text = word?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rect: CGRect
        if let bounds = word?.bounds(for: page), !text.isEmpty, bounds.width < 400, bounds.height < 200 {
            rect = bounds
        } else {
            rect = CGRect(x: pagePoint.x - 10, y: pagePoint.y - 10, width: 20, height: 20)
        }
        note.pageIndex = presented[index].source
        note.anchorRect = PageRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        note.anchorText = text.isEmpty ? nil : String(text.prefix(30))
        saveNote(note)
    }

    /// Va à l'ancre de la note et fait clignoter le mot ancré 1,5 s.
    func goToAnchor(_ note: PageComment) {
        guard let rect = note.anchorRect else { go(toSource: note.pageIndex); return }
        go(toSource: note.pageIndex)
        guard let pdf else { return }
        let bounds = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height).insetBy(dx: -3, dy: -3)
        var added: [(PDFPage, PDFAnnotation)] = []
        for page in pages(forSource: note.pageIndex, in: pdf) where page.bounds(for: .cropBox).intersects(bounds) {
            let flash = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            flash.color = UIColor.systemYellow.withAlphaComponent(0.6)
            flash.userName = "flash"
            page.addAnnotation(flash)
            added.append((page, flash))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for (page, flash) in added { page.removeAnnotation(flash) }
        }
    }

    func annotateAnchor(_ note: PageComment, in pdf: PDFDocument) {
        guard let rect = note.anchorRect else { return }
        let size: CGFloat = max(14, min(26, rect.height * 0.8))
        // Pastille « ＊ » au coin haut-droit du mot.
        let badge = CGRect(x: rect.x + rect.width - size * 0.3, y: rect.y + rect.height - size * 0.5, width: size, height: size)
        for page in pages(forSource: note.pageIndex, in: pdf) where page.bounds(for: .cropBox).intersects(badge) {
            let annotation = NoteAnchorAnnotation(bounds: badge, forType: .stamp, withProperties: nil)
            annotation.userName = "note:" + note.id
            page.addAnnotation(annotation)
        }
    }

    func removeAnchor(_ note: PageComment, in pdf: PDFDocument) {
        for page in pages(forSource: note.pageIndex, in: pdf) {
            for annotation in page.annotations where annotation.userName == "note:" + note.id { page.removeAnnotation(annotation) }
        }
    }

    // MARK: Surlignages

    func addHighlightAnnotations(to pdf: PDFDocument) {
        for highlight in highlights { annotate(highlight, in: pdf) }
    }

    func pages(forSource source: Int, in pdf: PDFDocument) -> [PDFPage] {
        presented.enumerated().compactMap { index, p in p.source == source ? pdf.page(at: index) : nil }
    }

    func annotate(_ highlight: Highlight, in pdf: PDFDocument) {
        for page in pages(forSource: highlight.pageIndex, in: pdf) {
            for rect in highlight.rects {
                let annotation = PDFAnnotation(bounds: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
                                               forType: .highlight, withProperties: nil)
                annotation.color = highlight.color.uiColor.withAlphaComponent(0.45)
                annotation.userName = "hl:" + highlight.id
                page.addAnnotation(annotation)
            }
        }
    }

    func highlightSelection(color: HighlightColor) {
        guard let pdf, let selection = pdfView.currentSelection else { return }
        var bySource: [Int: (rects: [PageRect], text: [String])] = [:]
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let index = pdf.index(for: page)
                guard presented.indices.contains(index) else { continue }
                let source = presented[index].source
                let r = line.bounds(for: page)
                guard r.width > 0, r.height > 0 else { continue }
                bySource[source, default: ([], [])].rects.append(PageRect(x: r.minX, y: r.minY, width: r.width, height: r.height))
                if let text = line.string { bySource[source, default: ([], [])].text.append(text) }
            }
        }
        for (source, value) in bySource {
            let highlight = Highlight(documentId: document.id, pageIndex: source, rects: value.rects, color: color,
                                      text: value.text.joined(separator: "\n"))
            highlights.append(highlight)
            annotate(highlight, in: pdf)
            model.persist { try $0.save(highlight) }
        }
        pdfView.clearSelection()
    }

    func deleteHighlight(_ highlight: Highlight) {
        highlights.removeAll { $0.id == highlight.id }
        if let pdf {
            for page in pages(forSource: highlight.pageIndex, in: pdf) {
                for annotation in page.annotations where annotation.userName == "hl:" + highlight.id {
                    page.removeAnnotation(annotation)
                }
            }
        }
        model.persist { try $0.deleteHighlight(id: highlight.id) }
    }

    var allHighlights: [Highlight] { highlights }

    // MARK: Signets

    func toggleBookmark() {
        let page = currentSourcePage
        if let existing = bookmarks.first(where: { $0.pageIndex == page }) {
            bookmarks.removeAll { $0.id == existing.id }
            model.persist { try $0.deleteBookmark(id: existing.id) }
        } else {
            let bookmark = Bookmark(documentId: document.id, pageIndex: page, title: String(localized: "Page \(document.pageLabel(page))"))
            bookmarks.append(bookmark)
            bookmarks.sort { $0.pageIndex < $1.pageIndex }
            model.persist { try $0.save(bookmark) }
        }
    }

    func rename(_ bookmark: Bookmark, to title: String) {
        guard let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[i].title = title
        let updated = bookmarks[i]
        model.persist { try $0.save(updated) }
    }

    func delete(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        model.persist { try $0.deleteBookmark(id: bookmark.id) }
    }
}
