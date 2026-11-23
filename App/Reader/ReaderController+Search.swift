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

    /// Moteurs fouillés par la recherche, dans son ordre de préférence (repris par le surlignage bref).
    static let searchEngines = [OCREngineID.glmocr, OCREngineID.ndlocr, OCREngineID.ppocr5, OCREngineID.vision]

    func search(_ query: String) {
        guard document.capabilities.textAnalysis, let pdf else { return }
        pdf.cancelFindString()
        searchResults = []
        pendingResults = []
        searchToken += 1
        let token = searchToken
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lastSearchQuery = trimmed
        guard !trimmed.isEmpty else {
            ocrSearchRunning = false
            isSearching = false
            pdfView.highlightedSelections = nil
            return
        }
        isSearching = true
        // Armé avant PDFKit : sa fin de recherche ne doit pas afficher « Aucun résultat » avant la recherche OCR.
        ocrSearchRunning = true
        pdf.beginFindString(trimmed, withOptions: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
        // Pages scannées : recherche aussi dans le texte OCR en cache, puis dans le texte des lectures IA (OvisOCR2, ou
        // ta correction) des pages sans résultat OCR. Hors du fil principal ; « Recherche… » reste affiché jusqu'au bout
        // (recette 1.6.4, point 11 : la carte disait « Aucun résultat » avant la fin de la recherche OCR).
        let documentId = document.id
        let engines = Self.searchEngines
        let service = model.ocr
        let pageCount = document.pageCount
        Task { [weak self] in
            let hits = await Task.detached(priority: .userInitiated) { () -> [(page: Int, context: String, ai: Bool)] in
                let ocr = service.search(trimmed, documentId: documentId, engines: engines)
                let found = Set(ocr.map(\.page))
                let ai = Self.aiTextHits(trimmed, documentId: documentId, pageCount: pageCount, skipping: found)
                return ocr.map { ($0.page, $0.context, false) } + ai.map { ($0.page, $0.context, true) }
            }.value
            guard let self, token == self.searchToken else { return }
            self.ocrSearchRunning = false
            let pdfPages = Set((self.searchResults + self.pendingResults).filter { !$0.fromOCR }.map(\.sourcePage))
            for hit in hits where !pdfPages.contains(hit.page) {
                let index = PresentationLayout.presentedIndex(ofSource: hit.page, in: self.presented)
                self.enqueue(SearchResult(selection: nil, presentedIndex: index, sourcePage: hit.page,
                                          context: (hit.ai ? "✦ " : "📷 ") + hit.context.replacingOccurrences(of: "\n", with: " ")))
            }
            self.isSearching = self.pdf?.isFinding ?? false
            self.flushResults()
        }
    }

    /// Pages dont la lecture IA (OvisOCR2, ou la correction de l'utilisateur, qui passe d'abord) contient `query`, avec un
    /// extrait, sauf `skipping` (déjà trouvées dans l'OCR). Mêmes règles de comparaison que la recherche OCR.
    nonisolated static func aiTextHits(_ query: String, documentId: String, pageCount: Int,
                                       skipping: Set<Int>) -> [(page: Int, context: String)] {
        // Seulement les pages qui ont une lecture IA ou une correction (un seul parcours du dossier, pas une ouverture
        // de fichier par page).
        let folder = DocumentAITextStore.folder.appendingPathComponent(documentId, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let readers = [ModelSpec.ovisocr2.id, DocumentAITextStore.correctedReader]
        let pages = Set(names.compactMap { name -> Int? in
            guard name.hasSuffix(".md"), let dash = name.lastIndex(of: "-"),
                  readers.contains(String(name[..<dash])) else { return nil }
            return Int(name[name.index(after: dash)...].dropLast(3))
        })
        var results: [(Int, String)] = []
        for page in pages.sorted() where page < pageCount && !skipping.contains(page) {
            guard let text = DocumentAITextStore.read(documentId: documentId, reader: ModelSpec.ovisocr2.id, page: page),
                  let range = text.range(of: query, options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive])
            else { continue }
            let start = text.index(range.lowerBound, offsetBy: -15, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: 25, limitedBy: text.endIndex) ?? text.endIndex
            results.append((page, String(text[start..<end])))
        }
        return results
    }

    /// Lit (OCR) toutes les pages qui n'ont pas encore de texte, en tâche de fond.
    func ocrWholeDocument() {
        guard documentOCRTask == nil, document.capabilities.textAnalysis else { return }
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
                // G2 : lecteur fermé ou lecture annulée, rien à relancer.
                guard !Task.isCancelled, self?.closed == false else { return }
                self?.schedulePageSettled()
            }
        }
    }

    func cancelWholeDocumentOCR() {
        documentOCRTask?.cancel()
    }

    /// Durée du surlignage du mot touché dans les résultats (idée de la recette 1.6.2, version 1.6.4).
    static let searchFlashDuration: UInt64 = 2_000_000_000

    func show(_ result: SearchResult) {
        clearSearchFlash()
        guard let selection = result.selection else {
            go(toSource: result.sourcePage)
            flashOCRMatch(source: result.sourcePage, query: lastSearchQuery)
            return
        }
        pdfView.go(to: selection)
        selection.color = UIColor.systemOrange.withAlphaComponent(0.6)
        pdfView.highlightedSelections = [selection]
        searchFlashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.searchFlashDuration)
            guard !Task.isCancelled else { return }
            self?.clearSearchFlash()
        }
    }

    /// Page scannée : le mot est retrouvé dans l'OCR en cache et surligné par une annotation **temporaire** (dans le
    /// repère de la page, elle suit le zoom et le défilement), retirée après 2 s, au résultat suivant ou à la fermeture.
    /// Rien n'est enregistré : ni dans les surlignages de l'utilisateur, ni dans le fichier.
    /// Contre-revues Codex : moteurs essayés **dans l'ordre de la recherche** (`OCRService.search` garde le premier qui
    /// a la page : même texte, même première occurrence que l'extrait) ; lecture du cache par le service, **sans** tenir
    /// le lecteur ; page coupée : chaque morceau va sur la moitié qu'il touche ; jamais de déplacement de la vue.
    private func flashOCRMatch(source: Int, query: String) {
        guard !query.isEmpty else { return }
        let service = model.ocr, documentId = document.id
        let engines = Self.searchEngines
        searchFlashTask = Task { @MainActor [weak self] in
            var groups: [[NormBox]] = []
            for engine in engines {
                guard !Task.isCancelled else { return }
                if let page = await service.cached(documentId: documentId, pageIndex: source, engine: engine) {
                    // Premier moteur qui a la page, comme la recherche : on s'arrête là, trouvé ou non.
                    groups = page.matchBoxes(of: query)
                    break
                }
            }
            guard !Task.isCancelled, !groups.isEmpty, let self, let frame = self.pageFrame(ofSource: source),
                  let pdf = self.pdf else { return }
            let rects = groups.compactMap { group in
                group.map(frame.pageRect).reduce(CGRect?.none) { ($0 ?? $1).union($1) }?.insetBy(dx: -2, dy: -2)
            }
            let all = self.pages(forSource: source, in: pdf)
            // Chaque morceau sur la (les) moitié(s) qu'il touche ; toutes les pages de la source sinon.
            var placed: [(page: PDFPage, rect: CGRect)] = []
            for rect in rects {
                let touched = all.filter { $0.bounds(for: .cropBox).intersects(rect) }
                for page in touched.isEmpty ? all : touched { placed.append((page, rect)) }
            }
            for item in placed {
                let annotation = PDFAnnotation(bounds: item.rect, forType: .highlight, withProperties: nil)
                annotation.color = UIColor.systemOrange.withAlphaComponent(0.55)
                annotation.userName = "flash:recherche"
                item.page.addAnnotation(annotation)
                self.searchFlashAnnotations.append((item.page, annotation))
            }
            // Aucun saut ici (4e contre-revue Codex) : le changement de page arrive en différé, aucun repère ne
            // garantit qu'un saut tardif n'écraserait pas une navigation de l'utilisateur. Le résultat a déjà ouvert la
            // page ; limite connue : sur une page coupée, un mot de l'autre moitié n'est vu qu'en tournant la page.
            try? await Task.sleep(nanoseconds: Self.searchFlashDuration)
            guard !Task.isCancelled else { return }
            self.clearSearchFlash()
        }
    }

    /// Retire le surlignage bref (annotations temporaires et sélection orange) et annule son minuteur.
    func clearSearchFlash() {
        searchFlashTask?.cancel()
        searchFlashTask = nil
        for item in searchFlashAnnotations { item.page.removeAnnotation(item.annotation) }
        searchFlashAnnotations = []
        pdfView.highlightedSelections = nil
    }

    // MARK: Image de la page (pour l'IA)

    /// Pages données (sources) en une image : côte à côte dans l'ordre affiché (double page « les deux »).
    func renderSources(_ sources: [Int], maxWidth: CGFloat = 2048) -> UIImage? {
        // Contre-revue Codex : le surlignage bref ne doit pas partir dans l'image (Page vers IA, copie).
        clearSearchFlash()
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
