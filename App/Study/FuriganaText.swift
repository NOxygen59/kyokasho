// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import OCRKit
import ReaderCore
import SwiftUI
import WebKit

/// Lectures d'un texte : mots reconnus par le dictionnaire Yomitan installé (lecture du dictionnaire,
/// posée sur les kanji du mot), sinon l'analyseur japonais du système.
enum TextFurigana {
    // FDR-N : comparer la lecture MeCab et celle du dictionnaire Yomitan ; désaccord → lecture du dictionnaire + marque « doute ». Voir § 6 Fiabilité N.
    static func rubies(_ text: String, segments: [Translator.Segment]) -> [(range: Range<Int>, reading: String)] {
        // MeCab installé : lectures selon le contexte (plus justes que la forme de base du dictionnaire).
        if Furigana.analyzer != nil { return Furigana.rubies(for: text).map { ($0.range, $0.reading) } }
        // Les segments doivent recouvrir le texte tel quel ; sinon, analyseur du système pour tout.
        guard !segments.isEmpty, segments.map(\.text).joined() == text else {
            return Furigana.rubies(for: text).map { ($0.range, $0.reading) }
        }
        var out: [(Range<Int>, String)] = []
        var offset = 0
        for segment in segments {
            let length = segment.text.count
            defer { offset += length }
            guard segment.text.contains(where: Furigana.isKanji) else { continue }
            if let term = segment.term, let mapped = dictionaryRubies(surface: segment.text, term: term) {
                out += mapped.map { ($0.0.lowerBound + offset ..< $0.0.upperBound + offset, $0.1) }
            } else {
                out += Furigana.rubies(for: segment.text).map { ($0.range.lowerBound + offset ..< $0.range.upperBound + offset, $0.reading) }
            }
        }
        return out
    }

    /// Lecture du dictionnaire (forme de base : 読む【よむ】) reportée sur le mot du texte (読んだ) :
    /// mêmes groupes de kanji dans le même ordre, sinon `nil`.
    static func dictionaryRubies(surface: String, term: TermResult) -> [(Range<Int>, String)]? {
        let reading = term.reading.applyingTransform(.hiraganaToKatakana, reverse: true) ?? term.reading
        guard !reading.isEmpty else { return nil }
        let base = Furigana.align(term.expression, reading)
        let baseChars = Array(term.expression)
        let groups = kanjiGroups(Array(surface))
        guard base.count == groups.count, !groups.isEmpty, base.allSatisfy({ $0.0.upperBound <= baseChars.count }),
              zip(base, groups).allSatisfy({ String(baseChars[$0.0]) == String(Array(surface)[$1]) }) else { return nil }
        return zip(base, groups).map { ($1, $0.1) }
    }

    static func kanjiGroups(_ chars: [Character]) -> [Range<Int>] {
        var groups: [Range<Int>] = []
        var start: Int?
        for (i, c) in chars.enumerated() {
            if Furigana.isKanji(c) { if start == nil { start = i } } else if let s = start { groups.append(s..<i); start = nil }
        }
        if let s = start { groups.append(s..<chars.count) }
        return groups
    }
}

/// Événement de la vue web du texte OCR vers la bulle du dictionnaire (Issue #13).
enum PanelLookupEvent {
    /// Mot touché/cliqué (`hover == false`) ou survolé avec Maj (`hover == true`). `wordRect` en coordonnées
    /// de la fenêtre (comme `.global` en SwiftUI).
    case open(text: String, wordRect: CGRect, hover: Bool)
    /// Le pointeur a quitté le mot survolé avec Maj (ou Maj n'est plus tenue pendant le mouvement).
    case hoverEnd
    /// Toucher ou clic hors d'un mot dans le texte.
    case tapOutside
}

/// Texte extrait avec furigana ; un appui sur un caractère ouvre le dictionnaire à partir de là.
struct FuriganaTextView: View {
    let page: OCRPage
    let formatted: Bool
    var regions: [OCRLayout.Region] = []
    var hoverReset = 0
    var onLookup: (PanelLookupEvent) -> Void
    @EnvironmentObject private var dictionary: DictionaryModel
    @State private var html = ""
    @AppStorage(FuriganaLayer.Tint.storageKey) private var tint = FuriganaLayer.Tint.red
    @ObservedObject private var morphology = MorphologyService.shared
    @State private var height: CGFloat = 200

    /// Unités de texte : titres, paragraphes, cellules (mis en forme) ou lignes (brut).
    private var units: [(tag: String, text: String, row: Int?)] {
        guard formatted else { return page.lines.map { ("p", $0.text, nil) } }
        if Self.isVertical(page) {
            // Une colonne par ligne OCR ; le mode mis en forme suit l'ordre japonais, de droite à gauche.
            return page.lines.sorted { a, b in
                abs(a.box.x - b.box.x) > 0.01 ? a.box.x > b.box.x : a.box.y < b.box.y
            }.map { ("p", $0.text, nil) }
        }
        return formattedUnits
    }

    private var formattedUnits: [(tag: String, text: String, row: Int?)] {
        var out: [(String, String, Int?)] = []
        let blocks = regions.isEmpty ? OCRLayout.blocks(page) : OCRLayout.blocks(page, regions: regions)
        for (b, block) in blocks.enumerated() {
            switch block {
            case .heading(let level, let text): out.append(("h\(level + 1)", text, nil))
            case .paragraph(let text): out.append(("p", text, nil))
            case .table(let rows):
                for (r, row) in rows.enumerated() { for cell in row { out.append(("td", cell, b * 1000 + r)) } }
            }
        }
        return out
    }

    var body: some View {
        RubyWebView(html: html, height: $height, hoverReset: hoverReset, onLookup: onLookup)
            .frame(height: height)
            .modifier(OCRScrollDiagnostics())
            .task(id: "\(page.hashValue)|\(formatted)|\(regions.hashValue)|\(tint.rawValue)|\(morphology.state == .ready)") { await build() }
    }

    private func build() async {
        var body = ""
        var openRow: Int?
        for (u, unit) in units.enumerated() {
            guard !Task.isCancelled else { return }
            // Brut : une unité = une ligne OCR, ses caractères douteux sont soulignés.
            let doubt = formatted ? [] : Set(page.lines[u].doubt ?? [])
            let segments = await dictionary.segment(unit.text)
            let rubies = TextFurigana.rubies(unit.text, segments: segments)
            let inner = Self.markup(unit.text, rubies: rubies, wordStarts: Self.wordStarts(unit.text, segments: segments), doubt: doubt)
            if unit.tag == "td" {
                if openRow != unit.row { body += (openRow == nil ? "<table>" : "</tr>") + "<tr>"; openRow = unit.row }
                body += "<td>\(inner)</td>"
            } else {
                if openRow != nil { body += "</tr></table>"; openRow = nil }
                body += "<\(unit.tag)>\(inner)</\(unit.tag)>"
            }
        }
        if openRow != nil { body += "</tr></table>" }
        // Construction remplacée entre-temps (autre page, autre affichage) : on n'écrase pas la nouvelle.
        guard !Task.isCancelled else { return }
        html = Self.page(body, vertical: Self.isVertical(page))
    }

    /// Pour chaque caractère, début du mot du dictionnaire qui le contient (segments de `Translator.segment`) :
    /// toucher 井 dans 天井 cherche 天井, pas 井. Sans mot trouvé : le caractère lui-même.
    static func wordStarts(_ text: String, segments: [Translator.Segment]) -> [Int]? {
        guard !segments.isEmpty, segments.map(\.text).joined() == text else { return nil }
        var starts: [Int] = []
        for segment in segments {
            let first = starts.count
            for k in 0..<segment.text.count { starts.append(segment.term == nil ? first + k : first) }
        }
        return starts
    }

    /// Chaque caractère dans un `<span data-q>` (texte à chercher à partir du début de son mot, calculé ici :
    /// pas de calcul d'index en JavaScript, qui compte autrement les caractères composés) ; kanji avec lecture
    /// dans `<ruby>`.
    static func markup(_ text: String, rubies: [(range: Range<Int>, reading: String)], wordStarts: [Int]? = nil,
                       doubt: Set<Int> = []) -> String {
        let chars = Array(text)
        func span(_ i: Int) -> String {
            let from = wordStarts.flatMap { $0.count == chars.count ? $0[i] : nil } ?? i
            return "<span\(doubt.contains(i) ? " class=\"doubt\"" : "") data-q=\"\(escape(String(chars[from..<min(chars.count, from + 24)])))\">\(escape(String(chars[i])))</span>"
        }
        var starts: [Int: (Range<Int>, String)] = [:]
        for r in rubies where r.range.upperBound <= chars.count && !r.range.isEmpty { starts[r.range.lowerBound] = (r.range, r.reading) }
        var out = ""
        var i = 0
        while i < chars.count {
            if let (range, reading) = starts[i] {
                out += "<ruby>" + range.map(span).joined()
                    + "<rt>\(escape(reading))</rt></ruby>"
                i = range.upperBound
            } else {
                out += span(i)
                i += 1
            }
        }
        return out
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func isVertical(_ page: OCRPage) -> Bool {
        let vertical = page.lines.filter(\.vertical).reduce(0) { $0 + $1.text.count }
        let horizontal = page.lines.filter { !$0.vertical }.reduce(0) { $0 + $1.text.count }
        return vertical > horizontal && vertical > 0
    }

    static func page(_ body: String, vertical: Bool = false) -> String {
        let text = UIColor(Atelier.textPrimary).hexString, accent = UIColor(Atelier.Tint.japanese).hexString
        let line = UIColor(Atelier.hairline).hexString
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,minimum-scale=1,maximum-scale=5,user-scalable=yes">
        <style>
        html,body{margin:0;background:transparent;color:\(text);font:17px/2.1 "Hiragino Mincho ProN",serif;-webkit-user-select:none}
        body.vertical{writing-mode:vertical-rl;text-orientation:mixed;height:460px;max-width:100%;overflow-x:auto;overflow-y:hidden}
        body.vertical ruby{ruby-position:over}
        p,h2,h3,td{margin:0 0 .6em} h2{font-size:1.35em} h3{font-size:1.15em}
        table{border-collapse:collapse;margin:.4em 0 .8em} td{border:1px solid \(line);padding:2px 8px}
        rt{font-size:.5em;color:\(FuriganaLayer.Tint.current.panelHex)} span[data-q]{cursor:pointer} span.hit{background:\(accent)55;border-radius:3px}
        span.doubt{text-decoration:underline solid #ff9f0a;background:#ff9f0a2e}
        </style></head><body\(vertical ? " class=\"vertical\"" : "")>\(body)
        <script>
        function size(){window.webkit.messageHandlers.kyokasho.postMessage({type:'height',value:document.body.scrollHeight})}
        window.onload=size; new ResizeObserver(size).observe(document.body);
        \(RubyWebView.lookupEventsScript)
        </script></body></html>
        """
    }
}

/// Vue web du texte à furigana : hauteur suivie (pour s'insérer dans le panneau), appuis → dictionnaire.
struct RubyWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    /// Change quand la bulle se ferme : l'état de survol JavaScript est alors remis à zéro.
    var hoverReset = 0
    var onLookup: (PanelLookupEvent) -> Void
    @AppStorage(Diagnostics.enabledKey) private var diagnosticsEnabled = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "kyokasho")
        context.coordinator.controller = config.userContentController
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.navigationDelegate = context.coordinator
        Diagnostics.log("Création du texte web OCR", "ocr-scroll")
        // Se déplacer dans le texte (tableaux larges, texte zoomé) : glisser à l'horizontale ou, zoomé, partout.
        // Pas zoomé, la hauteur suit le contenu : un glisser vertical fait défiler la fenêtre OCR, pas le texte.
        let scroll = view.scrollView
        scroll.isScrollEnabled = true
        // Déplacement libre dans toutes les directions ; pincer de 1× à 5×.
        scroll.isDirectionalLockEnabled = false
        scroll.alwaysBounceVertical = false
        scroll.alwaysBounceHorizontal = false
        scroll.bounces = true
        scroll.bouncesZoom = true
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.contentInsetAdjustmentBehavior = .never
        context.coordinator.setDiagnostics(view, enabled: diagnosticsEnabled)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.diagnosticsEnabled != diagnosticsEnabled {
            context.coordinator.setDiagnostics(view, enabled: diagnosticsEnabled)
        }
        if context.coordinator.lastHoverReset != hoverReset {
            context.coordinator.lastHoverReset = hoverReset
            view.evaluateJavaScript("window.__kyokashoResetHover&&window.__kyokashoResetHover()", completionHandler: nil)
        }
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        Diagnostics.log("Chargement HTML OCR : \(html.utf8.count) octets", "ocr-scroll")
        view.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        // Le contrôleur gardé à la création (pas une copie) : le gestionnaire est bien retiré.
        coordinator.controller?.removeScriptMessageHandler(forName: "kyokasho")
        coordinator.setDiagnostics(view, enabled: false)
        view.navigationDelegate = nil
    }

    /// Événements du dictionnaire dans le texte OCR (Issue #13), testés par `scripts/test_ocr_lookup_events.cjs`.
    /// Clic ou toucher explicite (un défilement ne produit pas de « click ») ; hors d'un mot, `tapOutside`.
    /// Souris seulement : survol avec Maj tenue, sans bouton appuyé. `window.__kyokashoResetHover()` est appelé
    /// par Swift quand la bulle se ferme (Maj relâchée, pointeur sorti) : sans cela, `hovered` restait sur le mot
    /// et le même mot ne rouvrait plus la bulle (revue de Codex sur #57).
    static let lookupEventsScript = """
    function post(m){window.webkit.messageHandlers.kyokasho.postMessage(m)}
    function hit(s){document.querySelectorAll('span.hit').forEach(function(x){x.classList.remove('hit')}); if(s){s.classList.add('hit')}}
    function open(s,hover){var r=s.getBoundingClientRect(); hit(s);
      post({type:'lookup',text:s.dataset.q,hover:hover,rect:{x:r.left,y:r.top,w:r.width,h:r.height}})}
    document.addEventListener('click',function(e){
      var s=e.target.closest('span[data-q]'); if(!s){hit(null); post({type:'tapOutside'}); return}
      open(s,false);
    });
    var hovered=null;
    function endHover(){if(hovered){hovered=null; hit(null); post({type:'hoverEnd'})}}
    window.__kyokashoResetHover=function(){hovered=null; hit(null)};
    document.addEventListener('mousemove',function(e){
      if(e.buttons){return}
      var s=e.target.closest?e.target.closest('span[data-q]'):null;
      if(e.shiftKey&&s){if(s!==hovered){hovered=s; open(s,true)}} else {endHover()}
    },{passive:true});
    document.addEventListener('mouseleave',endHover);
    """

    /// Événements horodatés et bornés, sans contenu du document. L'écart JS→natif mesure aussi le pont.
    private static let scrollDiagnosticScript = """
    (function() {
      if (window.__kyokashoRemoveScrollDiagnostic) return;
      var last = {}, listeners = {};
      ['wheel','touchstart','touchmove','scroll'].forEach(function(kind) {
        listeners[kind] = function() {
          var now = Date.now();
          if (now - (last[kind] || 0) < 500) return;
          last[kind] = now;
          window.webkit.messageHandlers.kyokasho.postMessage({type:'scrollDiagnostic',kind:kind,time:now});
        };
        document.addEventListener(kind, listeners[kind], {capture:true,passive:true});
      });
      window.__kyokashoRemoveScrollDiagnostic = function() {
        Object.keys(listeners).forEach(function(kind) {
          document.removeEventListener(kind, listeners[kind], true);
        });
        delete window.__kyokashoRemoveScrollDiagnostic;
      };
    })();
    """

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: RubyWebView
        var lastHTML = ""
        var lastHoverReset = 0
        weak var controller: WKUserContentController?
        var offsetObservation: NSKeyValueObservation?
        var diagnosticsEnabled = false
        private var lastNativeScroll = Date.distantPast

        func setDiagnostics(_ view: WKWebView, enabled: Bool) {
            guard diagnosticsEnabled != enabled else { return }
            diagnosticsEnabled = enabled
            if enabled {
                controller?.addUserScript(WKUserScript(source: RubyWebView.scrollDiagnosticScript,
                                                       injectionTime: .atDocumentEnd, forMainFrameOnly: true))
                offsetObservation = view.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                    self?.traceNativeScroll(scroll)
                }
                lastNativeScroll = .distantPast
                view.evaluateJavaScript(RubyWebView.scrollDiagnosticScript, completionHandler: nil)
            } else {
                // Ce contrôleur ne possède que le script de diagnostic ; le pont lookup reste installé.
                controller?.removeAllUserScripts()
                offsetObservation?.invalidate()
                offsetObservation = nil
                removeScrollListeners(view)
            }
        }

        private func removeScrollListeners(_ view: WKWebView) {
            view.evaluateJavaScript("window.__kyokashoRemoveScrollDiagnostic?.();", completionHandler: nil)
        }

        func traceNativeScroll(_ scroll: UIScrollView) {
            guard diagnosticsEnabled, Date().timeIntervalSince(lastNativeScroll) >= 0.5 else { return }
            lastNativeScroll = Date()
            Diagnostics.log("Défilement natif web : x=\(Int(scroll.contentOffset.x)), y=\(Int(scroll.contentOffset.y)), zoom=\(scroll.zoomScale)", "ocr-scroll")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            setDiagnostics(webView, enabled: parent.diagnosticsEnabled)
            if diagnosticsEnabled {
                webView.evaluateJavaScript(RubyWebView.scrollDiagnosticScript, completionHandler: nil)
            } else {
                // Retire aussi une injection déjà programmée avant une désactivation pendant le chargement.
                removeScrollListeners(webView)
            }
            Diagnostics.log("HTML OCR prêt", "ocr-scroll")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Diagnostics.log("Processus HTML OCR terminé", "ocr-scroll")
        }

        init(_ parent: RubyWebView) { self.parent = parent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "scrollDiagnostic":
                guard Diagnostics.enabled, let kind = body["kind"] as? String,
                      ["wheel", "touchstart", "touchmove", "scroll"].contains(kind),
                      let time = body["time"] as? Double, time.isFinite else { return }
                let delay = Date().timeIntervalSince1970 * 1000 - time
                Diagnostics.log("Événement HTML \(kind), délai pont=\(Int(delay)) ms", "ocr-scroll")
            case "height":
                if let value = body["value"] as? Double, abs(CGFloat(value) - parent.height) > 1 { parent.height = CGFloat(value) }
            case "lookup":
                guard let text = body["text"] as? String, !text.isEmpty else { return }
                // Rectangle CSS du mot → points de la vue web (zoom du pincement) → coordonnées de la fenêtre.
                var wordRect = CGRect.zero
                if let r = body["rect"] as? [String: Double], let web = message.webView {
                    let z = web.scrollView.zoomScale
                    let local = CGRect(x: (r["x"] ?? 0) * z, y: (r["y"] ?? 0) * z, width: (r["w"] ?? 0) * z, height: (r["h"] ?? 0) * z)
                    wordRect = web.convert(local, to: nil)
                }
                parent.onLookup(.open(text: text, wordRect: wordRect, hover: body["hover"] as? Bool ?? false))
            case "hoverEnd":
                parent.onLookup(.hoverEnd)
            case "tapOutside":
                parent.onLookup(.tapOutside)
            default: break
            }
        }
    }
}

/// Position du contenu web dans la fenêtre : distingue le déplacement du conteneur SwiftUI du scroll HTML.
private struct OCRScrollPositionKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct OCRScrollDiagnostics: ViewModifier {
    @AppStorage(Diagnostics.enabledKey) private var enabled = false
    @State private var lastEvent = Date.distantPast

    func body(content: Content) -> some View {
        content.background {
            if enabled {
                GeometryReader { proxy in
                    Color.clear.preference(key: OCRScrollPositionKey.self, value: proxy.frame(in: .global).minY)
                }
            }
        }
        .onPreferenceChange(OCRScrollPositionKey.self) { y in
            guard enabled, Date().timeIntervalSince(lastEvent) >= 0.5 else { return }
            lastEvent = Date()
            Diagnostics.log("Position conteneur OCR : y=\(Int(y))", "ocr-scroll")
        }
    }
}

extension UIColor {
    /// `#rrggbb` (couleur du thème, pour le CSS).
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
