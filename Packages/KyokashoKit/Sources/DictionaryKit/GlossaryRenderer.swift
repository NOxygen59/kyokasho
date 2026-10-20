// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import YomitanKit

/// Rendu HTML des résultats (popup et page de recherche). Tout le texte venant des dictionnaires
/// est échappé ; le contenu structuré n'autorise qu'une liste fermée de balises et de styles.
public struct GlossaryRenderer: Sendable {
    public struct Options: Codable, Sendable, Equatable {
        public var fontSize: Double = 17
        public var showFrequencies = true
        public var showPitch = true
        public var showFurigana = true
        public var showTags = true
        public var compactGlossary = false
        public var canAddCards = false

        public init() {}
    }

    /// Schéma des images des dictionnaires (servi par l'app).
    public static let mediaScheme = "kyomedia"

    public var options: Options
    let inflectionName: @Sendable (String) -> String

    public init(options: Options = Options(), inflectionName: @escaping @Sendable (String) -> String = { $0 }) {
        self.options = options
        self.inflectionName = inflectionName
    }

    // MARK: Pages

    public func page(terms: [TermResult], dictionaries: [DictionaryInfo], query: String? = nil) -> String {
        var body = ""
        if terms.isEmpty {
            body = "<div class=\"empty\">Aucun résultat\(query.map { " pour « \(escape($0)) »" } ?? "").</div>"
        }
        for (i, term) in terms.enumerated() { body += renderTerm(term, index: i) }
        return document(body: body, dictionaries: dictionaries)
    }

    public func page(kanji: KanjiResult) -> String {
        var html = "<article class=\"kanji\"><div class=\"kanji-glyph\">\(escape(kanji.character))</div>"
        if !kanji.frequencies.isEmpty {
            html += "<div class=\"freqs\">" + kanji.frequencies.map { "<span class=\"freq\"><b>\(escape($0.dictionaryTitle))</b> \(escape($0.display))</span>" }.joined() + "</div>"
        }
        for e in kanji.entries {
            html += "<section class=\"dict\"><div class=\"dict-title\">\(escape(e.dictionaryTitle))</div>"
            if !e.onyomi.isEmpty { html += "<div class=\"readings\"><span class=\"label\">音</span>\(e.onyomi.map { "<span class=\"on\">\(escape($0))</span>" }.joined())</div>" }
            if !e.kunyomi.isEmpty { html += "<div class=\"readings\"><span class=\"label\">訓</span>\(e.kunyomi.map { "<span class=\"kun\">\(escape($0))</span>" }.joined())</div>" }
            if !e.meanings.isEmpty { html += "<ol class=\"gloss\">" + e.meanings.map { "<li>\(escape($0))</li>" }.joined() + "</ol>" }
            if !e.stats.isEmpty {
                html += "<table class=\"stats\">" + e.stats.sorted { $0.key < $1.key }.map { "<tr><th>\(escape($0.key))</th><td>\(escape($0.value))</td></tr>" }.joined() + "</table>"
            }
            html += "</section>"
        }
        html += "<div class=\"hint\">Ordre des traits : non fourni par les dictionnaires de kanji habituels.</div></article>"
        return document(body: html, dictionaries: [])
    }

    // MARK: Terme

    func renderTerm(_ t: TermResult, index: Int) -> String {
        var h = "<article class=\"term\" data-index=\"\(index)\">"
        h += "<header><div class=\"headword\" lang=\"ja\">\(headword(t))</div><div class=\"actions\">"
        h += "<button class=\"btn audio\" data-term=\"\(attr(t.expression))\" data-reading=\"\(attr(t.reading))\" title=\"Prononciation\">▶︎</button>"
        if options.canAddCards {
            h += "<button class=\"btn card\" data-index=\"\(index)\" title=\"Créer une carte\">＋</button>"
        }
        h += "</div></header>"
        if !t.inflectionRules.isEmpty {
            h += "<div class=\"inflection\"><span class=\"from\">\(escape(t.matchedText))</span> ← "
                + t.inflectionRules.map { "<span class=\"rule\">\(escape(inflectionName($0)))</span>" }.joined(separator: " ← ") + "</div>"
        }
        if options.showPitch, !t.pitches.isEmpty {
            h += "<div class=\"pitches\">" + uniquePitches(t.pitches).map { pitchHTML($0, reading: t.reading) }.joined() + "</div>"
        }
        if options.showFrequencies, !t.frequencies.isEmpty {
            h += "<div class=\"freqs\">" + t.frequencies.map { "<span class=\"freq\"><b>\(escape($0.dictionaryTitle))</b> \(escape($0.display))</span>" }.joined() + "</div>"
        }
        if !t.ipa.isEmpty {
            h += "<div class=\"ipa\">" + Array(Set(t.ipa.map(\.transcription))).sorted().map { "<span>/\(escape($0))/</span>" }.joined(separator: " ") + "</div>"
        }
        var lastDictionary = ""
        for d in t.definitions {
            if d.dictionaryTitle != lastDictionary {
                if !lastDictionary.isEmpty { h += "</section>" }
                h += "<section class=\"dict\" data-dictionary=\"\(attr(d.dictionaryTitle))\"><div class=\"dict-title\">\(escape(d.dictionaryTitle))</div>"
                lastDictionary = d.dictionaryTitle
            }
            h += "<div class=\"definition\">"
            if options.showTags {
                let tags = (d.tags + d.termTags).filter { !$0.name.isEmpty }
                if !tags.isEmpty {
                    h += "<div class=\"tags\">" + tags.map { "<span class=\"tag cat-\(attr($0.category))\" title=\"\(attr($0.notes))\">\(escape($0.name))</span>" }.joined() + "</div>"
                }
            }
            h += glossaryHTML(d.glossaryJSON, dictionaryId: d.dictionaryId)
            h += "</div>"
        }
        if !lastDictionary.isEmpty { h += "</section>" }
        return h + "</article>"
    }

    func headword(_ t: TermResult) -> String {
        let kanjiLinked = { (text: String) -> String in
            text.map { c in
                JapaneseText.isKanji(c) ? "<a class=\"k\" data-kanji=\"\(attr(String(c)))\">\(escape(String(c)))</a>" : escape(String(c))
            }.joined()
        }
        guard options.showFurigana, t.reading != t.expression else {
            return "<span class=\"expr\">\(kanjiLinked(t.expression))</span>"
                + (t.reading != t.expression ? "<span class=\"reading\">\(escape(t.reading))</span>" : "")
        }
        return JapaneseText.distributeFurigana(t.expression, t.reading).map { seg in
            seg.reading.isEmpty ? kanjiLinked(seg.text)
                : "<ruby>\(kanjiLinked(seg.text))<rt>\(escape(seg.reading))</rt></ruby>"
        }.joined()
    }

    // MARK: Accent

    func uniquePitches(_ list: [TermResult.Pitch]) -> [TermResult.Pitch] {
        var seen = Set<String>()
        return list.filter { seen.insert("\($0.downstep ?? -9)|\($0.pattern ?? "")").inserted }
    }

    /// Graphique d'accent (points hauts/bas reliés) + numéro de chute, comme Yomitan.
    func pitchHTML(_ p: TermResult.Pitch, reading: String) -> String {
        let morae = JapaneseText.morae(JapaneseText.katakanaToHiragana(reading, keepProlongedSoundMarks: true))
        guard !morae.isEmpty else { return "" }
        var highs: [Bool] = morae.indices.map { i in
            if let pattern = p.pattern, i < pattern.count { return Array(pattern)[i] == "H" }
            return JapaneseText.isMoraPitchHigh(i, downstep: p.downstep ?? 0)
        }
        // Particule suivante (point « fantôme ») : haute seulement en heiban.
        highs.append(p.pattern.map { Array($0).count > morae.count ? Array($0)[morae.count] == "H" : false }
                     ?? JapaneseText.isMoraPitchHigh(morae.count, downstep: p.downstep ?? 0))
        let step = 20.0, w = Double(highs.count) * step, top = 6.0, bottom = 22.0
        var path = ""
        var dots = ""
        for (i, high) in highs.enumerated() {
            let x = step * Double(i) + step / 2
            let y = high ? top : bottom
            path += (i == 0 ? "M" : "L") + "\(x) \(y) "
            let ghost = i == highs.count - 1
            dots += "<circle cx=\"\(x)\" cy=\"\(y)\" r=\"4\" class=\"\(ghost ? "ghost" : "dot")\"/>"
        }
        let kana = morae.map { "<span>\(escape($0))</span>" }.joined()
        let category = p.downstep.flatMap { JapaneseText.pitchCategory(reading, downstep: $0, isVerbOrAdjective: false)?.rawValue } ?? ""
        let label = p.downstep.map { "[\($0)]" } ?? (p.pattern ?? "")
        return """
            <div class="pitch"><svg width="\(Int(w))" height="28" viewBox="0 0 \(Int(w)) 28"><path d="\(path)"/>\(dots)</svg>\
            <div class="morae" style="width:\(Int(w))px">\(kana)</div><span class="pitch-num">\(escape(label)) \(escape(category))</span>\
            <span class="pitch-src">\(escape(p.dictionaryTitle))</span></div>
            """
    }

    // MARK: Glossaire

    func glossaryHTML(_ json: String, dictionaryId: Int64) -> String {
        guard let items = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]) as? [Any] else {
            return ""
        }
        let rendered = items.compactMap { item -> String? in
            switch item {
            case let s as String: return escape(s)
            case let obj as [String: Any]:
                switch obj["type"] as? String {
                case "text": return escape(obj["text"] as? String ?? "")
                case "structured-content": return structured(obj["content"] as Any, dictionaryId: dictionaryId)
                case "image": return image(obj, dictionaryId: dictionaryId)
                default: return nil
                }
            case is [Any]: return nil   // [formeDeBase, règles] : entrée de déconjugaison, non affichée
            default: return nil
            }
        }
        guard !rendered.isEmpty else { return "" }
        if rendered.count == 1 || options.compactGlossary {
            return "<div class=\"gloss single\">" + rendered.joined(separator: " ; ") + "</div>"
        }
        return "<ol class=\"gloss\">" + rendered.map { "<li>\($0)</li>" }.joined() + "</ol>"
    }

    static let allowedTags: Set<String> = ["br", "ruby", "rt", "rp", "table", "thead", "tbody", "tfoot", "tr", "td", "th",
                                           "span", "div", "ol", "ul", "li", "details", "summary", "a", "img"]
    static let allowedStyles: Set<String> = ["fontStyle", "fontWeight", "fontSize", "color", "background", "backgroundColor",
                                             "textDecorationLine", "textDecorationStyle", "textDecorationColor", "borderColor",
                                             "borderStyle", "borderRadius", "borderWidth", "clipPath", "verticalAlign",
                                             "textAlign", "textEmphasis", "textShadow", "margin", "marginTop", "marginLeft",
                                             "marginRight", "marginBottom", "padding", "paddingTop", "paddingLeft",
                                             "paddingRight", "paddingBottom", "wordBreak", "whiteSpace", "cursor", "listStyleType"]

    func structured(_ node: Any, dictionaryId: Int64) -> String {
        switch node {
        case let s as String:
            return escape(s).replacingOccurrences(of: "\n", with: "<br>")
        case let list as [Any]:
            return list.map { structured($0, dictionaryId: dictionaryId) }.joined()
        case let obj as [String: Any]:
            guard let tag = obj["tag"] as? String, Self.allowedTags.contains(tag) else {
                return structured(obj["content"] as Any, dictionaryId: dictionaryId)
            }
            if tag == "br" { return "<br>" }
            if tag == "img" { return image(obj, dictionaryId: dictionaryId) }
            var attrs = " class=\"gloss-sc-\(tag)\""
            if let data = obj["data"] as? [String: Any] {
                for (k, v) in data {
                    let key = k.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }.map(String.init).joined()
                    attrs += " data-sc-\(key)=\"\(attr("\(v)"))\""
                }
            }
            if let style = obj["style"] as? [String: Any] {
                let css = style.compactMap { k, v -> String? in
                    guard Self.allowedStyles.contains(k) else { return nil }
                    let value = (v as? [Any]).map { $0.map { "\($0)" }.joined(separator: " ") } ?? "\(v)"
                    guard !value.contains(where: { "<>{};\"\\".contains($0) }) else { return nil }
                    let suffix = (v is NSNumber && !["fontWeight"].contains(k)) ? "em" : ""
                    return "\(kebab(k)):\(value)\(suffix)"
                }.joined(separator: ";")
                if !css.isEmpty { attrs += " style=\"\(attr(css))\"" }
            }
            for key in ["colSpan", "rowSpan"] {
                if let n = obj[key] as? Int { attrs += " \(key.lowercased())=\"\(n)\"" }
            }
            if let lang = obj["lang"] as? String { attrs += " lang=\"\(attr(lang))\"" }
            if tag == "a", let href = obj["href"] as? String {
                // Liens internes Yomitan « ?query=… » → nouvelle recherche ; liens externes → Safari.
                if href.hasPrefix("?"), let q = URLComponents(string: "x://x" + href)?.queryItems?.first(where: { $0.name == "query" })?.value {
                    attrs += " data-query=\"\(attr(q))\" href=\"#\""
                } else if href.hasPrefix("http") {
                    attrs += " href=\"\(attr(href))\" target=\"_blank\""
                }
            }
            if tag == "details", obj["open"] as? Bool == true { attrs += " open" }
            return "<\(tag)\(attrs)>\(structured(obj["content"] as Any, dictionaryId: dictionaryId))</\(tag)>"
        default:
            return ""
        }
    }

    func image(_ obj: [String: Any], dictionaryId: Int64) -> String {
        guard let path = obj["path"] as? String, !path.contains("..") else { return "" }
        var style = ""
        if let w = obj["width"] as? Double { style += "width:\(w)\((obj["sizeUnits"] as? String) == "em" ? "em" : "px");" }
        if let h = obj["height"] as? Double { style += "height:\(h)\((obj["sizeUnits"] as? String) == "em" ? "em" : "px");" }
        if obj["pixelated"] as? Bool == true || (obj["imageRendering"] as? String) == "pixelated" { style += "image-rendering:pixelated;" }
        if (obj["appearance"] as? String) == "monochrome" { style += "filter:invert(1);" }
        let encoded = path.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        let title = (obj["title"] as? String).map { " title=\"\(attr($0))\"" } ?? ""
        return "<img class=\"gloss-img\" src=\"\(Self.mediaScheme)://\(dictionaryId)/\(encoded)\" style=\"\(attr(style))\"\(title) loading=\"lazy\">"
    }

    // MARK: Document

    func document(body: String, dictionaries: [DictionaryInfo]) -> String {
        let styles = dictionaries.compactMap { d -> String? in
            guard let css = d.styles, !css.isEmpty else { return nil }
            return Self.scopeCSS(css, dictionary: d.title)
        }.joined(separator: "\n")
        return """
            <!doctype html><html lang="ja"><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
            <style>\(Self.baseCSS.replacingOccurrences(of: "FONTSIZE", with: String(options.fontSize)))</style>
            <style>\(styles)</style></head><body>\(body)<script>\(Self.script)</script></body></html>
            """
    }

    /// Préfixe chaque sélecteur du CSS d'un dictionnaire pour qu'il ne touche que ses définitions.
    static func scopeCSS(_ css: String, dictionary: String) -> String {
        let prefix = "[data-dictionary=\"\(dictionary.replacingOccurrences(of: "\"", with: "\\\""))\"]"
        var out = ""
        for block in css.components(separatedBy: "}") {
            guard let brace = block.firstIndex(of: "{") else { continue }
            let selectors = block[..<brace].trimmingCharacters(in: .whitespacesAndNewlines)
            let rules = block[block.index(after: brace)...]
            guard !selectors.hasPrefix("@"), !rules.contains("url(") else { continue }
            let scoped = selectors.split(separator: ",").map { "\(prefix) \($0.trimmingCharacters(in: .whitespaces))" }.joined(separator: ",")
            out += "\(scoped){\(rules)}\n"
        }
        return out
    }

    static let baseCSS = """
        :root{color-scheme:dark;--fg:rgba(255,255,255,.94);--fg2:rgba(255,255,255,.58);--fg3:rgba(255,255,255,.36);
        --bg:#1b1d22;--bg2:#262931;--line:rgba(255,255,255,.08);--jp:#ff6154;--read:#4fd1c4;--ann:#f7ba3b;--ai:#9e8fff}
        *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
        body{margin:0;padding:14px 16px 40px;background:var(--bg);color:var(--fg);font:FONTSIZEpx/1.55 -apple-system,"Hiragino Sans",sans-serif;-webkit-text-size-adjust:none}
        article.term{padding:12px 0 16px;border-bottom:1px solid var(--line)}
        article.term:last-child{border-bottom:none}
        header{display:flex;align-items:flex-start;justify-content:space-between;gap:10px}
        .headword{font-size:1.75em;line-height:1.5;font-family:"Hiragino Mincho ProN","Hiragino Sans",serif}
        .headword rt{font-size:.42em;color:var(--fg2);font-family:"Hiragino Sans",sans-serif}
        .headword .reading{font-size:.6em;color:var(--fg2);margin-left:10px}
        a.k{color:inherit;text-decoration:none;border-bottom:1px dotted var(--fg3)}
        .actions{display:flex;gap:6px;padding-top:6px}
        .btn{border:none;border-radius:9px;background:var(--bg2);color:var(--fg);width:34px;height:34px;font-size:15px}
        .btn.card{background:var(--ann);color:#111;font-weight:700}
        .btn.playing{background:var(--read);color:#111}
        .inflection{font-size:.8em;color:var(--fg2);margin:2px 0 6px}
        .inflection .from{color:var(--jp)}
        .inflection .rule{background:var(--bg2);border-radius:6px;padding:1px 6px}
        .freqs{display:flex;flex-wrap:wrap;gap:6px;margin:6px 0}
        .freq{font-size:.72em;background:var(--bg2);border-radius:999px;padding:2px 9px;color:var(--fg2)}
        .freq b{color:var(--read);font-weight:600;margin-right:4px}
        .pitches{display:flex;flex-wrap:wrap;gap:14px;margin:6px 0}
        .pitch{position:relative;display:flex;flex-direction:column;gap:0;font-size:.75em;color:var(--fg2)}
        .pitch svg path{fill:none;stroke:var(--jp);stroke-width:1.6}
        .pitch svg .dot{fill:var(--jp)} .pitch svg .ghost{fill:var(--bg);stroke:var(--jp);stroke-width:1.4}
        .pitch .morae{display:flex;justify-content:space-around} .pitch .morae span{width:20px;text-align:center}
        .pitch-num{color:var(--fg)} .pitch-src{color:var(--fg3);font-size:.85em}
        .ipa{font-size:.8em;color:var(--fg2)}
        section.dict{margin-top:10px}
        .dict-title{font:600 10.5px/1.4 -apple-system;letter-spacing:.12em;text-transform:uppercase;color:var(--fg3);margin-bottom:4px}
        .definition{margin:4px 0 8px}
        .tags{display:flex;flex-wrap:wrap;gap:4px;margin-bottom:3px}
        .tag{font-size:.68em;border-radius:5px;padding:1px 6px;background:#3a3f4b;color:var(--fg)}
        .tag.cat-partOfSpeech{background:#2d4f4b} .tag.cat-popular{background:#5a3a2b} .tag.cat-frequent{background:#5a3a2b}
        .tag.cat-archaism,.tag.cat-dictionary{background:#3b3553}
        ol.gloss{margin:2px 0;padding-left:1.3em} ol.gloss li{margin:2px 0}
        .gloss.single{margin:2px 0}
        .gloss-sc-table{border-collapse:collapse;margin:4px 0} .gloss-sc-td,.gloss-sc-th{border:1px solid var(--line);padding:2px 6px}
        .gloss-img{max-width:100%;vertical-align:middle;border-radius:4px}
        details summary{color:var(--fg2)}
        a{color:var(--read)}
        .kanji-glyph{font:5.5em/1.1 "Hiragino Mincho ProN",serif;text-align:center;margin:6px 0 10px}
        .readings{margin:4px 0} .readings .label{display:inline-block;width:1.6em;color:var(--jp);font-weight:700}
        .readings .on,.readings .kun{margin-right:10px} table.stats{font-size:.8em;color:var(--fg2);margin-top:6px} table.stats th{text-align:left;padding-right:12px}
        .hint{font-size:.72em;color:var(--fg3);margin-top:14px}
        .empty{color:var(--fg2);padding:20px 0;text-align:center}
        .tapped{background:rgba(255,97,84,.35);border-radius:3px}
        """

    /// Toucher un mot dans une définition → nouvelle recherche (popup imbriqué) ; kanji → fiche ;
    /// ▶︎ → audio ; ＋ → carte.
    static let script = """
        (function(){
        const post=(m)=>window.webkit&&window.webkit.messageHandlers.kyokasho&&window.webkit.messageHandlers.kyokasho.postMessage(m);
        function textAfter(node,offset,max){
          let out=node.textContent.slice(offset);
          const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,{acceptNode:(n)=>{
            let p=n.parentElement;while(p){if(p.tagName==='RT'||p.tagName==='RP'||p.tagName==='SCRIPT'||p.tagName==='STYLE'||p.tagName==='BUTTON')return NodeFilter.FILTER_REJECT;p=p.parentElement}
            return NodeFilter.FILTER_ACCEPT}});
          walker.currentNode=node;
          while(out.length<max){const n=walker.nextNode();if(!n)break;if(n.parentElement&&getComputedStyle(n.parentElement).display==='block'&&out.length>0)break;out+=n.textContent}
          return out.slice(0,max);
        }
        document.addEventListener('click',function(e){
          const t=e.target;
          const audio=t.closest('.audio');if(audio){post({type:'audio',term:audio.dataset.term,reading:audio.dataset.reading});audio.classList.add('playing');setTimeout(()=>audio.classList.remove('playing'),900);return}
          const card=t.closest('.card');if(card){post({type:'card',index:parseInt(card.dataset.index)});card.textContent='✓';return}
          const k=t.closest('[data-kanji]');if(k){post({type:'kanji',character:k.dataset.kanji});return}
          const q=t.closest('[data-query]');if(q){e.preventDefault();post({type:'lookup',text:q.dataset.query,x:e.clientX,y:e.clientY});return}
          if(t.closest('a[href^=http]'))return;
          const r=document.caretRangeFromPoint(e.clientX,e.clientY);
          if(!r||r.startContainer.nodeType!==3)return;
          let p=r.startContainer.parentElement;while(p){if(p.tagName==='RT')return;p=p.parentElement}
          const text=textAfter(r.startContainer,r.startOffset,20);
          if(!text.trim())return;
          document.querySelectorAll('.tapped').forEach(n=>{n.replaceWith(document.createTextNode(n.textContent))});
          try{const rr=document.createRange();rr.setStart(r.startContainer,r.startOffset);rr.setEnd(r.startContainer,Math.min(r.startOffset+1,r.startContainer.length));const s=document.createElement('span');s.className='tapped';rr.surroundContents(s)}catch(_){}
          post({type:'lookup',text:text,x:e.clientX,y:e.clientY});
        });
        })();
        """

    // MARK: Échappement

    func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }

    func attr(_ s: String) -> String { escape(s).replacingOccurrences(of: "'", with: "&#39;") }

    func kebab(_ s: String) -> String {
        var out = ""
        for c in s { if c.isUppercase { out += "-" + c.lowercased() } else { out.append(c) } }
        return out
    }
}
