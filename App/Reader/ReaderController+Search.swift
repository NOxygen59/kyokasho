// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import GLMOCRKit
import OCRKit
import PDFKit
import PencilKit
import ReaderCore
import UIKit

/// `ReaderController` : recherche, image de la page pour l'IA.
extension ReaderController {
    // MARK: Recherche

    static let maxSearchResults = 500

    func enqueue(_ result: SearchResult) {
        guard searchResults.count + pendingResults.count < Self.maxSearchResults else { return }
        pendingResults.append(result)
        if searchResults.count + pendingResults.count >= Self.maxSearchResults {
            pdf?.cancelFindString()
            isSearching = false
            flushResults()
            return
        }
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.flushResults() }
    }

    func flushResults() {
        flushScheduled = false
        guard !pendingResults.isEmpty else { return }
        // Une page trouvée dans le texte du PDF n'a pas besoin du résultat OCR en plus.
        let pdfPages = Set((searchResults + pendingResults).filter { !$0.fromOCR }.map(\.sourcePage))
        searchResults.removeAll { $0.fromOCR && pdfPages.contains($0.sourcePage) }
        pendingResults.removeAll { $0.fromOCR && pdfPages.contains($0.sourcePage) }
        // Tri par page de lecture (l'ordre interne peut différer en droite → gauche), stable.
        let all = (searchResults + pendingResults).enumerated()
            .sorted { $0.element.sourcePage != $1.element.sourcePage ? $0.element.sourcePage < $1.element.sourcePage : $0.offset < $1.offset }
            .map(\.element)
        pendingResults = []
        searchResults = all
    }

    func search(_ query: String) {
        guard let pdf else { return }
        pdf.cancelFindString()
        searchResults = []
        pendingResults = []
        searchToken += 1
        let token = searchToken
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSearching = false
            pdfView.highlightedSelections = nil
            return
        }
        isSearching = true
        pdf.beginFindString(trimmed, withOptions: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
        // Pages scannées : recherche aussi dans le texte OCR en cache.
        let documentId = document.id
        let engines = [OCREngineID.glmocr, OCREngineID.ndlocr, OCREngineID.ppocr5, OCREngineID.vision]
        let service = model.ocr
        Task { [weak self] in
            let hits = await service.search(trimmed, documentId: documentId, engines: engines)
            guard let self, token == self.searchToken else { return }
            let pdfPages = Set((self.searchResults + self.pendingResults).filter { !$0.fromOCR }.map(\.sourcePage))
            for hit in hits where !pdfPages.contains(hit.page) {
                let index = PresentationLayout.presentedIndex(ofSource: hit.page, in: self.presented)
                self.enqueue(SearchResult(selection: nil, presentedIndex: index, sourcePage: hit.page,
                                          context: "📷 " + hit.context.replacingOccurrences(of: "\n", with: " ")))
            }
            self.flushResults()
        }
    }

    /// Lit (OCR) toutes les pages qui n'ont pas encore de texte, en tâche de fond.
    func ocrWholeDocument() {
        guard documentOCRTask == nil, !document.isComic else { return }
        let url = fileURL
        let documentId = document.id
        let count = document.pageCount
        let choice = settings.ocrEngine
        let service = model.ocr
        documentOCRProgress = (0, count)
        documentOCRTask = Task { [weak self] in
            for page in 0..<count {
                if Task.isCancelled { break }
                let engine = await Task.detached(priority: .utility) {
                    OCRService.resolve(choice, url: url, pageIndex: page)
                }.value
                _ = try? await service.page(documentId: documentId, url: url, pageIndex: page, engine: engine)
                await MainActor.run { self?.documentOCRProgress = (page + 1, count) }
            }
            await MainActor.run {
                self?.documentOCRProgress = nil
                self?.documentOCRTask = nil
                self?.schedulePageSettled()
            }
        }
    }

    func cancelWholeDocumentOCR() {
        documentOCRTask?.cancel()
    }

    func show(_ result: SearchResult) {
        guard let selection = result.selection else {
            go(toSource: result.sourcePage)
            return
        }
        pdfView.go(to: selection)
        selection.color = UIColor.systemOrange.withAlphaComponent(0.6)
        pdfView.highlightedSelections = [selection]
    }

    // MARK: Image de la page (pour l'IA)

    /// Pages données (sources) en une image : côte à côte dans l'ordre affiché (double page « les deux »).
    func renderSources(_ sources: [Int], maxWidth: CGFloat = 2048) -> UIImage? {
        guard let pdf else { return nil }
        let pages: [PDFPage] = presented.indices.filter { sources.contains(presented[$0].source) }.compactMap { pdf.page(at: $0) }
        guard !pages.isEmpty else { return nil }
        let sizes = pages.map { page -> CGSize in
            let box = page.bounds(for: .cropBox)
            return page.rotation % 180 != 0 ? CGSize(width: box.height, height: box.width) : box.size
        }
        let height = sizes.map(\.height).max() ?? 1
        let totalWidth = sizes.reduce(0) { $0 + $1.width * height / max($1.height, 1) }
        let scale = maxWidth / max(totalWidth, 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: totalWidth * scale, height: height * scale), format: format).image { _ in
            var x: CGFloat = 0
            for (page, size) in zip(pages, sizes) {
                let w = size.width * height / max(size.height, 1) * scale
                let h = height * scale
                page.thumbnail(of: CGSize(width: w, height: h), for: .cropBox).draw(in: CGRect(x: x, y: 0, width: w, height: h))
                x += w
            }
        }
    }
}
