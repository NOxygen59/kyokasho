// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import GLMOCRKit
import OCRKit
import PDFKit
import PencilKit
import ReaderCore
import UIKit

/// `ReaderController` : rotation, découpe, rognage automatique.
extension ReaderController {
    // MARK: Rotation et découpe de la page courante

    func rotateCurrentPage() {
        let source = currentSourcePage
        var t = transforms[source] ?? PageTransform(documentId: document.id, pageIndex: source)
        t.rotation = (t.rotation + 90) % 360
        transforms[source] = t
        model.persist { try $0.save(t) }
        // Page entière, sans découpe automatique en jeu : on tourne sur place (pas de reconstruction).
        if !isBuilding, let pdf, !settings.splitWidePages, !splitSources.contains(source), let base = originalRotations[source] {
            for page in pages(forSource: source, in: pdf) { page.rotation = ((base + t.rotation) % 360 + 360) % 360 }
            pdfView.layoutDocumentView()
            if pdfView.isAtFit { pdfView.fitToPage() }
            return
        }
        rebuild(keepingSource: source)
    }

    func toggleSplitCurrentPage() {
        let source = currentSourcePage
        var t = transforms[source] ?? PageTransform(documentId: document.id, pageIndex: source)
        t.split.toggle()
        transforms[source] = t
        model.persist { try $0.save(t) }
        rebuild(keepingSource: source)
    }

    var isCurrentPageSplit: Bool { presented.indices.contains(currentIndex) && presented[currentIndex].part != .whole }

    // MARK: Rognage automatique (calculé en tâche de fond, mis en cache en base)

    func startAutoCropIfNeeded() {
        cropTask?.cancel()
        guard settings.autoCrop else { return }
        let missing = (0..<document.pageCount).filter { transforms[$0]?.autoCrop == nil }
        guard !missing.isEmpty else { return }
        // Ordre : page courante puis vers l'extérieur, pour que ce qu'on lit soit rogné d'abord.
        let start = currentSourcePage
        let ordered = missing.sorted { abs($0 - start) < abs($1 - start) }
        let url = fileURL
        let documentId = document.id
        cropTask = Task.detached(priority: .utility) { [weak self] in
            guard let cg = CGPDFDocument(url as CFURL) else { return }
            var batch: [Int: NormalizedRect] = [:]
            for (n, index) in ordered.enumerated() {
                if Task.isCancelled { return }
                if let crop = autoreleasepool(invoking: { Self.detectCrop(cg, pageIndex: index) }) {
                    batch[index] = crop
                }
                // Petits lots autour de la page lue (vite visibles), puis gros lots : chaque lot
                // relance la mise en page de tout le document.
                if batch.count >= (n < 8 ? 4 : 80) || n == ordered.count - 1 {
                    let ready = batch
                    batch.removeAll()
                    await self?.applyCrops(ready, documentId: documentId)
                }
            }
        }
    }

    nonisolated static func detectCrop(_ document: CGPDFDocument, pageIndex: Int) -> NormalizedRect? {
        guard let page = document.page(at: pageIndex + 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        let width = 160
        let height = max(1, Int((Double(width) * box.height / max(box.width, 1)).rounded()))
        var pixels = [UInt8](repeating: 255, count: width * height)
        let ok: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.interpolationQuality = .low
            ctx.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.drawPDFPage(page)
            return true
        }
        guard ok else { return nil }
        // Le contexte a l'origine en bas : les lignes du tampon vont du haut vers le bas, comme attendu.
        return pixels.withUnsafeBufferPointer {
            ContentBounds.detect(pixels: $0, width: width, height: height, bytesPerRow: width)
        } ?? NormalizedRect.full
    }

    func applyCrops(_ crops: [Int: NormalizedRect], documentId: String) {
        guard documentId == document.id, settings.autoCrop, let pdf else { return }
        var toSave: [PageTransform] = []
        // Pages affichées de chaque page source, calculées une fois (au lieu d'un parcours par page).
        var pagesBySource: [Int: [PDFPage]] = [:]
        for (i, p) in presented.enumerated() where crops[p.source] != nil {
            if let page = pdf.page(at: i) { pagesBySource[p.source, default: []].append(page) }
        }
        for (index, crop) in crops {
            var t = transforms[index] ?? PageTransform(documentId: documentId, pageIndex: index)
            t.autoCrop = crop
            transforms[index] = t
            toSave.append(t)
            guard !splitSources.contains(index), let box = originalBoxes[index] else { continue }
            for page in pagesBySource[index] ?? [] {
                page.setBounds(ContentBounds.apply(crop, to: box), for: .cropBox)
            }
        }
        model.persist { try $0.save(toSave) }
        pdfView.layoutDocumentView()
        // Les tailles de page ont changé : recalcul de l'échelle « page entière » (sauf si zoomé).
        if pdfView.isAtFit { pdfView.fitToPage() }
    }
}
