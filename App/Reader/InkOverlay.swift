// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
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
    /// Pages dessinées pendant cette lecture : jamais oubliées (l'enregistrement est asynchrone).
    private var touched: Set<Int> = []
    private var saveWork: DispatchWorkItem?
    private var editing = false
    /// Zones OCR à dessiner (si le réglage est actif), par page source.
    private(set) var ocrPages: [Int: OCRPage] = [:]
    var showOCRBoxes = false {
        didSet { for view in liveViews.allObjects { view.showOCR(showOCRBoxes ? ocrPages[view.sourcePage] : nil) } }
    }

    func setOCR(_ page: OCRPage?, source: Int) {
        ocrPages[source] = page
        guard showOCRBoxes else { return }
        for view in liveViews.allObjects where view.sourcePage == source { view.showOCR(page) }
    }

    /// Surcouches visibles (pour mettre à jour les deux moitiés d'une page découpée).
    private let liveViews = NSHashTable<InkPageView>.weakObjects()

    init(documentId: String, model: AppModel) {
        self.documentId = documentId
        self.model = model
        super.init()
        // Les pages sont claires même en thème sombre : couleurs d'encre non inversées, stylo noir.
        toolPicker.colorUserInterfaceStyle = .light
        toolPicker.selectedTool = PKInkingTool(.pen, color: .black, width: 3)
    }

    /// Oublie dessins et zones OCR des pages éloignées (un long livre ne remplit plus la mémoire).
    /// Les dessins pas encore enregistrés sont gardés.
    func trim(around source: Int, keep: Int = 8) {
        drawings = drawings.filter { abs($0.key - source) <= keep || dirty.contains($0.key) || touched.contains($0.key) }
        ocrPages = ocrPages.filter { abs($0.key - source) <= keep }
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
        touched.insert(source)
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
        let canvases = liveViews.allObjects.compactMap(\.existingCanvas)
        if on, let first = canvases.first {
            toolPicker.setVisible(true, forFirstResponder: first)
            first.becomeFirstResponder()
        } else {
            for canvas in canvases {
                toolPicker.setVisible(false, forFirstResponder: canvas)
                canvas.resignFirstResponder()
            }
        }
    }

    // MARK: PDFPageOverlayViewProvider

    nonisolated func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        MainActor.assumeIsolated {
            guard let controller, let pdf = controller.pdf else { return nil }
            let index = pdf.index(for: page)
            guard controller.presented.indices.contains(index) else { return nil }
            let source = controller.presented[index].source
            // Surcouche légère pour chaque page affichée (PDFKit ne la redemande pas quand on passe en
            // mode dessin) ; la vue PencilKit n'est créée qu'en mode dessin ou si la page a un dessin.
            let overlay = InkPageView(store: self, sourcePage: source, box: page.bounds(for: .cropBox), rotation: page.rotation,
                                      sourceBox: controller.originalBox(ofSource: source) ?? page.bounds(for: .cropBox))
            if pagesWithInk.contains(source) { overlay.show(drawing(forSource: source)) }
            if showOCRBoxes { overlay.showOCR(ocrPages[source]) }
            overlay.setEditing(editing, toolPicker: toolPicker, finger: model.drawWithFinger)
            liveViews.add(overlay)
            return overlay
        }
    }

    nonisolated func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        MainActor.assumeIsolated {
            guard let overlay = overlayView as? InkPageView else { return }
            if let canvas = overlay.existingCanvas { toolPicker.removeObserver(canvas) }
            liveViews.remove(overlay)
            if !dirty.isEmpty { flush() }
        }
    }
}

/// Surcouche d'une page : vue PencilKit transparente, dans le repère de la page affichée.
final class InkPageView: UIView, PKCanvasViewDelegate {
    private var canvas: PKCanvasView?
    var existingCanvas: PKCanvasView? { canvas }
    let sourcePage: Int
    private let box: CGRect
    private let rotation: Int
    /// `cropBox` d'origine de la page source : repère des résultats OCR.
    private let sourceBox: CGRect
    private weak var store: InkStore?
    private let ocrLineLayer = CAShapeLayer()
    private let ocrCharLayer = CAShapeLayer()
    private var ocrPage: OCRPage?
    private var applying = false
    private var lastSize: CGSize = .zero
    private var canonical = PKDrawing()

    init(store: InkStore, sourcePage: Int, box: CGRect, rotation: Int, sourceBox: CGRect) {
        self.store = store
        self.sourcePage = sourcePage
        self.box = box
        self.rotation = rotation
        self.sourceBox = sourceBox
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        isUserInteractionEnabled = false
        for (layer, color, width) in [(ocrCharLayer, UIColor.systemBlue.withAlphaComponent(0.45), 0.5),
                                      (ocrLineLayer, UIColor.systemOrange.withAlphaComponent(0.9), 1.0)] {
            layer.fillColor = nil
            layer.strokeColor = color.cgColor
            layer.lineWidth = width
            self.layer.addSublayer(layer)
        }
    }

    /// Zones OCR (lignes en orange, caractères en bleu) ; `nil` pour les masquer.
    func showOCR(_ page: OCRPage?) {
        ocrPage = page
        drawOCR()
    }

    private func drawOCR() {
        guard let page = ocrPage, bounds.width > 0, sourceBox.width > 0 else {
            ocrLineLayer.path = nil
            ocrCharLayer.path = nil
            return
        }
        let transform = pageTransform
        func path(_ boxes: [NormBox]) -> CGPath {
            let p = CGMutablePath()
            for b in boxes {
                p.addRect(CGRect(x: sourceBox.minX + b.x * sourceBox.width, y: sourceBox.maxY - (b.y + b.h) * sourceBox.height,
                                 width: b.w * sourceBox.width, height: b.h * sourceBox.height), transform: transform)
            }
            return p
        }
        ocrLineLayer.path = path(page.lines.map(\.box))
        ocrCharLayer.path = path(page.lines.flatMap(\.charBoxes))
    }

    /// Crée la vue PencilKit à la première utilisation (mémoire : rien pour les pages sans dessin).
    @discardableResult
    private func ensureCanvas() -> PKCanvasView {
        if let canvas { return canvas }
        let canvas = PKCanvasView(frame: bounds)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.isUserInteractionEnabled = false
        // Encre affichée telle quelle (sinon le noir devient blanc en thème sombre).
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = self
        addSubview(canvas)
        self.canvas = canvas
        return canvas
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
        canvas?.frame = bounds
        if bounds.size != lastSize, bounds.width > 0 {
            lastSize = bounds.size
            apply()
            drawOCR()
        }
    }

    func show(_ drawing: PKDrawing) {
        canonical = drawing
        if canvas == nil && drawing.strokes.isEmpty { return }
        ensureCanvas()
        apply()
    }

    private func apply() {
        guard bounds.width > 0, let canvas else { return }
        applying = true
        canvas.drawing = canonical.transformed(using: pageTransform)
        applying = false
    }

    @MainActor
    func setEditing(_ on: Bool, toolPicker: PKToolPicker, finger: Bool) {
        isUserInteractionEnabled = on
        guard on || canvas != nil else { return }
        let canvas = ensureCanvas()
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
        canvas?.isUserInteractionEnabled == true ? super.hitTest(point, with: event) : nil
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !applying, bounds.width > 0 else { return }
        canonical = canvasView.drawing.transformed(using: pageTransform.inverted())
        MainActor.assumeIsolated { store?.update(source: sourcePage, drawing: canonical, from: self) }
    }
}
