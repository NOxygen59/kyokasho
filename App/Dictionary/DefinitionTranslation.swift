// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import Foundation
import SwiftUI

/// Traductions françaises des définitions anglaises (DeepL), gardées sur l'appareil avec ton avis :
/// 👍 validée, 👎 à revoir, ✏️ corrigée à la main (la correction remplace la traduction, pour toujours).
@MainActor
final class DefinitionTranslations: ObservableObject {
    static let shared = DefinitionTranslations()
    static let autoKey = "dictionary.autoTranslateFR"

    enum Status: String, Codable { case machine, liked, disliked, edited }

    struct Entry: Codable, Equatable {
        var text: String
        var status: Status
    }

    @Published private(set) var entries: [String: Entry] = [:]
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("definition-translations.json")
    }()

    private init() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        } else {
            // Fichier illisible : mis de côté plutôt qu'écrasé (tes corrections restent récupérables).
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("bak"))
        }
    }

    static func key(_ term: TermResult) -> String {
        "\(term.expression)|\(term.reading)|\(term.definitions.first?.dictionaryTitle ?? "")"
    }

    /// Définitions en texte simple (celles du premier dictionnaire du mot).
    static func source(_ term: TermResult) -> String {
        guard let title = term.definitions.first?.dictionaryTitle else { return "" }
        return term.definitions.filter { $0.dictionaryTitle == title }
            .map { GlossaryText.plain($0.glossaryJSON, limit: 200) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: " ; ")
    }

    /// Définition surtout en lettres latines (et pas de kana/kanji) : anglaise.
    static func isEnglish(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 3 else { return false }
        let latin = letters.filter { $0.isASCII }.count
        return Double(latin) / Double(letters.count) > 0.8
    }

    func translate(_ term: TermResult) async throws {
        let source = Self.source(term)
        guard !source.isEmpty else { return }
        let text = try await DeepLService.shared.translate(source, target: "FR")
        set(Self.key(term), Entry(text: text, status: .machine))
    }

    func set(_ key: String, _ entry: Entry?) {
        entries[key] = entry
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}

/// Bloc « Français » sous les définitions anglaises du premier mot trouvé.
struct DefinitionTranslationBar: View {
    let term: TermResult
    @ObservedObject private var store = DefinitionTranslations.shared
    @ObservedObject private var deepl = DeepLService.shared
    @AppStorage(DefinitionTranslations.autoKey) private var auto = false
    @State private var busy = false
    @State private var error: String?
    @State private var editing = false
    @State private var draft = ""

    private var key: String { DefinitionTranslations.key(term) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("FR").font(.system(size: 11, weight: .bold)).foregroundStyle(Atelier.Tint.ai)
                Text(term.expression).font(.custom("HiraginoSans-W6", size: 13)).foregroundStyle(Atelier.textSecondary)
                Spacer()
                if let entry = store.entries[key] {
                    feedback(entry)
                }
            }
            if editing {
                TextField("Ta traduction", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 14))
                    .padding(6)
                    .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                HStack {
                    Button("Annuler") { editing = false }
                    Spacer()
                    Button("Garder") {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty { store.set(key, .init(text: text, status: .edited)) }
                        editing = false
                    }
                    .fontWeight(.semibold)
                }
                .font(.system(size: 13))
                .foregroundStyle(Atelier.Tint.ai)
            } else if let entry = store.entries[key] {
                Text(entry.text).font(.system(size: 14)).foregroundStyle(Atelier.textPrimary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if deepl.hasKey {
                Button {
                    Task { await translate() }
                } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView().controlSize(.small) }
                        Text("Traduire la définition en français")
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Atelier.Tint.ai)
                .disabled(busy)
            } else {
                Text("Traduction française : ajoute ta clé DeepL dans Réglages → Traduction.")
                    .font(.caption).foregroundStyle(Atelier.textTertiary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Atelier.textTertiary) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Atelier.surfaceHigh.opacity(0.5))
        .task(id: key) {
            editing = false
            error = nil
            if auto, deepl.hasKey, store.entries[key] == nil { await translate() }
        }
    }

    private func feedback(_ entry: DefinitionTranslations.Entry) -> some View {
        HStack(spacing: 12) {
            Button { store.set(key, .init(text: entry.text, status: entry.status == .liked ? .machine : .liked)) } label: {
                Image(systemName: entry.status == .liked || entry.status == .edited ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .accessibilityLabel("Bonne traduction")
            Button {
                store.set(key, .init(text: entry.text, status: .disliked))
                draft = entry.text
                editing = true
            } label: {
                Image(systemName: entry.status == .disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .accessibilityLabel("Mauvaise traduction : la corriger")
            Button { draft = entry.text; editing = true } label: { Image(systemName: "pencil") }
                .accessibilityLabel("Modifier la traduction")
        }
        .font(.system(size: 13))
        .foregroundStyle(Atelier.textSecondary)
        .buttonStyle(.plain)
    }

    private func translate() async {
        busy = true
        defer { busy = false }
        do { try await store.translate(term) } catch { self.error = error.localizedDescription }
    }
}
