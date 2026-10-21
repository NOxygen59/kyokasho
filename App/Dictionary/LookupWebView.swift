// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Message envoyé par la page de définitions (script de `GlossaryRenderer`).
enum LookupMessage {
    case lookup(String)
    case kanji(String)
    case audio(term: String, reading: String)
    case card(index: Int)
    /// Bloc de traduction française : translate / like / dislike / edit.
    case french(String)
}

/// Vue web des définitions. Pas de JavaScript venant des dictionnaires (seulement notre script),
/// pas de chargement réseau sauf les liens que tu touches (ouverts dans Safari).
struct LookupWebView: UIViewRepresentable {
    let html: String
    let mediaRoot: URL?
    var onMessage: (LookupMessage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onMessage: onMessage) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "kyokasho")
        if let mediaRoot {
            config.setURLSchemeHandler(MediaSchemeHandler(root: mediaRoot), forURLScheme: GlossaryRenderer.mediaScheme)
        }
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.navigationDelegate = context.coordinator
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onMessage = onMessage
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "kyokasho")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onMessage: (LookupMessage) -> Void
        var lastHTML = ""

        init(onMessage: @escaping (LookupMessage) -> Void) {
            self.onMessage = onMessage
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "lookup": if let text = body["text"] as? String { onMessage(.lookup(text)) }
            case "kanji": if let c = body["character"] as? String { onMessage(.kanji(c)) }
            case "audio": onMessage(.audio(term: body["term"] as? String ?? "", reading: body["reading"] as? String ?? ""))
            case "card": if let i = body["index"] as? Int { onMessage(.card(index: i)) }
            case "fr": if let a = body["action"] as? String { onMessage(.french(a)) }
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

/// Sert les images des dictionnaires (`kyomedia://<id>/<chemin>`) depuis le disque.
final class MediaSchemeHandler: NSObject, WKURLSchemeHandler {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let host = url.host, Int64(host) != nil else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let path = url.path.removingPercentEncoding ?? url.path
        let folder = root.appendingPathComponent(host, isDirectory: true)
        let file = folder.appendingPathComponent(path)
        guard file.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
