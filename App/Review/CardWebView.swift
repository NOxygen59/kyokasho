// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// HTML d'une face de carte : CSS du modèle, médias servis par `kyocard:///nom`, `[sound:x]` → bouton ▶︎.
enum CardHTML {
    static let scheme = "kyocard"

    // FDR-4 : couleurs du thème (`Theme.current`) comme `FuriganaTextView.page` (hexString). Voir § 6 étape 4.
    static func page(css: String, body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>
        html,body{margin:0;padding:0;background:#16181c;-webkit-text-size-adjust:none;-webkit-user-select:none}
        .snd{display:inline-block;border:none;border-radius:50%;width:38px;height:38px;margin:6px;font-size:16px;
          background:#22262c;color:#ff6f59;cursor:pointer}
        \(css)
        </style></head><body><div class="card">\(rewrite(body))</div>
        <script>
        document.addEventListener('click',function(e){
          var s=e.target.closest('.snd');
          if(s){window.webkit.messageHandlers.card.postMessage({type:'sound',name:s.dataset.name});e.stopPropagation();return}
          if(e.target.closest('a'))return;
          window.webkit.messageHandlers.card.postMessage({type:'tap'});
        });
        </script></body></html>
        """
    }

    /// Noms des sons cités (`[sound:x]`), dans l'ordre.
    static func sounds(in html: String) -> [String] {
        var out: [String] = []
        var rest = html[...]
        while let p = rest.range(of: "[sound:") {
            rest = rest[p.upperBound...]
            guard let e = rest.firstIndex(of: "]") else { break }
            out.append(String(rest[..<e]))
            rest = rest[rest.index(after: e)...]
        }
        return out
    }

    static func rewrite(_ html: String) -> String {
        var s = html
        for name in sounds(in: html) {
            let safe = name.replacingOccurrences(of: "\"", with: "")
            s = s.replacingOccurrences(of: "[sound:\(name)]",
                                       with: "<button class=\"snd\" data-name=\"\(safe)\">▶︎</button>")
        }
        // src="nom" (fichier du dossier média) → kyocard:///nom ; les URL complètes ne changent pas.
        var out = ""
        var rest = s[...]
        while let p = rest.range(of: "src=\"") {
            out += rest[..<p.upperBound]
            rest = rest[p.upperBound...]
            guard let e = rest.firstIndex(of: "\"") else { break }
            let value = String(rest[..<e])
            out += value.contains(":") || value.hasPrefix("/") ? value : "\(scheme):///\(value)"
            rest = rest[e...]
        }
        return out + rest
    }
}

/// Vue web d'une carte. Toucher la carte → `onTap` ; ▶︎ → lecture du son.
struct CardWebView: UIViewRepresentable {
    let html: String
    let mediaRoot: URL
    /// Sons joués à l'affichage (comme Anki).
    var autoplay: [String] = []
    var onTap: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(mediaRoot: mediaRoot, onTap: onTap) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "card")
        config.setURLSchemeHandler(CardMediaHandler(root: mediaRoot), forURLScheme: CardHTML.scheme)
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.navigationDelegate = context.coordinator
        load(view, context: context)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onTap = onTap
        if context.coordinator.lastHTML != html { load(view, context: context) }
    }

    private func load(_ view: WKWebView, context: Context) {
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: nil)
        if let first = autoplay.first { context.coordinator.play(first) }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "card")
        coordinator.player?.stop()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let mediaRoot: URL
        var onTap: () -> Void
        var lastHTML = ""
        var player: AVAudioPlayer?

        init(mediaRoot: URL, onTap: @escaping () -> Void) {
            self.mediaRoot = mediaRoot
            self.onTap = onTap
        }

        func play(_ name: String) {
            guard !name.contains("/"), let data = try? Data(contentsOf: mediaRoot.appendingPathComponent(name)) else { return }
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            player = try? AVAudioPlayer(data: data)
            player?.play()
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "tap": onTap()
            case "sound": if let name = body["name"] as? String { play(name) }
            default: break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, ["http", "https"].contains(url.scheme ?? ""), action.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// Sert les fichiers du dossier média des cartes (`kyocard:///nom`), noms plats seulement.
final class CardMediaHandler: NSObject, WKURLSchemeHandler {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        let name = (url.path.removingPercentEncoding ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix("."),
              let data = try? Data(contentsOf: root.appendingPathComponent(name)) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let mime = UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
