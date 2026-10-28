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
    var hoverReset = 0
    var onLookup: (PanelLookupEvent) -> Void
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
    private var error: String? { center.errors[layoutKey] ?? center.errors[translateKey] }
    /// Traduction française (Qwen3-VL, hors ligne) de la mise en page, gardée par page.
    @AppStorage("study.aiLayoutFrench") private var french = false
    @State private var frenchMarkdown: String?
    /// Page construite avec les deux langues (`#langs`) : la bascule passe par `RubyWebView.language`.
    @State private var combined = false

    private var source: Int { reader.focusSource }

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
            if markdown != nil, !html.isEmpty {
                RubyWebView(html: html, height: $height, hoverReset: hoverReset,
                            language: combined ? french : nil, onLookup: onLookup)
                    .frame(height: height)
                    .modifier(OCRScrollDiagnostics())
                Button { read() } label: {
                    Label("Refaire la mise en page", systemImage: "arrow.clockwise").font(.caption)
                }
                .foregroundStyle(Atelier.textTertiary)
                .disabled(reading || !OvisOCR2Reader().isAvailable)
            }
        }
        .task(id: "\(reader.document.id)|\(source)|\(furigana)|\(tint.rawValue)|\(center.finished)") { await load() }
        // Japonais et français dans la même page : la vue web bascule sans recharger et garde la position de
        // lecture (recette 1.3.2 (55)). Sinon (pas de traduction, texte vertical) : reconstruction comme avant.
        .onChange(of: french) { _ in if !combined { Task { await load() } } }
    }

    private func load() async {
        markdown = DocumentAITextStore.read(documentId: reader.document.id, reader: ModelSpec.ovisocr2.id, page: source)
        frenchMarkdown = DocumentAITextStore.read(documentId: reader.document.id, reader: "fr", page: source)
        html = ""
        guard let markdown else { return }
        let vertical = reader.ocrPage.map(FuriganaTextView.isVertical) == true
        // Valeurs construites localement, publiées ensemble après le contrôle d'annulation : une tâche annulée
        // (changement de page pendant la construction) ne touche ni `combined` ni `html` (revue de Codex, #78).
        let built: String, bothLanguages: Bool
        if let frenchMarkdown, !vertical {
            // Les deux langues dans la même page ; `RubyWebView` affiche celle de `french` dès le chargement.
            let japanese = await Self.body(markdown, furigana: furigana, dictionary: dictionary, url: reader.fileURL, page: source)
            let translated = await Self.body(frenchMarkdown, furigana: false, french: true, dictionary: dictionary,
                                             url: reader.fileURL, page: source)
            built = FuriganaTextView.page("<div id=\"langs\" class=\"\(french ? "fr" : "ja")\"><div id=\"ja\">\(japanese)</div>"
                                          + "<div id=\"fr\">\(translated)</div></div><script>\(Self.languageSwitchScript)</script>")
            bothLanguages = true
        } else {
            let showFrench = french && frenchMarkdown != nil
            built = await Self.html(showFrench ? frenchMarkdown! : markdown, furigana: furigana && !showFrench,
                                    french: showFrench, vertical: !showFrench && vertical,
                                    dictionary: dictionary, url: reader.fileURL, page: source)
            bothLanguages = false
        }
        guard !Task.isCancelled else { return }
        combined = bothLanguages
        html = built
    }

    /// Bascule 日本語 / Français sans recharger, appelée par `RubyWebView` avec `y` = haut de la zone visible du
    /// panneau en pixels CSS de la page (0 ou moins : rien à garder). Le bloc lu en haut (`data-b`, indice du bloc
    /// Markdown) est retrouvé dans l'autre langue, à la même fraction de sa hauteur ; si les deux traductions n'ont
    /// pas le même nombre de blocs, position proportionnelle. Renvoie le nouvel `y` et la nouvelle hauteur.
    /// Testé par `scripts/test_ai_language_switch.cjs`.
    static let languageSwitchScript = """
    window.__kyokashoSwitchLanguage=function(fr,y){
      var langs=document.getElementById('langs'); if(!langs){return null}
      var from=document.getElementById(fr?'ja':'fr'), to=document.getElementById(fr?'fr':'ja');
      if(langs.className===(fr?'fr':'ja')){return {y:y,h:document.body.scrollHeight}}
      var oldH=document.body.scrollHeight, anchor=null, frac=0, scrollY=window.scrollY||0;
      var a=from.querySelectorAll('[data-b]'), b=null;
      if(y>0){for(var i=0;i<a.length;i++){var r=a[i].getBoundingClientRect(), top=r.top+scrollY;
        if(top+r.height>y){anchor=a[i]; frac=r.height>0?Math.max(0,Math.min(1,(y-top)/r.height)):0; break}}}
      langs.className=fr?'fr':'ja';
      var newH=document.body.scrollHeight, newY=y;
      if(y>0){
        b=to.querySelectorAll('[data-b]'); var target=null;
        if(anchor&&b.length===a.length){var k=+anchor.dataset.b;
          for(var j=0;j<b.length;j++){if(+b[j].dataset.b<=k){target=b[j]}}}
        if(target){var r2=target.getBoundingClientRect(); newY=r2.top+scrollY+frac*r2.height}
        else if(oldH>0){newY=y/oldH*newH}
      }
      return {y:newY,h:newH};
    };
    """

    /// Mise en page de la page par OvisOCR2 (fichier gardé), même si on change de page entre-temps.
    private func read() {
        let budget = reader.ocrPage.map(DocumentAnalysisService.tokenBudget) ?? 2048
        let source = source, url = reader.fileURL, documentId = reader.document.id
        center.run(layoutKey, title: "Mise en page IA p. \(source + 1)", modelId: ModelSpec.ovisocr2.id, activity: "mise en page") { _ in
            let text = try await Diagnostics.measure("mise en page IA p. \(source)", "miseenpage") {
                try await OvisOCR2Reader(language: OCRTargetLanguage.forDocument(documentId))
                    .read(.pdfPage(url: url, index: source), maxTokens: budget)
            }
            try Task.checkCancellation()
            try DocumentAITextStore.write(text, documentId: documentId, reader: ModelSpec.ovisocr2.id, page: source)
            DocumentAnalysisService.shared.invalidatePage(source, documentId: documentId)
            NotificationCenter.default.post(name: .aiPageRead, object: DocumentScan.PageRead(documentId: documentId, page: source))
        }
    }

    // MARK: HTML

    /// Page complète d'une seule langue.
    static func html(_ markdown: String, furigana: Bool, french: Bool = false, vertical: Bool = false, dictionary: DictionaryModel,
                     url: URL, page: Int) async -> String {
        FuriganaTextView.page(await body(markdown, furigana: furigana, french: french, dictionary: dictionary, url: url, page: page),
                              vertical: vertical)
    }

    /// Blocs → HTML. Tout texte passe par `FuriganaTextView.markup` (échappé, mot entier au toucher, furigana).
    /// Chaque élément de premier niveau porte `data-b` (indice du bloc Markdown) : repère commun aux deux langues.
    static func body(_ markdown: String, furigana: Bool, french: Bool = false, dictionary: DictionaryModel,
                     url: URL, page: Int) async -> String {
        let blocks = AILayout.blocks(markdown)
        func text(_ s: String) async -> String {
            // Français : texte simplement échappé (pas de dictionnaire japonais au toucher).
            if french { return "<span lang=\"fr\">\(FuriganaTextView.escape(s))</span>" }
            var result = ""
            for part in FormulaMarkup.parts(s) {
                switch part {
                case .formula(let source): result += FormulaMarkup.html(source)
                case .prose(let prose):
                    let segments = await dictionary.segment(prose)
                    let rubies = furigana ? TextFurigana.rubies(prose, segments: segments) : []
                    result += FuriganaTextView.markup(prose, rubies: rubies,
                                                     wordStarts: FuriganaTextView.wordStarts(prose, segments: segments))
                }
            }
            return result
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
        .formula{display:inline-block;white-space:nowrap;font-family:'Times New Roman',serif;
                 background:rgba(255,255,255,.06);padding:0 .12em;border-radius:.15em}
        .formula sup,.formula sub{font-size:.72em;line-height:0}
        .formula .frac{display:inline-flex;vertical-align:middle;flex-direction:column;text-align:center;font-size:.86em}
        .formula .frac>span:first-child{border-bottom:1px solid;padding:0 .15em}
        .formula .radicand{border-top:1px solid;padding:0 .12em}
        </style>
        """
        // Français : police sans empattement, interligne normal (pas de place à garder pour des furigana). Limité au
        // bloc `.fr-text` : la page qui contient les deux langues garde le style japonais pour `#ja`.
        if french { body += "<style>.fr-text{font-family:-apple-system,'Helvetica Neue',sans-serif;line-height:1.65}</style><div class=\"fr-text\">" }
        body += "<style>#langs.ja #fr,#langs.fr #ja{display:none}</style>"
        var figureIndex = 0
        // Figures qui se suivent (chacune avec sa courte légende) : grille de vignettes, comme dans le livre.
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            if case .figure = block {
                body += "<div class=\"figs\" data-b=\"\(index)\">"
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
            let b = " data-b=\"\(index)\""
            index += 1
            switch block {
            case .heading(let level, let s):
                let tag = "h\(min(max(level, 2), 4))"
                body += "<\(tag)\(b)>\(await text(s))</\(tag)>"
            case .paragraph(let s):
                // « 図表6-120 … » : titre de figure, centré en petit comme dans le livre.
                let isFigureTitle = s.hasPrefix("図表") || s.hasPrefix("図 ") || s.hasPrefix("表 ")
                body += isFigureTitle ? "<p class=\"figtitle\"\(b)>\(await text(s))</p>" : "<p\(b)>\(await text(s))</p>"
            case .list(let items):
                body += "<ul\(b)>"
                for item in items { body += "<li>\(await text(item))</li>" }
                body += "</ul>"
            case .table(let rows):
                body += "<table\(b)>"
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
        if french { body += "</div>" }
        return body
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

/// Présentation locale des formules OvisOCR2. Le Markdown d'origine reste inchangé pour la copie
/// et la comparaison avec la page ; seules les commandes reconnues deviennent des symboles.
private enum FormulaMarkup {
    enum Part { case prose(String), formula(String) }

    static func parts(_ text: String) -> [Part] {
        var result: [Part] = []
        var cursor = text.startIndex
        while cursor < text.endIndex, let open = text[cursor...].firstIndex(of: "$") {
            if open > cursor { result.append(.prose(String(text[cursor..<open]))) }
            let next = text.index(after: open)
            let doubled = next < text.endIndex && text[next] == "$"
            let bodyStart = doubled ? text.index(after: next) : next
            let delimiter = doubled ? "$$" : "$"
            guard let close = text[bodyStart...].range(of: delimiter) else {
                result.append(.prose(String(text[open...])))
                return result
            }
            result.append(.formula(String(text[bodyStart..<close.lowerBound])))
            cursor = close.upperBound
        }
        if cursor < text.endIndex { result.append(.prose(String(text[cursor...]))) }
        return result
    }

    static func html(_ latex: String) -> String {
        var parser = Parser(Array(latex))
        return "<span class=\"formula\" aria-label=\"formule OCR à vérifier sur la page\">" + parser.render() + "</span>"
    }

    private struct Parser {
        let chars: [Character]
        var index = 0

        init(_ chars: [Character]) { self.chars = chars }

        mutating func group() -> String {
            guard index < chars.count else { return "" }
            if chars[index] == "{" {
                index += 1
                return render(untilBrace: true)
            }
            let char = chars[index]
            index += 1
            return FuriganaTextView.escape(String(char))
        }

        mutating func render(untilBrace: Bool = false) -> String {
            var out = ""
            while index < chars.count {
                let char = chars[index]
                index += 1
                if char == "}" && untilBrace { break }
                if char == "\\" {
                    let start = index
                    while index < chars.count && chars[index].isLetter { index += 1 }
                    let command = String(chars[start..<index])
                    switch command {
                    case "frac":
                        let top = group(), bottom = group()
                        out += "<span class=\"frac\"><span>\(top)</span><span>\(bottom)</span></span>"
                    case "sqrt": out += "√<span class=\"radicand\">\(group())</span>"
                    case "alpha": out += "α"
                    case "beta": out += "β"
                    case "gamma": out += "γ"
                    case "pi": out += "π"
                    case "propto": out += "∝"
                    case "cdot", "times": out += command == "cdot" ? "·" : "×"
                    case "leq": out += "≤"
                    case "geq": out += "≥"
                    case "mathrm", "text": out += group()
                    default: out += FuriganaTextView.escape("\\" + command)
                    }
                } else if char == "_" || char == "^" {
                    let tag = char == "_" ? "sub" : "sup"
                    out += "<\(tag)>\(group())</\(tag)>"
                } else if char == "{" {
                    out += render(untilBrace: true)
                } else {
                    out += FuriganaTextView.escape(String(char))
                }
            }
            return out
        }
    }
}

/// Barre 日本語 / Français de la mise en page IA (#17), **hors du défilement** du panneau Texte : toujours visible,
/// même en bas d'une longue page. Mêmes données qu'`AILayoutView` (clé `study.aiLayoutFrench`, tâches
/// `AITaskCenter`, fichiers `DocumentAITextStore`) ; elle se relit à chaque page et à chaque tâche terminée.
struct AILayoutLanguageBar: View {
    @ObservedObject var reader: ReaderController
    @ObservedObject private var center = AITaskCenter.shared
    @AppStorage("study.aiLayoutFrench") private var french = false
    @State private var markdown: String?
    @State private var hasFrench = false

    private var source: Int { reader.focusSource }
    private var translateKey: String { "translate|\(reader.document.id)|\(source)" }
    private var translating: Bool { center.isRunning(translateKey) }

    var body: some View {
        // Jamais vide : une vue vide (`Group` sans contenu) n'exécute pas son `.task`, et la barre ne se chargeait
        // jamais (recette 1.3.2 (53), point 4). Le `Color.clear` de hauteur nulle porte le chargement.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0)
            if markdown != nil { languageRow }
        }
        .task(id: "\(reader.document.id)|\(source)|\(center.finished)") {
            markdown = DocumentAITextStore.read(documentId: reader.document.id, reader: ModelSpec.ovisocr2.id, page: source)
            hasFrench = DocumentAITextStore.read(documentId: reader.document.id, reader: "fr", page: source) != nil
        }
    }

    /// Japonais / français (si traduit), ou bouton de traduction hors ligne par Qwen3-VL.
    @ViewBuilder
    private var languageRow: some View {
        if translating {
            HStack(spacing: 10) {
                ProgressView()
                Text("Qwen3-VL traduit la page… (1 à 3 min, hors ligne)").font(.footnote).foregroundStyle(Atelier.textSecondary)
            }
        } else if hasFrench {
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
        } else {
            // Sans Qwen3-VL ni traduction gardée : un message plutôt qu'une barre vide.
            Label("Traduction hors ligne : télécharge Qwen3-VL dans Réglages → Modèles d'IA et outils.",
                  systemImage: "character.bubble")
                .font(.caption)
                .foregroundStyle(Atelier.textTertiary)
        }
    }

    /// Traduction de la page (fichier gardé), même si on change de page entre-temps.
    private func translate() {
        guard let markdown else { return }
        let source = source, documentId = reader.document.id, glossary = DomainLexicon.shared.glossary
        center.run(translateKey, title: "Traduction Qwen3-VL p. \(source + 1)", modelId: ModelSpec.qwen3vl4b.id, activity: "traduction") { _ in
            let fr = try await Diagnostics.measure("traduction p. \(source)", "traduction") {
                try await Qwen3VLReader().translate(markdown: markdown, glossary: glossary)
            }
            // Arrêtée : la génération rend un texte partiel, jamais gardé.
            try Task.checkCancellation()
            try DocumentAITextStore.write(fr, documentId: documentId, reader: "fr", page: source)
            UserDefaults.standard.set(true, forKey: "study.aiLayoutFrench")
        }
    }
}
