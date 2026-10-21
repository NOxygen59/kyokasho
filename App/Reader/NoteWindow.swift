// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PencilKit
import ReaderCore
import SwiftUI

/// Fenêtre flottante d'une note : déplaçable (en-tête), redimensionnable (coin bas-droit, doigt / Pencil / souris).
/// Contenu à taille fixe (on défile dedans si la fenêtre est petite) : texte au clavier et dessin au Pencil
/// en même temps (le Pencil dessine, le doigt écrit / défile ; « doigt » permet aussi de dessiner au doigt).
struct NoteWindow: View {
    @ObservedObject var reader: ReaderController
    let note: PageComment
    /// Zone où la fenêtre peut aller.
    let area: CGSize

    @AppStorage("note.width") private var width = 420.0
    @AppStorage("note.height") private var height = 380.0
    @AppStorage("note.x") private var x = 80.0
    @AppStorage("note.y") private var y = 120.0
    @GestureState private var move: CGSize = .zero
    @GestureState private var resize: CGSize = .zero
    @State private var tool = NoteCanvas.Tool.pen(.black)
    @State private var fingerDraws = false

    private static let minSize = CGSize(width: 260, height: 200)

    var body: some View {
        let w = min(max(Self.minSize.width, width + resize.width), area.width)
        let h = min(max(Self.minSize.height, height + resize.height), area.height)
        let left = min(max(0, x + move.width), max(0, area.width - w))
        let top = min(max(0, y + move.height), max(0, area.height - h))
        VStack(spacing: 0) {
            header
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .updating($move) { v, s, _ in s = v.translation }
                    .onEnded { v in
                        x = min(max(0, x + v.translation.width), max(0, area.width - w))
                        y = min(max(0, y + v.translation.height), max(0, area.height - h))
                    })
            Divider().overlay(Atelier.hairline)
            NoteCanvas(note: note, tool: tool, fingerDraws: fingerDraws) { text, drawing in
                // Note supprimée entre-temps : surtout ne pas la recréer.
                guard var updated = reader.notes.first(where: { $0.id == note.id }) else { return }
                if let text { updated.body = text }
                if let drawing { updated.drawing = drawing }
                reader.saveNote(updated)
            }
            .id(note.id)
        }
        .frame(width: w, height: h)
        .background(Atelier.surface)
        .clipShape(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous)
            .strokeBorder(Atelier.Tint.annotate.opacity(0.45), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) { resizeHandle(w: w, h: h) }
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .offset(x: left, y: top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transaction { if move != .zero || resize != .zero { $0.animation = nil } }
    }

    private var current: PageComment { reader.notes.first { $0.id == note.id } ?? note }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(Atelier.textTertiary)
            Text("Note · p. \(reader.document.pageLabel(current.pageIndex))")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Atelier.textSecondary).lineLimit(1)
            Spacer(minLength: 4)
            toolButton(.pen(.black), icon: "pencil.tip", color: .white)
            toolButton(.pen(.systemRed), icon: "pencil.tip", color: .red)
            toolButton(.pen(.systemBlue), icon: "pencil.tip", color: .blue)
            toolButton(.eraser, icon: "eraser", color: Atelier.textSecondary)
            Button { fingerDraws.toggle() } label: {
                Image(systemName: fingerDraws ? "hand.draw.fill" : "hand.draw")
                    .foregroundStyle(fingerDraws ? Atelier.Tint.annotate : Atelier.textSecondary)
            }
            .accessibilityLabel(fingerDraws ? "Le doigt écrit du texte" : "Dessiner au doigt ou à la souris")
            anchorButton
            Button { reader.openNote = nil } label: { Image(systemName: "xmark").foregroundStyle(Atelier.textSecondary) }
                .accessibilityLabel("Fermer la note")
        }
        .font(.system(size: 14, weight: .semibold))
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Atelier.surfaceHigh.opacity(0.6))
        .contentShape(Rectangle())
    }

    /// Ancre : aller au mot ancré (lien) ; appui long → déplacer l'ancre. Sans ancre : la poser.
    @ViewBuilder
    private var anchorButton: some View {
        if current.anchorRect != nil {
            Button { reader.goToAnchor(current) } label: {
                HStack(spacing: 3) {
                    Text("＊").foregroundStyle(Atelier.Tint.annotate)
                    if let text = current.anchorText { Text(text).lineLimit(1).frame(maxWidth: 70) }
                }
            }
            .contextMenu {
                Button { reader.placingAnchorFor = current } label: { Label("Déplacer l'ancre", systemImage: "scope") }
                Button(role: .destructive) {
                    var n = current
                    n.anchorRect = nil
                    n.anchorText = nil
                    reader.saveNote(n)
                } label: { Label("Retirer l'ancre", systemImage: "xmark") }
            }
            .accessibilityLabel("Aller au mot ancré")
        } else {
            Button { reader.placingAnchorFor = current } label: {
                Image(systemName: "scope")
                    .foregroundStyle(reader.placingAnchorFor?.id == note.id ? Atelier.Tint.annotate : Atelier.textSecondary)
            }
            .accessibilityLabel("Ancrer la note sur un mot de la page (toucher ensuite la page)")
        }
    }

    private func toolButton(_ target: NoteCanvas.Tool, icon: String, color: Color) -> some View {
        Button { tool = target } label: {
            Image(systemName: icon)
                .foregroundStyle(color)
                .padding(3)
                .background(tool == target ? Atelier.Tint.annotate.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private func resizeHandle(w: CGFloat, h: CGFloat) -> some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .rotationEffect(.degrees(90))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Atelier.textTertiary)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .updating($resize) { v, s, _ in s = v.translation }
                .onEnded { v in
                    width = min(max(Self.minSize.width, width + v.translation.width), area.width)
                    height = min(max(Self.minSize.height, height + v.translation.height), area.height)
                })
            .accessibilityLabel("Redimensionner la note")
    }
}

/// Feuille de la note : `PKCanvasView` (défilement + dessin) avec un `UITextView` dessous, à taille fixe.
struct NoteCanvas: UIViewRepresentable {
    enum Tool: Equatable {
        case pen(UIColor), eraser
    }

    let note: PageComment
    var tool: Tool
    var fingerDraws: Bool
    /// Texte ou dessin changé (l'autre à `nil`), après une courte pause.
    var onChange: (String?, Data?) -> Void

    static let pageSize = CGSize(width: 820, height: 1400)

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = UIColor(white: 0.97, alpha: 1)
        canvas.isOpaque = true
        canvas.contentSize = Self.pageSize
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.alwaysBounceVertical = true
        canvas.overrideUserInterfaceStyle = .light
        if let data = note.drawing, let drawing = try? PKDrawing(data: data) { canvas.drawing = drawing }
        canvas.delegate = context.coordinator

        let text = UITextView(frame: CGRect(origin: .zero, size: Self.pageSize))
        text.backgroundColor = .clear
        text.isScrollEnabled = false
        text.font = UIFont(name: "HiraginoSans-W3", size: 18) ?? .systemFont(ofSize: 18)
        text.textColor = .black
        text.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        text.text = note.body
        text.delegate = context.coordinator
        // Sous le dessin : l'encre reste par-dessus le texte.
        canvas.insertSubview(text, at: 0)
        context.coordinator.textView = text
        context.coordinator.canvas = canvas
        context.coordinator.fitText()
        apply(to: canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.onChange = onChange
        apply(to: canvas)
    }

    private func apply(to canvas: PKCanvasView) {
        canvas.drawingPolicy = fingerDraws ? .anyInput : .pencilOnly
        switch tool {
        case .pen(let color): canvas.tool = PKInkingTool(.pen, color: color, width: 3)
        case .eraser: canvas.tool = PKEraserTool(.vector)
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.flush()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UITextViewDelegate {
        var onChange: (String?, Data?) -> Void
        weak var textView: UITextView?
        weak var canvas: PKCanvasView?
        private var pendingText: String?
        private var drawingChanged = false
        private var timer: Timer?

        init(onChange: @escaping (String?, Data?) -> Void) { self.onChange = onChange }

        func textViewDidChange(_ textView: UITextView) {
            pendingText = textView.text
            fitText()
            schedule()
        }

        /// La feuille s'allonge avec le texte (jamais moins que la taille de départ).
        func fitText() {
            guard let textView, let canvas else { return }
            let width = NoteCanvas.pageSize.width
            let needed = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height + 200
            let height = max(NoteCanvas.pageSize.height, needed, canvas.contentSize.height)
            guard height != textView.frame.height else { return }
            textView.frame = CGRect(x: 0, y: 0, width: width, height: height)
            canvas.contentSize = CGSize(width: width, height: height)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Sérialisé à l'enregistrement seulement (pas à chaque trait).
            drawingChanged = true
            schedule()
        }

        private func schedule() {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in self?.flush() }
        }

        /// Enregistre ce qui attend (aussi à la fermeture de la fenêtre).
        func flush() {
            timer?.invalidate()
            guard pendingText != nil || drawingChanged else { return }
            let text = pendingText
            let drawing = drawingChanged ? canvas?.drawing.dataRepresentation() : nil
            pendingText = nil
            drawingChanged = false
            onChange(text, drawing)
        }
    }
}
