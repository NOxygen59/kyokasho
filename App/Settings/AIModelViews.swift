// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import SwiftUI

/// Réglages → Modèles → une page par IA : à quoi elle sert, place prise, chargée ou non (mémoire, dernier usage),
/// « Décharger », ses réglages, ses dernières tâches. Qwen3-VL : conversation (`QwenChatView`).
struct AIModelDetailView: View {
    let spec: ModelSpec
    @ObservedObject private var downloads = ModelDownloads.shared
    @State private var status: AIModelStatus?
    @State private var diskSize: Int64?
    @State private var journal: [String] = []
    @AppStorage(DocumentScan.autoKey) private var autoScan = true
    @AppStorage(ReaderController.aiRereadKey) private var aiReread = true
    @AppStorage(DocumentAnalysisService.useQwenKey) private var useQwen = false

    /// Modèles MLX (chargés en mémoire du GPU) ; les autres (ONNX) s'ouvrent à la demande.
    private var isMLX: Bool { [ModelSpec.glmocr.id, ModelSpec.ovisocr2.id, ModelSpec.qwen3vl4b.id].contains(spec.id) }
    private var directory: URL { ModelStore.shared.directory(spec) }
    private var installed: Bool { downloads.installed.contains(spec.id) }
    private var isLoaded: Bool { status?.loaded == directory }

    /// Domaines du journal (`Diagnostics.measure`) où ce modèle travaille.
    private var areas: Set<String> {
        switch spec.id {
        case ModelSpec.ovisocr2.id: return ["scan", "verif", "miseenpage", "analyse"]
        case ModelSpec.qwen3vl4b.id: return ["traduction", "chat", "analyse"]
        case ModelSpec.glmocr.id: return ["relecture", "analyse"]
        default: return ["ocr"]
        }
    }

    var body: some View {
        Form {
            Section {
                Text(spec.summary).font(.callout)
                LabeledContent("Installé", value: installed ? "oui" : "non")
                if let diskSize, diskSize > 0 { LabeledContent("Place sur l'iPad", value: StorageUsage.format(diskSize)) }
            }
            if isMLX {
                Section {
                    LabeledContent("État") {
                        Text(isLoaded ? (status?.inUse == true ? "chargé, en cours d'utilisation" : "chargé")
                             : status?.loading == directory ? "en chargement…" : "pas chargé")
                    }
                    if isLoaded, let status {
                        LabeledContent("Mémoire du GPU (MLX)", value: "\(status.gpuActiveMB) Mo + cache \(status.gpuCacheMB) Mo")
                    }
                    LabeledContent("Dernier usage") {
                        if let date = status?.lastUse[directory] {
                            Text(date, style: .relative) + Text(" (depuis le lancement)")
                        } else {
                            Text("pas depuis le lancement")
                        }
                    }
                    Button(role: .destructive) {
                        Task { await GLMOCREngine.unload(directory: directory); await refresh() }
                    } label: { Label("Décharger maintenant", systemImage: "eject") }
                    .disabled(!isLoaded)
                } header: {
                    Text("Mémoire")
                } footer: {
                    Text("Un seul modèle d'IA chargé à la fois. Il se libère tout seul 45 s après sa dernière lecture, en revenant à la bibliothèque ou quand l'app passe en arrière-plan. Une lecture en cours le garde jusqu'à sa fin.")
                }
            } else {
                Section("Mémoire") {
                    Text("Ouvert à la demande pendant la lecture d'une page, refermé 30 s après le dernier usage.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            settings
            if spec.id == ModelSpec.qwen3vl4b.id {
                Section {
                    NavigationLink { QwenChatView() } label: { Label("Discuter avec Qwen3-VL", systemImage: "bubble.left.and.bubble.right") }
                        .disabled(!installed)
                } footer: {
                    Text("Le modèle se charge à l'ouverture de la conversation et se décharge en la quittant (≈ 3,5 Go).")
                }
            }
            Section("Dernières tâches") {
                if journal.isEmpty {
                    Text("Rien depuis le lancement de l'app.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(journal.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                            .foregroundStyle(line.contains("✗") ? Color.red : Color.secondary)
                    }
                }
            }
        }
        .navigationTitle(spec.title)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    @ViewBuilder
    private var settings: some View {
        switch spec.id {
        case ModelSpec.ovisocr2.id:
            Section {
                Toggle("Lire chaque document à l'import et à l'ouverture", isOn: $autoScan)
            } header: { Text("Réglages") } footer: {
                Text("Pages pas encore lues seulement (≈ 30 s par page). Ce texte sert aux furigana, aux caractères douteux, à la mise en page IA et à la vérification.")
            }
        case ModelSpec.glmocr.id:
            Section {
                Toggle("Relire les lignes douteuses automatiquement", isOn: $aiReread)
            } header: { Text("Réglages") }
        case ModelSpec.qwen3vl4b.id:
            Section {
                Toggle("Ajouter à l'analyse du document entier", isOn: $useQwen)
            } header: { Text("Réglages") } footer: {
                Text("Une lecture de plus par page (plus lent, vote plus sûr). La traduction française l'utilise toujours.")
            }
        default:
            EmptyView()
        }
    }

    private func refresh() async {
        let dir = directory
        diskSize = await Task.detached(priority: .utility) { StorageUsage.size(of: dir) }.value
        if isMLX { status = await GLMOCREngine.status() }
        journal = Diagnostics.recent(areas: areas)
    }
}

/// Conversation avec Qwen3-VL-4B, gardée d'une ouverture à l'autre (`Chats/qwen.json`).
struct QwenChatView: View {
    @State private var chat = QwenChat()
    @State private var messages: [QwenChat.Message] = []
    @State private var draft = ""
    @State private var loading = true
    @State private var answering: Task<Void, Never>?
    @State private var error: String?

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kyokasho/Chats/qwen.json")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty, !loading {
                            Text("Pose une question : un mot japonais, une phrase du manuel, une notion de design d'intérieur… Tout reste sur l'iPad.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(Array(messages.enumerated()), id: \.offset) { i, m in
                            bubble(m).id(i)
                        }
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                    .padding()
                }
                .onChange(of: messages) { list in
                    withAnimation { proxy.scrollTo(list.count - 1, anchor: .bottom) }
                }
            }
            Divider()
            HStack(spacing: 10) {
                TextField(loading ? "Chargement du modèle…" : "Ta question", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .disabled(loading)
                    .onSubmit(send)
                if answering != nil {
                    Button { answering?.cancel() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                        .accessibilityLabel("Arrêter la réponse")
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .disabled(loading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Envoyer")
                }
            }
            .padding()
        }
        .navigationTitle("Qwen3-VL")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    answering?.cancel()
                    messages = []
                    save()
                    Task { await chat.reset() }
                } label: { Label("Nouvelle conversation", systemImage: "square.and.pencil") }
                .disabled(loading)
            }
        }
        .task {
            messages = (try? JSONDecoder().decode([QwenChat.Message].self, from: Data(contentsOf: Self.file))) ?? []
            // Lexique du domaine : sens et lectures sûres ajoutés aux questions.
            chat.glossary = DomainLexicon.shared.glossary
            chat.readings = DomainLexicon.shared.readings
            do {
                try await Diagnostics.measure("chargement de Qwen3-VL (chat)", "chat") {
                    try await chat.start(history: messages)
                }
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
        // Écran quitté : réponse arrêtée, modèle déchargé.
        .onDisappear {
            answering?.cancel()
            let chat = chat
            Task { await chat.stop() }
        }
    }

    private func bubble(_ m: QwenChat.Message) -> some View {
        let mine = m.role == .user
        return HStack {
            if mine { Spacer(minLength: 60) }
            Text(m.text.isEmpty ? "…" : m.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(mine ? Atelier.Tint.ai.opacity(0.25) : Atelier.surfaceHigh,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !mine { Spacer(minLength: 60) }
        }
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !loading, answering == nil else { return }
        draft = ""
        error = nil
        messages.append(.init(role: .user, text: prompt))
        messages.append(.init(role: .assistant, text: ""))
        let index = messages.count - 1
        answering = Task {
            let start = Date()
            do {
                for try await chunk in chat.stream(prompt) { messages[index].text += chunk }
                Diagnostics.remember("chat", "✓ réponse en \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
                Diagnostics.remember("chat", "✗ réponse : \(error.localizedDescription)")
            }
            if messages[index].text.isEmpty { messages[index].text = "(pas de réponse)" }
            answering = nil
            save()
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(messages).write(to: Self.file, options: .atomic)
    }
}
