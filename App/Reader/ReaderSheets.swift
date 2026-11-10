// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PDFKit
import ReaderCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Recherche

struct SearchSheet: View {
    @ObservedObject var reader: ReaderController
    /// Fermeture explicite : `close()` avec une recherche active peut fermer aussi le lecteur.
    var close: () -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if reader.isSearching && reader.searchResults.isEmpty {
                    HStack { ProgressView(); Text("Recherche…").foregroundStyle(.secondary) }
                } else if !query.isEmpty && reader.searchResults.isEmpty && !reader.isSearching {
                    Text("Aucun résultat.").foregroundStyle(.secondary)
                }
                ForEach(reader.searchResults) { result in
                    Button {
                        reader.show(result)
                        close()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Page \(reader.document.pageLabel(result.sourcePage))").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(result.context).lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: String(localized: "Mot ou phrase"))
            .onSubmit(of: .search) { reader.search(query) }
            .onChange(of: query) { if $0.isEmpty { reader.search("") } }
            .navigationTitle(reader.searchResults.isEmpty ? String(localized: "Rechercher") : String(localized: "\(reader.searchResults.count) résultat(s)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { close() } } }
        }
    }
}

// MARK: - Page vers IA

struct AIPageSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var reader: ReaderController
    var openWeb: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var prompts: [AIPrompt] = []
    @State private var copied: String?
    @State private var editingPrompt: AIPrompt?
    /// Double page : pages envoyées (une des deux, ou les deux côte à côte).
    @State private var chosen: [Int] = []

    private var pageTitle: String {
        let labels = chosen.map { reader.document.pageLabel($0) }
        return labels.count > 1 ? String(localized: "Pages \(labels.joined(separator: " et "))") : String(localized: "Page \(labels.first ?? reader.document.pageLabel(reader.currentSourcePage))")
    }

    var body: some View {
        NavigationStack {
            List {
                if reader.shownSources.count > 1 {
                    Section("Double page : quelle page ?") {
                        Picker("Pages", selection: $chosen) {
                            ForEach(reader.shownSources, id: \.self) { source in
                                Text("p. \(reader.document.pageLabel(source))").tag([source])
                            }
                            Text("Les deux").tag(reader.shownSources)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        Group {
                            if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView() }
                        }
                        .frame(width: 160, height: 210)
                        .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: Atelier.corner(8)))
                        VStack(alignment: .leading, spacing: 10) {
                            Text(pageTitle).font(.headline)
                            Button { copyImage() } label: { Label("Copier la page en image", systemImage: "photo.on.rectangle") }
                                .buttonStyle(.borderedProminent)
                            Text("Colle-la ensuite dans claude.ai (ou une autre IA), puis colle un prompt ci-dessous.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button { openWeb() } label: { Label("Ouvrir le navigateur à côté", systemImage: "sidebar.trailing") }
                        }
                    }
                }
                Section("Prompts") {
                    ForEach(prompts) { prompt in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(prompt.title).font(.subheadline.bold())
                                Text(prompt.body).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Button("Copier") { copy(prompt.body, label: prompt.title) }.buttonStyle(.bordered)
                            Button("Image + texte") { copyBoth(prompt) }.buttonStyle(.bordered)
                        }
                        .swipeActions {
                            Button(role: .destructive) { deletePrompt(prompt) } label: { Label("Supprimer", systemImage: "trash") }
                            Button { editingPrompt = prompt } label: { Label("Modifier", systemImage: "pencil") }
                        }
                    }
                    Button { editingPrompt = AIPrompt(title: "", body: "", position: prompts.count) } label: {
                        Label("Nouveau prompt", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Page vers IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .overlay(alignment: .bottom) {
                if let copied {
                    Text("Copié : \(copied)").padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Atelier.material(.regularMaterial), in: Capsule()).padding(.bottom, 20)
                }
            }
            .sheet(item: $editingPrompt) { prompt in
                PromptEditor(prompt: prompt) { saved in
                    if let i = prompts.firstIndex(where: { $0.id == saved.id }) { prompts[i] = saved } else { prompts.append(saved) }
                    model.persist { try $0.save(saved) }
                }
            }
            .onAppear {
                prompts = (try? model.database.aiPrompts()) ?? []
                if chosen.isEmpty { chosen = reader.shownSources.count > 1 ? reader.shownSources : [reader.currentSourcePage] }
            }
            .onChange(of: chosen) { sources in
                image = nil
                DispatchQueue.main.async { image = reader.renderSources(sources, maxWidth: sources.count > 1 ? 3072 : 2048) }
            }
        }
    }

    private func flash(_ text: String) {
        copied = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if copied == text { copied = nil } }
    }

    private func copyImage() {
        guard let image else { return }
        UIPasteboard.general.image = image
        flash(String(localized: "image de la page"))
    }

    private func copy(_ text: String, label: String) {
        UIPasteboard.general.string = text
        flash(label)
    }

    /// Deux éléments dans le presse-papiers : l'image puis le texte (les apps qui savent coller
    /// plusieurs éléments récupèrent les deux).
    private func copyBoth(_ prompt: AIPrompt) {
        guard let image, let png = image.pngData() else { return }
        UIPasteboard.general.setItems([[UTType.png.identifier: png], [UTType.utf8PlainText.identifier: prompt.body]])
        flash(String(localized: "image + « \(prompt.title) »"))
    }

    private func deletePrompt(_ prompt: AIPrompt) {
        prompts.removeAll { $0.id == prompt.id }
        model.persist { try $0.deletePrompt(id: prompt.id) }
    }
}

struct PromptEditor: View {
    @State var prompt: AIPrompt
    var onSave: (AIPrompt) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titre", text: $prompt.title)
                TextEditor(text: $prompt.body).frame(minHeight: 160)
            }
            .navigationTitle("Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { onSave(prompt); dismiss() }
                        .disabled(prompt.title.isEmpty || prompt.body.isEmpty)
                }
            }
        }
    }
}

// MARK: - Navigateur à côté

/// Petit navigateur ouvert à tous les sites (claude.ai, dictionnaires en ligne, recherche…).
struct WebPanel: View {
    var onClose: () -> Void
    @Environment(\.openURL) private var openURL
    @StateObject private var state = WebState(view: WebView.shared)
    @State private var address = ""
    @FocusState private var editing: Bool

    /// Raccourcis : un appui ouvre le site.
    static let shortcuts: [(name: String, url: String)] = [
        ("Brave", "https://search.brave.com"),
        ("Claude", "https://claude.ai/new"),
        ("ChatGPT", "https://chatgpt.com"),
        ("Jisho", "https://jisho.org"),
        ("Weblio", "https://www.weblio.jp"),
        ("DeepL", "https://www.deepl.com/translator"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button { state.view.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!state.canGoBack).accessibilityLabel("Page précédente")
                    Button { state.view.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!state.canGoForward).accessibilityLabel("Page suivante")
                    TextField("Adresse ou recherche", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.webSearch).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .focused($editing)
                        .onSubmit { go(address) }
                    Button { if state.loading { state.view.stopLoading() } else { state.view.reload() } } label: {
                        Image(systemName: state.loading ? "xmark" : "arrow.clockwise")
                    }
                    .accessibilityLabel(state.loading ? String(localized: "Arrêter") : String(localized: "Recharger"))
                    Button { if let url = state.url { openURL(url) } } label: { Image(systemName: "safari") }
                        .accessibilityLabel("Ouvrir dans Safari")
                    Button(action: onClose) { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Fermer")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.shortcuts, id: \.url) { site in
                            Button(site.name) { go(site.url) }
                                .font(Atelier.font(13, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(Atelier.surfaceHigh))
                        }
                    }
                }
            }
            .padding(12)
            .background(Atelier.material(.ultraThinMaterial))
            if state.loading {
                ProgressView(value: state.progress).progressViewStyle(.linear).tint(Atelier.Tint.ai)
            }
            WebView(url: WebView.startURL)
        }
        .onAppear { address = state.url?.absoluteString ?? "" }
        .onChange(of: state.url) { url in if !editing { address = url?.absoluteString ?? "" } }
    }

    private func go(_ text: String) {
        editing = false
        guard let url = WebView.url(for: text) else { return }
        state.view.load(URLRequest(url: url))
    }
}

/// État de la vue web (adresse, retour possible, chargement) suivi pour la barre du navigateur.
@MainActor
final class WebState: ObservableObject {
    let view: WKWebView
    @Published var url: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var loading = false
    @Published var progress = 0.0
    private var observations: [NSKeyValueObservation] = []

    init(view: WKWebView) {
        self.view = view
        func watch<V>(_ path: KeyPath<WKWebView, V>, _ apply: @escaping (WebState, V) -> Void) {
            observations.append(view.observe(path, options: [.initial, .new]) { [weak self] web, _ in
                let value = web[keyPath: path]
                Task { @MainActor in if let self { apply(self, value) } }
            })
        }
        watch(\.url) { state, url in
            state.url = url
            if let url { UserDefaults.standard.set(url.absoluteString, forKey: "web.lastURL") }
        }
        watch(\.canGoBack) { $0.canGoBack = $1 }
        watch(\.canGoForward) { $0.canGoForward = $1 }
        watch(\.isLoading) { $0.loading = $1 }
        watch(\.estimatedProgress) { $0.progress = $1 }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    /// Première page : la dernière visitée, sinon claude.ai.
    @MainActor static var startURL: URL {
        UserDefaults.standard.string(forKey: "web.lastURL").flatMap(URL.init(string:)) ?? URL(string: "https://claude.ai/new")!
    }

    /// Texte tapé → adresse (avec https:// si besoin) ou recherche Brave (`WebAddress`, demande de NOxygen59 du
    /// 10/11/2026 : moteur de recherche Brave à la place de DuckDuckGo).
    static func url(for text: String) -> URL? { WebAddress.url(for: text) }

    /// Une seule vue web pour toute l'app : les sessions (claude.ai…) et la page restent ouvertes
    /// quand on ferme et rouvre le panneau.
    @MainActor static let shared: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.uiDelegate = SameViewOpener.shared
        // Agent Safari complet : certains sites refusent les vues web intégrées.
        view.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
        return view
    }()

    func makeUIView(context: Context) -> WKWebView {
        let view = Self.shared
        if view.url == nil { view.load(URLRequest(url: url)) }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Fenêtres secondaires du navigateur intégré.
///
/// Un lien `target="_blank"` cliqué s'ouvre dans la même vue, comme avant. Une fenêtre ouverte par la page
/// (`window.open`, par exemple « Continuer avec Google » sur claude.ai) devient une **vraie** vue fille, créée avec la
/// configuration fournie par WebKit et présentée en feuille au-dessus : c'est ce lien parent → fille (`window.opener`)
/// qui renvoie le résultat de connexion à la page d'origine. Avant (retour terrain T3 du 10/11/2026), la fenêtre était
/// chargée à la place de la page, le lien était perdu et la connexion n'aboutissait jamais (enquête GLM
/// `REVUES/GLM-D03-T3-CONNEXION-f85d0c0.md`). Décision pure : `WebPopupPolicy` (testée).
final class SameViewOpener: NSObject, WKUIDelegate {
    @MainActor static let shared = SameViewOpener()
    /// Feuilles ouvertes, par vue fille : gardent la vue en vie jusqu'à sa fermeture.
    @MainActor private var sheets: [ObjectIdentifier: UIViewController] = [:]

    @MainActor
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let realWindow = WebPopupPolicy.opensRealWindow(
            linkActivated: navigationAction.navigationType == .linkActivated,
            hasSize: windowFeatures.width != nil || windowFeatures.height != nil)
        guard realWindow, let top = Self.topController() else {
            webView.load(navigationAction.request)
            return nil
        }
        // La configuration fournie doit être utilisée telle quelle : elle porte le lien avec la page parente.
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.customUserAgent = webView.customUserAgent
        child.uiDelegate = self
        let holder = UIViewController()
        holder.view = child
        holder.navigationItem.title = navigationAction.request.url?.host
        holder.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self, weak child] _ in
                if let child { self?.close(child) }
            })
        let navigation = UINavigationController(rootViewController: holder)
        navigation.modalPresentationStyle = .formSheet
        sheets[ObjectIdentifier(child)] = navigation
        top.present(navigation, animated: true)
        // WebKit charge lui-même la requête dans la vue renvoyée.
        return child
    }

    /// La page a fermé sa fenêtre (`window.close()`, fin normale de la connexion Google).
    @MainActor
    func webViewDidClose(_ webView: WKWebView) {
        close(webView)
    }

    @MainActor
    private func close(_ child: WKWebView) {
        guard let sheet = sheets.removeValue(forKey: ObjectIdentifier(child)) else { return }
        child.stopLoading()
        sheet.dismiss(animated: true)
    }

    /// Contrôleur visible le plus haut (feuilles empilées comprises).
    @MainActor
    private static func topController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return nil }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}
