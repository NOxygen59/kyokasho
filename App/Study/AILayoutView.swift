// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import GLMOCRKit
import OCRKit
import SwiftUI
import UIKit

/// Panneau Texte → « Mise en page IA » : la page telle qu'OvisOCR2 l'a mise en forme (titres, paragraphes, listes,
/// tableaux, figures découpées dans la page), en HTML **construit ici** à partir de blocs sûrs (`AILayout`), aux
/// couleurs du thème, avec furigana et dictionnaire au toucher. Markdown gardé par page (le même que l'analyse).
struct AILayoutView: View {
    @ObservedObject var reader: ReaderController
    let furigana: Bool
    var onLookup: (String) -> Void
    @EnvironmentObject private var dictionary: DictionaryModel
    @AppStorage(FuriganaLayer.Tint.storageKey) private var tint = FuriganaLayer.Tint.red
    @State private var markdown: String?
    @State private var html = ""
    @State private var height: CGFloat = 200
    @ObservedObject private var center = AITaskCenter.shared
    /// Lecture / traduction : tâches de l'app (continuent si on change de page), une par page.
    private var layoutKey: String { "layout|\(reader.document.id)|\(source)" }
    private var translateKey: String { "translate|\(reader.document.id)|\(source)" }
    private var reading: Bool { center.isRunning(layoutKey) }
    private var translating: Bool { center.isRunning(translateKey) }
    private var error: String? { center.errors[layoutKey] ?? center.errors[translateKey] }
    /// Traduction française (Qwen3-VL, hors ligne) de la mise en page, gardée par page.
    @AppStorage("study.aiLayoutFrench") private var french = false
    @State private var frenchMarkdown: String?

    private var source: Int { reader.focusSource }
    private var file: URL { DocumentAnalysisService.rawURL(reader.document.id, ModelSpec.ovisocr2.id, source) }
    private var frenchFile: URL { DocumentAnalysisService.rawURL(reader.document.id, "fr", source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if reading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("OvisOCR2 met la page en forme… (≈ 30 s)").font(.footnote).foregroundStyle(Atelier.textSecondary)
                }
            } else if markdown == nil {
                Text("Pas encore de mise en page IA pour cette page.").font(.footnote).foregroundStyle(Atelier.textSecondary)
                if OvisOCR2Reader().isAvailable {
                    Button { read() } label: {
                        Label("Mettre en page avec OvisOCR2", systemImage: "sparkles.rectangle.stack")
                    }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.ai))
                } else {
                    Text("Télécharge OvisOCR2 dans Réglages → Modèles d'IA et outils.").font(.caption).foregroundStyle(Atelier.textTertiary)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if markdown != nil {
                languageRow
            }
            if markdown != nil, !html.isEmpty {
                RubyWebView(html: html, height: $height, onLookup: onLookup)
                    .frame(height: height)
                Button { read() } label: {
                    Label("Refaire la mise en page", systemImage: "arrow.clockwise").font(.caption)
                }
                .foregroundStyle(Atelier.textTertiary)
                .disabled(reading || !OvisOCR2Reader().isAvailable)
            }
        }
        .task(id: "\(reader.document.id)|\(source)|\(furigana)|\(tint.rawValue)|\(french)|\(center.finished)") { await load() }
    }

    /// Japonais / français (si traduit), ou bouton de traduction hors ligne par Qwen3-VL.
    @ViewBuilder
    private var languageRow: some View {
        if translating {
            HStack(spacing: 10) {
                ProgressView()
                Text("Qwen3-VL traduit la page… (1 à 3 min, hors ligne)").font(.footnote).foregroundStyle(Atelier.textSecondary)
            }
        } else if frenchMarkdown != nil {
            HStack {
                Picker("Langue", selection: $french) {
                    Text("日本語").tag(false)
                    Text("Français").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                Spacer()
                Button { translate() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Retraduire la page")
                    .foregroundStyle(Atelier.textTertiary)
                    .disabled(!Qwen3VLReader().isAvailable)
            }
        } else if Qwen3VLReader().isAvailable {
            Button { translate() } label: {
                Label("Traduire en français (hors ligne)", systemImage: "character.bubble")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Atelier.Tint.ai)
        }
    }

    /// Traduction de la page (fichier gardé), même si on change de page entre-temps.
    private func translate() {
        guard let markdown else { return }
        let source = source, frenchFile = frenchFile, glossary = DomainLexicon.shared.glossary
        center.run(translateKey, title: "Traduction Qwen3-VL p. \(source + 1)", modelId: ModelSpec.qwen3vl4b.id, activity: "traduction") { _ in
            let fr = try await Diagnostics.measure("traduction p. \(source)", "traduction") {
                try await Qwen3VLReader().translate(markdown: markdown, glossary: glossary)
            }
            // Arrêtée : la génération rend un texte partiel, jamais gardé.
            try Task.checkCancellation()
            try? FileManager.default.createDirectory(at: frenchFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fr.write(to: frenchFile, atomically: true, encoding: .utf8)
            UserDefaults.standard.set(true, forKey: "study.aiLayoutFrench")
        }
    }

    private func load() async {
        markdown = try? String(contentsOf: file, encoding: .utf8)
        frenchMarkdown = try? String(contentsOf: frenchFile, encoding: .utf8)
        html = ""
        guard let markdown else { return }
        let showFrench = french && frenchMarkdown != nil
        let built = await Self.html(showFrench ? frenchMarkdown! : markdown, furigana: furigana && !showFrench,
                                    french: showFrench, vertical: !showFrench && reader.ocrPage.map(FuriganaTextView.isVertical) == true,
                                    dictionary: dictionary, url: reader.fileURL, page: source)
        guard !Task.isCancelled else { return }
        html = built
    }

    /// Mise en page de la page par OvisOCR2 (fichier gardé), même si on change de page entre-temps.
    private func read() {
        let budget = reader.ocrPage.map(DocumentAnalysisService.tokenBudget) ?? 2048
        let source = source, file = file, frenchFile = frenchFile, url = reader.fileURL, documentId = reader.document.id
        center.run(layoutKey, title: "Mise en page IA p. \(source + 1)", modelId: ModelSpec.ovisocr2.id, activity: "mise en page") { _ in
            let text = try await Diagnostics.measure("mise en page IA p. \(source)", "miseenpage") {
                try await OvisOCR2Reader().read(.pdfPage(url: url, index: source), maxTokens: budget)
            }
            try Task.checkCancellation()
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            NotificationCenter.default.post(name: .aiPageRead, object: DocumentScan.PageRead(documentId: documentId, page: source))
            // Mise en page refaite : l'ancienne traduction ne correspond plus.
            try? FileManager.default.removeItem(at: frenchFile)
        }
    }

    // MARK: HTML

    /// Blocs → HTML. Tout texte passe par `FuriganaTextView.markup` (échappé, mot entier au toucher, furigana).
    static func html(_ markdown: String, furigana: Bool, french: Bool = false, vertical: Bool = false, dictionary: DictionaryModel,
                     url: URL, page: Int) async -> String {
        let blocks = AILayout.blocks(markdown)
        func text(_ s: String) async -> String {
            // Français : texte simplement échappé (pas de dictionnaire japonais au toucher).
            if french { return "<span lang=\"fr\">\(FuriganaTextView.escape(s))</span>" }
            let segments = await dictionary.segment(s)
            let rubies = furigana ? TextFurigana.rubies(s, segments: segments) : []
            return FuriganaTextView.markup(s, rubies: rubies, wordStarts: FuriganaTextView.wordStarts(s, segments: segments))
        }
        // Figures : une seule image de la page, découpée hors du fil principal.
        let boxes = blocks.compactMap { b -> (Int, Int, Int, Int)? in
            if case .figure(let l, let t, let r, let bt) = b { return (l, t, r, bt) }
            return nil
        }
        let figures: [String] = boxes.isEmpty ? [] : await Task.detached(priority: .userInitiated) {
            guard let image = try? PageRenderer.render(url: url, pageIndex: page, longSide: 1600) else { return [] }
            return boxes.map { figureURI(image, $0) ?? "" }
        }.value
        var body = """
        <style>
        .figs{display:flex;flex-wrap:wrap;gap:10px;margin:.4em 0 .9em;justify-content:flex-start}
        figure{margin:0;width:calc(33.3% - 7px);text-align:center}
        figure img{max-width:100%;max-height:170px;border-radius:6px;background:#fff}
        figcaption{font-size:.72em;line-height:1.4;margin-top:4px;opacity:.85}
        p.figtitle{text-align:center;font-size:.8em;opacity:.8;margin-top:-.2em}
        th{font-weight:700;opacity:.9} ul{margin:0 0 .6em;padding-left:1.3em} li{margin:.15em 0}
        h2,h3,h4{line-height:1.6;margin:.8em 0 .4em}
        </style>
        """
        // Français : police sans empattement, interligne normal (pas de place à garder pour des furigana).
        if french { body += "<style>body{font-family:-apple-system,'Helvetica Neue',sans-serif;line-height:1.65}</style>" }
        var figureIndex = 0
        // Figures qui se suivent (chacune avec sa courte légende) : grille de vignettes, comme dans le livre.
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            if case .figure = block {
                body += "<div class=\"figs\">"
                while index < blocks.count, case .figure = blocks[index] {
                    var caption = ""
                    if index + 1 < blocks.count, case .paragraph(let c) = blocks[index + 1], c.count <= 24 {
                        caption = await text(c)
                        index += 1
                        // Petites notes entre parenthèses sous la légende : « (ルバードア) », « (2枚一組) ».
                        while index + 1 < blocks.count, case .paragraph(let note) = blocks[index + 1], note.count <= 14,
                              note.hasPrefix("(") || note.hasPrefix("（") {
                            caption += "<br>" + (await text(note))
                            index += 1
                        }
                    }
                    let uri = figures.indices.contains(figureIndex) ? figures[figureIndex] : ""
                    figureIndex += 1
                    body += "<figure>" + (uri.isEmpty ? "" : "<img src=\"\(uri)\" alt=\"\">")
                        + (caption.isEmpty ? "" : "<figcaption>\(caption)</figcaption>") + "</figure>"
                    index += 1
                }
                body += "</div>"
                continue
            }
            index += 1
            switch block {
            case .heading(let level, let s):
                let tag = "h\(min(max(level, 2), 4))"
                body += "<\(tag)>\(await text(s))</\(tag)>"
            case .paragraph(let s):
                // « 図表6-120 … » : titre de figure, centré en petit comme dans le livre.
                let isFigureTitle = s.hasPrefix("図表") || s.hasPrefix("図 ") || s.hasPrefix("表 ")
                body += isFigureTitle ? "<p class=\"figtitle\">\(await text(s))</p>" : "<p>\(await text(s))</p>"
            case .list(let items):
                body += "<ul>"
                for item in items { body += "<li>\(await text(item))</li>" }
                body += "</ul>"
            case .table(let rows):
                body += "<table>"
                for row in rows {
                    body += "<tr>"
                    for cell in row {
                        let tag = cell.header ? "th" : "td"
                        let span = (cell.colspan > 1 ? " colspan=\"\(cell.colspan)\"" : "") + (cell.rowspan > 1 ? " rowspan=\"\(cell.rowspan)\"" : "")
                        body += "<\(tag)\(span)>\(await text(cell.text))</\(tag)>"
                    }
                    body += "</tr>"
                }
                body += "</table>"
            case .figure:
                break  // traitées plus haut (grille)
            }
        }
        return FuriganaTextView.page(body, vertical: vertical)
    }

    /// Découpe d'une figure (coordonnées sur 1000) → image JPEG en `data:` (≤ 900 px de large).
    nonisolated static func figureURI(_ image: CGImage, _ box: (Int, Int, Int, Int)) -> String? {
        let w = Double(image.width), h = Double(image.height)
        let rect = CGRect(x: Double(box.0) / 1000 * w, y: Double(box.1) / 1000 * h,
                          width: Double(box.2 - box.0) / 1000 * w, height: Double(box.3 - box.1) / 1000 * h)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard rect.width >= 8, rect.height >= 8, let crop = image.cropping(to: rect) else { return nil }
        let scale = min(1, 900 / rect.width)
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let jpeg = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.8) { _ in
            UIImage(cgImage: crop).draw(in: CGRect(origin: .zero, size: size))
        }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}
