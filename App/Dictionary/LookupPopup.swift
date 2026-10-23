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
    @Published private(set) var stack: [Page] = [] {
        didSet { stackRevision &+= 1 }
    }
    private var requestID = UUID()
    /// Change à chaque modification de la pile : sert de clé au HTML déjà construit.
    private var stackRevision = 0
    private struct HTMLKey: Equatable {
        var revision: Int
        var canAddCards: Bool
        var added: Set<String>
        var options: GlossaryRenderer.Options
        var dictionaries: [DictionaryInfo]
    }
    private var htmlCache: (key: HTMLKey, html: String)?
    /// Mot reconnu sur la page (pour surligner le texte touché).
    @Published private(set) var matchedLength = 0

    init(dictionary: DictionaryModel) {
        self.dictionary = dictionary
    }

    var current: Page? { stack.last }
    var canGoBack: Bool { stack.count > 1 }

    func start(_ text: String, preferredReading: String? = nil) {
        stack = []
        push(text, preferredReading: preferredReading)
    }

    func push(_ text: String, preferredReading: String? = nil) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        requestID = UUID()
        let request = requestID
        stack.append(.loading(query))
        let depth = stack.count
        Task {
            var results = await dictionary.lookup(query)
            guard requestID == request, stack.count == depth else { return }
            if let preferredReading, let index = results.firstIndex(where: {
                $0.expression == query && $0.reading == preferredReading
            }), index != 0 {
                results.insert(results.remove(at: index), at: 0)
            }
            stack[depth - 1] = .terms(query: query, results: results)
            if depth == 1 { matchedLength = results.first?.matchLength ?? 0 }
            if let first = results.first {
                dictionary.remember(.init(kind: .word, expression: first.expression, reading: first.reading))
                if dictionary.profile.autoPlayAudio { await dictionary.playAudio(term: first.expression, reading: first.reading) }
            }
        }
    }

    func pushKanji(_ character: String) {
        requestID = UUID()
        let request = requestID
        stack.append(.loading(character))
        let depth = stack.count
        Task {
            if let k = await dictionary.kanji(character), requestID == request, stack.count == depth {
                stack[depth - 1] = .kanji(k)
                dictionary.remember(.init(kind: .kanji, expression: character, reading: ""))
            } else if requestID == request, stack.count == depth {
                let results = await dictionary.lookup(character)
                guard requestID == request, stack.count == depth else { return }
                stack[depth - 1] = .terms(query: character, results: results)
            }
        }
    }

    func back() {
        if stack.count > 1 { requestID = UUID(); stack.removeLast() }
    }

    func clear() {
        requestID = UUID()
        stack = []
        matchedLength = 0
    }

    /// HTML de la page affichée. Gardé tant que rien ne change : le popup se redessine souvent
    /// (toast, sélection…) et reconstruire tout le HTML à chaque fois coûtait pour rien.
    func html(canAddCards: Bool, added: Set<String> = []) -> String {
        let key = HTMLKey(revision: stackRevision, canAddCards: canAddCards, added: added,
                          options: dictionary.profile.display, dictionaries: dictionary.dictionaries)
        if let htmlCache, htmlCache.key == key { return htmlCache.html }
        let renderer = dictionary.renderer(canAddCards: canAddCards, added: added)
        let html: String
        switch current {
        case .terms(let q, let r)?: html = renderer.page(terms: r, dictionaries: dictionary.dictionaries, query: q)
        case .kanji(let k)?: html = renderer.page(kanji: k)
        default: html = renderer.page(terms: [], dictionaries: [], query: nil).replacingOccurrences(of: "Aucun résultat.", with: "…")
        }
        htmlCache = (key, html)
        return html
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
    @ObservedObject private var translations = DefinitionTranslations.shared
    @ObservedObject private var deepl = DeepLService.shared
    @AppStorage(DefinitionTranslations.autoKey) private var autoTranslate = false
    @State private var translating = false
    @State private var translateError: String?
    @State private var editingFrench = false
    @State private var frenchDraft = ""

    /// Premier mot trouvé, s'il n'a que des définitions anglaises (traduction française possible).
    private var englishTerm: TermResult? {
        guard let term = session.currentTerms.first,
              DefinitionTranslations.isEnglish(DefinitionTranslations.source(term)) else { return nil }
        return term
    }

    private var pageHTML: String {
        let html = session.html(canAddCards: onAddCard != nil, added: added)
        guard let term = englishTerm else { return html }
        let block = DefinitionTranslationHTML.block(entry: translations.entries[DefinitionTranslations.key(term)],
                                                    hasKey: deepl.hasKey, busy: translating, error: translateError)
        return DefinitionTranslationHTML.inject(block, into: html)
    }

    private var savedEntry: DictionaryModel.SavedEntry? {
        switch session.current {
        case .terms(_, let results)?: return results.first.map {
            .init(kind: .word, expression: $0.expression, reading: $0.reading)
        }
        case .kanji(let kanji)?: return .init(kind: .kanji, expression: kanji.character, reading: "")
        default: return nil
        }
    }

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
                if let entry = savedEntry {
                    Button { dictionaryModel.toggleSaved(entry) } label: {
                        Image(systemName: dictionaryModel.isSaved(entry) ? "star.fill" : "star")
                            .foregroundStyle(Atelier.Tint.japanese)
                    }
                    .accessibilityLabel(dictionaryModel.isSaved(entry) ? "Retirer des mots enregistrés" : "Enregistrer")
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
                LookupWebView(html: pageHTML,
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
        // Traduction automatique (option) du premier mot anglais pas encore traduit.
        .task(id: englishTerm.map(DefinitionTranslations.key)) {
            translateError = nil
            guard autoTranslate, deepl.hasKey, let term = englishTerm,
                  translations.entries[DefinitionTranslations.key(term)] == nil else { return }
            await translateFrench(term)
        }
        .alert("Traduction française", isPresented: $editingFrench) {
            TextField("Ta traduction", text: $frenchDraft)
            Button("Annuler", role: .cancel) {}
            Button("Garder") {
                let text = frenchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if let term = englishTerm, !text.isEmpty {
                    translations.set(DefinitionTranslations.key(term), .init(text: text, status: .edited))
                }
            }
        }
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
        case .french(let action):
            guard let term = englishTerm else { return }
            let key = DefinitionTranslations.key(term)
            let entry = translations.entries[key]
            switch action {
            case "translate": Task { await translateFrench(term) }
            case "like":
                if let entry { translations.set(key, .init(text: entry.text, status: entry.status == .liked ? .machine : .liked)) }
            case "dislike":
                if let entry { translations.set(key, .init(text: entry.text, status: .disliked)) }
                frenchDraft = entry?.text ?? ""
                editingFrench = true
            default:
                frenchDraft = entry?.text ?? ""
                editingFrench = true
            }
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

    private func translateFrench(_ term: TermResult) async {
        translating = true
        translateError = nil
        defer { translating = false }
        do { try await translations.translate(term) } catch { translateError = error.localizedDescription }
    }
}
