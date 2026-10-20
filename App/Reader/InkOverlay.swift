// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PDFKit
import PencilKit
import ReaderCore
import UIKit

/// Dessins au stylet : une vue PencilKit par page *affichée* (PDFKit crée et retire les surcouches
/// au fil du défilement), dessins chargés à la demande, enregistrés en différé hors du fil
/// principal. Les traits sont stockés dans le repère PDF de la page source : ils restent justes
/// quel que soit le rognage, la découpe ou la rotation.
@MainActor
final class InkStore: NSObject, PDFPageOverlayViewProvider {
    let documentId: String
    let model: AppModel
    weak var controller: ReaderController?

    let toolPicker = PKToolPicker()
    private var pagesWithInk: Set<Int> = []
    private var drawings: [Int: PKDrawing] = [:]
    private var dirty: Set<Int> = []
    private var saveWork: DispatchWorkItem?
    private var editing = false
    /// Surcouches visibles (pour mettre à jour les deux moitiés d'une page découpée).
    private let liveViews = NSHashTable<InkPageView>.weakObjects()

    init(documentId: String, model: AppModel) {
        self.documentId = documentId
        self.model = model
        super.init()
    }

    func loadIndex() throws {
        pagesWithInk = try model.database.pagesWithInk(documentId: documentId)
    }

    func drawing(forSource source: Int) -> PKDrawing {
        if let cached = drawings[source] { return cached }
        guard pagesWithInk.contains(source),
              let row = try? model.database.inkDrawing(documentId: documentId, pageIndex: source),
              let drawing = try? PKDrawing(data: row.data) else {
            return PKDrawing()
        }
        drawings[source] = drawing
        return drawing
    }

    func update(source: Int, drawing: PKDrawing, from view: InkPageView) {
        drawings[source] = drawing
        pagesWithInk.insert(source)
        dirty.insert(source)
        for other in liveViews.allObjects where other !== view && other.sourcePage == source {
            other.show(drawing)
        }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    /// Écrit les dessins modifiés (sérialisation et écriture en tâche de fond).
    func flush() {
        saveWork?.cancel()
        let pending = dirty.compactMap { source in drawings[source].map { (source, $0) } }
        dirty.removeAll()
        guard !pending.isEmpty else { return }
        let id = documentId
        model.persist { db in
            for (source, drawing) in pending {
                let data = drawing.dataRepresentation()
                try db.save(InkDrawing(documentId: id, pageIndex: source, data: data), isEmpty: drawing.strokes.isEmpty)
            }
        }
    }

    func setEditing(_ on: Bool) {
        editing = on
        for view in liveViews.allObjects { view.setEditing(on, toolPicker: toolPicker, finger: model.drawWithFinger) }
    }

    /// Affiche ou masque la palette d'outils (après que PDFKit a recréé les surcouches).
    func showToolPicker(_ on: Bool) {
        if on, let first = liveViews.allObjects.first {
            toolPicker.setVisible(true, forFirstResponder: first.canvas)
            first.canvas.becomeFirstResponder()
        } else {
            for view in liveViews.allObjects { toolPicker.setVisible(false, forFirstResponder: view.canvas) }
        }
    }

    // MARK: PDFPageOverlayViewProvider

    nonisolated func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        MainActor.assumeIsolated {
            guard let controller, let pdf = controller.pdf else { return nil }
            let index = pdf.index(for: page)
            guard controller.presented.indices.contains(index) else { return nil }
            let source = controller.presented[index].source
            // Pas de surcouche inutile : seulement si la page a déjà un dessin, ou si on dessine.
            guard editing || pagesWithInk.contains(source) else { return nil }
            let overlay = InkPageView(store: self, sourcePage: source, box: page.bounds(for: .cropBox), rotation: page.rotation)
            overlay.show(drawing(forSource: source))
            overlay.setEditing(editing, toolPicker: toolPicker, finger: model.drawWithFinger)
            liveViews.add(overlay)
            return overlay
        }
    }

    nonisolated func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        MainActor.assumeIsolated {
            guard let overlay = overlayView as? InkPageView else { return }
            toolPicker.removeObserver(overlay.canvas)
            liveViews.remove(overlay)
            if !dirty.isEmpty { flush() }
        }
    }
}

/// Surcouche d'une page : vue PencilKit transparente, dans le repère de la page affichée.
final class InkPageView: UIView, PKCanvasViewDelegate {
    let canvas = PKCanvasView()
    let sourcePage: Int
    private let box: CGRect
    private let rotation: Int
    private weak var store: InkStore?
    private var applying = false
    private var lastSize: CGSize = .zero
    private var canonical = PKDrawing()

    init(store: InkStore, sourcePage: Int, box: CGRect, rotation: Int) {
        self.store = store
        self.sourcePage = sourcePage
        self.box = box
        self.rotation = rotation
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.delegate = self
        addSubview(canvas)
    }

    required init?(coder: NSCoder) { fatalError("non utilisé") }

    /// Repère PDF de la page source → repère de cette vue.
    private var pageTransform: CGAffineTransform {
        let base = PageGeometry.pageToView(box: box, rotation: rotation)
        let rotatedWidth = rotation % 180 == 0 ? box.width : box.height
        let scale = bounds.width > 0 ? bounds.width / rotatedWidth : 1
        return base.concatenating(CGAffineTransform(scaleX: scale, y: scale))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        if bounds.size != lastSize, bounds.width > 0 {
            lastSize = bounds.size
            apply()
        }
    }

    func show(_ drawing: PKDrawing) {
        canonical = drawing
        apply()
    }

    private func apply() {
        guard bounds.width > 0 else { return }
        applying = true
        canvas.drawing = canonical.transformed(using: pageTransform)
        applying = false
    }

    @MainActor
    func setEditing(_ on: Bool, toolPicker: PKToolPicker, finger: Bool) {
        canvas.isUserInteractionEnabled = on
        canvas.drawingPolicy = finger ? .anyInput : .pencilOnly
        if on {
            toolPicker.addObserver(canvas)
            canvas.tool = toolPicker.selectedTool
        } else {
            toolPicker.removeObserver(canvas)
        }
    }

    // Laisse passer les touches vers PDFKit hors mode dessin.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        canvas.isUserInteractionEnabled ? super.hitTest(point, with: event) : nil
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !applying, bounds.width > 0 else { return }
        canonical = canvasView.drawing.transformed(using: pageTransform.inverted())
        MainActor.assumeIsolated { store?.update(source: sourcePage, drawing: canonical, from: self) }
    }
}
