// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import SwiftUI

/// Pile de recherches d'un popup : chaque mot touché dans une définition ouvre une page de plus
/// (recherche imbriquée), avec retour arrière et historique.
@MainActor
final class LookupSession: ObservableObject {
    enum Page: Equatable {
        case terms(query: String, results: [TermResult])
        case kanji(KanjiResult)
        case loading(String)

        var title: String {
            switch self {
            case .terms(let q, let r): return r.first?.matchedText ?? q
            case .kanji(let k): return k.character
            case .loading(let q): return q
            }
        }
    }

    let dictionary: DictionaryModel
    @Published private(set) var stack: [Page] = []
    /// Toutes les recherches de la session (onglet Historique de la recherche manuelle).
    @Published private(set) var history: [String] = []
    /// Mot reconnu sur la page (pour surligner le texte touché).
    @Published private(set) var matchedLength = 0

    init(dictionary: DictionaryModel) {
        self.dictionary = dictionary
    }

    var current: Page? { stack.last }
    var canGoBack: Bool { stack.count > 1 }

    func start(_ text: String) {
        stack = []
        push(text)
    }

    func push(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        stack.append(.loading(query))
        let depth = stack.count
        Task {
            let results = await dictionary.lookup(query)
            guard stack.count == depth else { return }
            stack[depth - 1] = .terms(query: query, results: results)
            if depth == 1 { matchedLength = results.first?.matchLength ?? 0 }
            if let first = results.first {
                history.removeAll { $0 == first.expression }
                history.insert(first.expression, at: 0)
                if history.count > 100 { history.removeLast() }
                if dictionary.profile.autoPlayAudio { await dictionary.playAudio(term: first.expression, reading: first.reading) }
            }
        }
    }

    func pushKanji(_ character: String) {
        stack.append(.loading(character))
        let depth = stack.count
        Task {
            if let k = await dictionary.kanji(character), stack.count == depth {
                stack[depth - 1] = .kanji(k)
            } else if stack.count == depth {
                stack[depth - 1] = .terms(query: character, results: await dictionary.lookup(character))
            }
        }
    }

    func back() {
        if stack.count > 1 { stack.removeLast() }
    }

    func clear() {
        stack = []
        matchedLength = 0
    }

    func html(canAddCards: Bool, added: Set<String> = []) -> String {
        let renderer = dictionary.renderer(canAddCards: canAddCards, added: added)
        switch current {
        case .terms(let q, let r)?: return renderer.page(terms: r, dictionaries: dictionary.dictionaries, query: q)
        case .kanji(let k)?: return renderer.page(kanji: k)
        default: return renderer.page(terms: [], dictionaries: [], query: nil).replacingOccurrences(of: "Aucun résultat.", with: "…")
        }
    }

    var currentTerms: [TermResult] {
        if case .terms(_, let r)? = current { return r }
        return []
    }
}

/// Popup de dictionnaire (panneau flottant Atelier).
struct LookupPopup: View {
    @EnvironmentObject private var dictionaryModel: DictionaryModel
    @ObservedObject var session: LookupSession
    /// Clés des cartes existantes (✓ dans les résultats).
    var added: Set<String> = []
    /// Ajoute une carte ; renvoie un petit message à afficher (doublon, erreur…), ou `nil`.
    var onAddCard: ((TermResult) -> String?)? = nil
    var close: () -> Void
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if session.canGoBack {
                    Button { session.back() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Retour")
                }
                Text(session.current?.title ?? "").font(.custom("HiraginoSans-W6", size: 16)).lineLimit(1)
                    .foregroundStyle(Atelier.textPrimary)
                if case .loading? = session.current { ProgressView().controlSize(.small).tint(Atelier.Tint.japanese) }
                Spacer()
                if session.stack.count > 1 {
                    Text("\(session.stack.count)").font(Atelier.mono).foregroundStyle(Atelier.textTertiary)
                }
                Button(action: close) { Image(systemName: "xmark") }.accessibilityLabel("Fermer")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Atelier.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider().overlay(Atelier.hairline)
            if !dictionaryModel.hasTermDictionaries {
                VStack(spacing: 8) {
                    Text("Aucun dictionnaire").font(.headline).foregroundStyle(Atelier.textPrimary)
                    Text("Importe un dictionnaire Yomitan (.zip) dans Réglages → Dictionnaires.")
                        .multilineTextAlignment(.center).foregroundStyle(Atelier.textSecondary)
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LookupWebView(html: session.html(canAddCards: onAddCard != nil, added: added),
                              mediaRoot: dictionaryModel.database?.mediaRoot) { message in
                    handle(message)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(.system(size: 14, weight: .semibold)).foregroundStyle(Atelier.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Atelier.surfaceHigh, in: Capsule())
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
        .background(Atelier.surface)
        .clipShape(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).strokeBorder(Atelier.Tint.japanese.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 24, y: 10)
    }

    private func handle(_ message: LookupMessage) {
        switch message {
        case .lookup(let text): session.push(text)
        case .kanji(let c): session.pushKanji(c)
        case .audio(let term, let reading): Task { await dictionaryModel.playAudio(term: term, reading: reading) }
        case .card(let index):
            let terms = session.currentTerms
            guard terms.indices.contains(index), let message = onAddCard?(terms[index]) else { return }
            toast = message
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if toast == message { toast = nil }
            }
        }
    }
}
