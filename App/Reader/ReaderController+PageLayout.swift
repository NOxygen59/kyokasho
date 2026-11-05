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

    var pageRotations: [Int: Int] {
        Dictionary(uniqueKeysWithValues: (0..<document.pageCount).map { ($0, transforms[$0]?.rotation ?? 0) })
    }

    func applyPageRotations(_ rotations: [Int: Int], rereading: Bool) async throws {
        let source = currentSourcePage
        // Une lecture en cours pour l'ancienne orientation ne doit plus s'afficher.
        cancelEnsureOCR()
        furiganaTask?.cancel()
        try await model.applyPageRotations(rotations, to: document, rereading: rereading)
        transforms = try model.database.pageTransforms(documentId: document.id)
        ocrPage = nil
        // Mémoires de l'ancienne orientation : leurs boîtes normalisées, redessinées sur la page tournée,
        // tomberaient là où était le texte avant la rotation (recette 1.3.2 (72), essai 3.6).
        for page in rotations.keys {
            ink.setOCR(nil, source: page)
            realOCRMemo[page] = nil
            furiganaGeneration[page, default: 0] += 1
            pageFuriganaTasks[page]?.cancel()
        }
        LayoutRegionsCache.shared.clear()
        FuriganaLayer.clearMemory()
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
