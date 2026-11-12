// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import ReaderCore
import AVFoundation
import SwiftUI
import UIKit

/// Réglages → Modèles → une page par IA : à quoi elle sert, place prise, chargée ou non (mémoire, dernier usage),
/// « Décharger », ses réglages, ses dernières tâches. Qwen3-VL : conversation (`QwenChatView`).
struct AIModelDetailView: View {
    let spec: ModelSpec
    @ObservedObject private var downloads = ModelDownloads.shared
    @State private var status: AIModelStatus?
    @State private var diskSize: Int64?
    @State private var journal: [String] = []

    /// Modèles MLX (chargés en mémoire du GPU) ; les autres (ONNX) s'ouvrent à la demande.
    private var isMLX: Bool { [ModelSpec.glmocr.id, ModelSpec.ovisocr2.id, ModelSpec.qwen3vl4b.id,
                               ModelSpec.qwen35chat4b.id].contains(spec.id) }
    private var directory: URL { ModelStore.shared.directory(spec) }
    private var installed: Bool { downloads.installed.contains(spec.id) }
    private var isLoaded: Bool { status?.loaded == directory }

    /// Domaines du journal (`Diagnostics.measure`) où ce modèle travaille.
    private var areas: Set<String> {
        switch spec.id {
        case ModelSpec.ovisocr2.id: return ["scan", "verif", "miseenpage", "analyse"]
        case ModelSpec.qwen3vl4b.id: return ["traduction", "chat", "analyse"]
        case ModelSpec.qwen35chat4b.id: return ["chat"]
        case ModelSpec.glmocr.id: return ["relecture", "analyse"]
        default: return ["ocr"]
        }
    }

    var body: some View {
        Form {
            Section {
                Text(spec.summary).font(.callout)
                LabeledContent("Installé", value: installed ? String(localized: "oui") : String(localized: "non"))
                if let diskSize, diskSize > 0 { LabeledContent("Place sur l'iPad", value: StorageUsage.format(diskSize)) }
            }
            if isMLX {
                Section {
                    LabeledContent("État") {
                        Text(isLoaded ? (status?.inUse == true ? String(localized: "chargé, en cours d'utilisation") : String(localized: "chargé"))
                             : status?.loading == directory ? String(localized: "en chargement…") : String(localized: "pas chargé"))
                    }
                    if isLoaded, let status {
                        LabeledContent("Mémoire du GPU (MLX)", value: String(localized: "\(status.gpuActiveMB) Mo + cache \(status.gpuCacheMB) Mo"))
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
            usageLocation
            if spec.id == ModelSpec.qwen3vl4b.id || spec.id == ModelSpec.qwen35chat4b.id {
                Section {
                    NavigationLink { QwenChatView(preferredModel: spec) } label: { Label("Discuter avec l'IA", systemImage: "bubble.left.and.bubble.right") }
                        .disabled(!installed)
                } footer: {
                    Text("Choisis le modèle dans le chat. Il se charge à l'ouverture et se décharge en quittant la conversation.")
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
    private var usageLocation: some View {
        switch spec.id {
        case ModelSpec.ovisocr2.id:
            Section {
                NavigationLink("Lecture automatique des documents") { OCRSettingsView() }
            } header: { Text("Utilisation") } footer: {
                Text("La langue se choisit à l'import ou dans les réglages du livre.")
            }
        case ModelSpec.glmocr.id:
            Section {
                NavigationLink("Relecture des caractères douteux") { OCRAdvancedSettingsView() }
            } header: { Text("Utilisation") }
        case ModelSpec.qwen3vl4b.id:
            Section {
                Text("Ajoute ce modèle depuis l'écran « Analyser le document entier » du livre. La traduction française l'utilise toujours.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Utilisation") }
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

/// Conversation avec Qwen3-VL-4B. Pour un livre, seules ses pages déjà lues par Ovis sont consultées.
struct QwenChatView: View {
    var document: LibraryDocument? = nil
    var embedded = false
    var focusPage: String? = nil
    var preferredModel: ModelSpec = .qwen3vl4b
    var openPage: ((Int) -> Void)? = nil
    /// Fenêtre OCR : enregistre une réponse comme note de la page affichée.
    var saveToNotes: ((String) -> Void)? = nil
    /// Base de l'app, pour suivre les pages citées après une modification des pages (#49, R4).
    var database: AppDatabase? = nil
    private struct Conversation: Codable, Identifiable {
        /// Titre par défaut gardé en français dans le fichier : c'est lui qu'on reconnaît pour le remplacer.
        var shownTitle: String { title == "Nouveau chat" ? String(localized: "Nouveau chat") : title }
        var id = UUID()
        var title: String
        var modelID = ModelSpec.qwen3vl4b.id
        var messages: [QwenChat.Message] = []
    }
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloads = ModelDownloads.shared
    @State private var chat = QwenChat()
    @State private var messages: [QwenChat.Message] = []
    @State private var conversations: [Conversation] = []
    @State private var selectedConversation: UUID?
    @State private var selectedModelID = ModelSpec.qwen3vl4b.id
    @State private var draft = ""
    @State private var loading = true
    @State private var ready = false
    @State private var answering: Task<Void, Never>?
    @State private var modelSwitch: Task<Void, Never>?
    @State private var error: String?
    @State private var storageError = false
    /// Réglages du chat du modèle choisi (#45) ; feuille ouverte par la roue dentée.
    @State private var showSettings = false
    @State private var settingsAtOpen = AIChatSettings()
    /// Durée de la dernière réponse, affichée sous la barre (« réponse en 12 s »).
    @State private var lastDuration: TimeInterval?
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false
    @State private var showConversations = false
    /// Bref retour après une action sur une réponse (« Copié », « Ajouté aux notes »).
    @State private var toast: String?
    private static let speaker = AVSpeechSynthesizer()

    private var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kyokasho/Chats/qwen\(document.map { "-" + $0.id } ?? "").json")
    }
    private var bookFile: URL? {
        document.map { file.deletingLastPathComponent().appendingPathComponent("book-\($0.id).json") }
    }
    private var selectedSpec: ModelSpec {
        selectedModelID == ModelSpec.qwen35chat4b.id ? .qwen35chat4b : .qwen3vl4b
    }

    var body: some View {
        VStack(spacing: 0) {
            if document != nil { conversationBar }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty, !loading {
                            Text(document == nil
                                 ? String(localized: "Pose une question sur un mot japonais, une phrase ou un sujet qui t'intéresse. Tout reste sur l'iPad.")
                                 : String(localized: "Pose une question sur ce livre ou sur un mot. Je chercherai les passages lus par OvisOCR2 et citerai leurs pages ; sinon, je répondrai avec mes connaissances générales en le signalant."))
                                .font(.footnote).foregroundStyle(.secondary)
                            if ready { suggestions }
                        }
                        ForEach(Array(messages.enumerated()), id: \.offset) { i, m in
                            bubble(m, index: i).id(i)
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
            statusLine
            if ready { chips.padding(.top, 6) }
            HStack(spacing: 10) {
                // Corbeille à côté du champ (recette 62) : efface la conversation affichée, après une confirmation.
                Button { confirmDelete = true } label: { Image(systemName: "trash").font(.body) }
                    .foregroundStyle(.red)
                    .disabled(answering != nil || loading || storageError || (messages.isEmpty && (document == nil || conversations.count < 2)))
                    .accessibilityLabel("Supprimer cette conversation")
                TextField(loading ? String(localized: "Chargement du modèle…") : ready ? String(localized: "Ta question") : String(localized: "Modèle indisponible"), text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!ready)
                    .onSubmit(send)
                if answering != nil {
                    Button { answering?.cancel() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                        .accessibilityLabel("Arrêter la réponse")
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .disabled(!ready || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityLabel("Envoyer (⌘ ↩)")
                }
            }
            .padding()
        }
        .navigationTitle(embedded ? "" : document.map { String(localized: "Discuter · ") + $0.title } ?? String(localized: "Chat IA"))
        .toolbar {
            if document != nil && !embedded {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
            if document == nil {
                ToolbarItem(placement: .secondaryAction) { HStack { tasksMenu; settingsButton } }
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
        }
        .task {
            if document != nil { loadConversations() }
            else {
                selectedModelID = preferredModel.id
                messages = (try? JSONDecoder().decode([QwenChat.Message].self, from: Data(contentsOf: file))) ?? []
            }
            if storageError { loading = false; return }
            if let document, !DocumentKnowledge.isReady(document) {
                error = String(localized: "Attends la fin de la lecture OvisOCR2 : \(DocumentKnowledge.readCount(document))/\(document.pageCount) pages.")
                loading = false
                return
            }
            await startSelectedModel()
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast).font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Atelier.material(.thinMaterial), in: Capsule())
                    .padding(.top, 50)
                    .transition(.opacity)
            }
        }
        .alert("Renommer la conversation", isPresented: $renaming) {
            TextField("Titre", text: $newTitle)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") { renameConversation() }
        }
        // Fenêtre de confirmation centrée dans le chat (recette 1.3.2 (63), point 17) : la feuille d'iOS se plaçait
        // mal dans la fenêtre OCR ; celle-ci reste au milieu du panneau, à droite, en fenêtre ou en plein écran.
        .centeredConfirmation(isPresented: $confirmDelete, title: String(localized: "Supprimer cette conversation ?"),
                              message: String(localized: "Ses messages seront effacés de l'iPad. Les autres conversations sont gardées."),
                              confirm: String(localized: "Supprimer")) { deleteConversation() }
        .sheet(isPresented: $showConversations) {
            ConversationListSheet(
                items: conversations.map { ($0.id, $0.shownTitle, $0.messages.count) },
                selected: selectedConversation,
                onOpen: { id in showConversations = false; switchConversation(to: id) },
                onRename: { id in
                    showConversations = false
                    newTitle = conversations.first(where: { $0.id == id })?.title ?? ""
                    if id != selectedConversation { switchConversation(to: id) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { renaming = true }
                },
                onDelete: { ids in deleteConversations(ids) },
                onNew: { showConversations = false; newConversation() })
        }
        .sheet(isPresented: $showSettings, onDismiss: applySettingsIfChanged) {
            NavigationStack {
                AIChatSettingsView(modelID: selectedModelID, fixedModel: true)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showSettings = false } } }
            }
        }
        // Écran quitté : réponse arrêtée, modèle déchargé.
        .onDisappear {
            answering?.cancel()
            modelSwitch?.cancel()
            save()
            let chat = chat
            Task { await chat.stop() }
        }
    }

    private var conversationBar: some View {
        VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
            // Liste des conversations en feuille (recette 62) : choisir, renommer, en supprimer plusieurs.
            Button { showConversations = true } label: {
                Label(conversations.first(where: { $0.id == selectedConversation })?.shownTitle ?? String(localized: "Conversation"), systemImage: "bubble.left")
                    .lineLimit(1)
            }
            .disabled(answering != nil || loading || storageError)
            Spacer(minLength: 0)
            Menu {
                modelOption(.qwen3vl4b, title: String(localized: "Qwen3-VL 4B"))
                modelOption(.qwen35chat4b, title: String(localized: "Qwen3.5 4B"))
            } label: {
                Label(selectedSpec.id == ModelSpec.qwen35chat4b.id ? "Qwen3.5" : "Qwen3-VL", systemImage: "cpu")
                    .lineLimit(1)
            }
            .disabled(answering != nil || loading || storageError)
            if let progress = downloads.progress[ModelSpec.qwen35chat4b.id] {
                ProgressView(value: progress).frame(width: 30)
            }
            tasksMenu
            settingsButton
            Button { newConversation() } label: {
                Image(systemName: "square.and.pencil")
            }
            .disabled(answering != nil || loading || storageError)
            .accessibilityLabel("Nouveau chat")
        }
        .font(.caption)
        .padding(.horizontal, 12).padding(.vertical, 8)
        if let error = downloads.errors[ModelSpec.qwen35chat4b.id] {
            Text("Téléchargement : \(error)").font(.caption2).foregroundStyle(.red)
                .padding(.horizontal, 12)
        }
        }
    }

    @ViewBuilder
    private func modelOption(_ spec: ModelSpec, title: String) -> some View {
        if downloads.installed.contains(spec.id) {
            Button { selectModel(spec) } label: {
                Label(title, systemImage: spec.id == selectedModelID ? "checkmark" : "cpu")
            }
        } else if downloads.progress[spec.id] != nil {
            Text("Téléchargement de \(title)…")
        } else {
            Button { downloads.start(spec) } label: {
                Label("Télécharger \(title) (\(StorageUsage.format(spec.totalSize)))", systemImage: "arrow.down.circle")
            }
        }
    }

    /// Tâches rapides (#37) : une question type écrite dans le champ, à compléter ou envoyer telle quelle.
    private var tasksMenu: some View {
        let page = focusPage.map { String(localized: "la page \($0)") } ?? String(localized: "ce passage")
        return Menu {
            Button("Résumer \(page)") { draft = String(localized: "Résume \(page) : de quoi parle-t-elle, puis les points clés.") }
            Button("Expliquer les formules de \(page)") { draft = String(localized: "Explique pas à pas chaque formule de \(page), avec un exemple chiffré.") }
            Button("Vocabulaire de \(page)") { draft = String(localized: "Liste les mots techniques japonais de \(page) avec lecture et sens.") }
            Button("Traduire mot à mot") { draft = String(localized: "Traduis mot à mot, puis naturellement : ") }
        } label: { Image(systemName: "list.bullet.rectangle") }
        .disabled(!ready || answering != nil)
        .accessibilityLabel("Tâches rapides")
    }

    private var settingsButton: some View {
        Button {
            settingsAtOpen = AIChatSettingsStore.load(selectedModelID)
            showSettings = true
        } label: { Image(systemName: "slider.horizontal.3") }
        .disabled(loading || answering != nil)
        .accessibilityLabel("Consigne et paramètres du chat")
    }

    /// Réglages changés : le modèle redémarre la conversation avec eux (historique gardé).
    private func applySettingsIfChanged() {
        guard AIChatSettingsStore.load(selectedModelID) != settingsAtOpen, downloads.installed.contains(selectedModelID) else { return }
        let oldChat = chat
        ready = false
        loading = true
        modelSwitch = Task {
            await oldChat.stop()
            guard !Task.isCancelled else { return }
            await startSelectedModel()
        }
    }

    private func loadConversations() {
        guard let bookFile else { return }
        if let data = try? Data(contentsOf: bookFile) {
            guard let stored = try? JSONDecoder().decode([Conversation].self, from: data), !stored.isEmpty else {
                error = String(localized: "Impossible de lire les conversations enregistrées. Elles n'ont pas été modifiées.")
                storageError = true
                return
            }
            conversations = stored
        }
        if conversations.isEmpty {
            let old = (try? JSONDecoder().decode([QwenChat.Message].self, from: Data(contentsOf: file))) ?? []
            let initialModel = downloads.installed.contains(ModelSpec.qwen3vl4b.id)
                ? ModelSpec.qwen3vl4b.id : ModelSpec.qwen35chat4b.id
            conversations = [Conversation(title: old.first(where: { $0.role == .user })
                .map { String($0.text.prefix(42)) } ?? "Nouveau chat", modelID: initialModel, messages: old)]
            saveConversations()
        }
        selectedConversation = conversations[0].id
        selectedModelID = conversations[0].modelID
        messages = conversations[0].messages
    }

    private func startSelectedModel() async {
        loading = true
        ready = false
        error = nil
        let spec = selectedSpec
        guard downloads.installed.contains(spec.id) else {
            error = String(localized: "Télécharge \(spec.title) depuis le menu Modèle pour discuter.")
            loading = false
            return
        }
        let selectedChat = QwenChat(model: spec)
        selectedChat.glossary = DomainLexicon.shared.glossary
        selectedChat.readings = DomainLexicon.shared.readings
        chat = selectedChat
        do {
            try await Diagnostics.measure("chargement de \(spec.title) (chat)", "chat") {
                try await selectedChat.start(history: document == nil ? messages : [], grounded: document != nil,
                                             settings: AIChatSettingsStore.load(spec.id))
            }
            if Task.isCancelled {
                await selectedChat.stop()
                return
            }
            ready = true
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func selectModel(_ spec: ModelSpec) {
        guard selectedModelID != spec.id, downloads.installed.contains(spec.id), !loading, answering == nil else { return }
        let oldChat = chat
        selectedModelID = spec.id
        if let index = conversations.firstIndex(where: { $0.id == selectedConversation }) {
            conversations[index].modelID = spec.id
            saveConversations()
        }
        ready = false
        loading = true
        modelSwitch = Task {
            await oldChat.stop()
            guard !Task.isCancelled else { return }
            await startSelectedModel()
        }
    }

    private func switchConversation(to id: UUID) {
        guard id != selectedConversation else { return }
        save()
        let previousModelID = selectedModelID
        selectedConversation = id
        let selected = conversations.first(where: { $0.id == id })
        selectedModelID = selected?.modelID ?? ModelSpec.qwen3vl4b.id
        messages = selected?.messages ?? []
        error = nil
        if previousModelID == selectedModelID { Task { await chat.reset() } }
        else {
            let oldChat = chat
            ready = false
            loading = true
            modelSwitch = Task {
                await oldChat.stop()
                guard !Task.isCancelled else { return }
                await startSelectedModel()
            }
        }
    }

    private func newConversation() {
        save()
        let conversation = Conversation(title: "Nouveau chat", modelID: selectedModelID)
        conversations.insert(conversation, at: 0)
        selectedConversation = conversation.id
        messages = []
        error = nil
        saveConversations()
        Task { await chat.reset() }
    }

    private func bubble(_ m: QwenChat.Message, index: Int) -> some View {
        let mine = m.role == .user
        let streaming = answering != nil && index == messages.count - 1
        return HStack {
            if mine { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 8) {
                // Gras, italique, code et liens du Markdown des réponses ; retours à la ligne gardés.
                Text(Self.rendered(m.text.isEmpty ? "…" : m.text)).textSelection(.enabled)
                if !mine, let openPage, let document {
                    let links = citedLinks(m, document: document)
                    if !links.pages.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(links.pages, id: \.self) { page in
                                Button("p. \(document.pageLabel(page))") { openPage(page) }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    if let note = links.note {
                        Text(note).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if !mine, !streaming, !m.text.isEmpty { answerActions(m, index: index) }
            }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(mine ? Atelier.Tint.ai.opacity(0.25) : Atelier.surfaceHigh,
                            in: RoundedRectangle(cornerRadius: Atelier.corner(14), style: .continuous))
                .contextMenu {
                    Button { copy(m.text) } label: { Label("Copier", systemImage: "doc.on.doc") }
                    if mine {
                        Button { draft = m.text } label: { Label("Reprendre dans le champ", systemImage: "pencil") }
                    }
                }
            if !mine { Spacer(minLength: 60) }
        }
    }

    /// Actions sous une réponse (#chat de la fenêtre OCR) : copier, relancer, note, lire, partager.
    private func answerActions(_ m: QwenChat.Message, index: Int) -> some View {
        HStack(spacing: 14) {
            Button { copy(m.text) } label: { Image(systemName: "doc.on.doc") }
                .accessibilityLabel("Copier la réponse")
            if index == messages.count - 1, index > 0 {
                Button { regenerate() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(!ready || answering != nil)
                    .accessibilityLabel("Relancer la réponse")
            }
            if let saveToNotes {
                Button { saveToNotes(m.text); show(String(localized: "Ajouté aux notes de la page")) } label: { Image(systemName: "note.text.badge.plus") }
                    .accessibilityLabel("Ajouter aux notes de la page")
            }
            Button { speak(m.text) } label: { Image(systemName: Self.speaker.isSpeaking ? "stop.circle" : "speaker.wave.2") }
                .accessibilityLabel("Lire à voix haute")
            // Feuille de partage présentée par UIKit : `ShareLink` ne s'ouvrait pas depuis le panneau (recette 62).
            Button { ShareSheetPresenter.present([m.text]) } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Partager la réponse")
        }
        .font(.caption)
        .buttonStyle(.plain)
        .foregroundStyle(Atelier.textSecondary)
    }

    /// Questions types quand la conversation est vide (#37) : un toucher les envoie.
    private var suggestions: some View {
        let page = focusPage.map { String(localized: "la page \($0)") } ?? String(localized: "ce passage")
        let list = document == nil
            ? [String(localized: "Explique la différence entre は et が"), String(localized: "Comment lire 天井 ?"), String(localized: "Donne 5 mots du bâtiment en japonais")]
            : [String(localized: "Résume \(page)"), String(localized: "Explique les formules de \(page)"), String(localized: "Quels mots techniques apprendre dans \(page) ?")]
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(list, id: \.self) { text in
                Button { draft = text; send() } label: {
                    Label(text, systemImage: "sparkles").font(.caption).multilineTextAlignment(.leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// Raccourcis au-dessus du champ, défilables (la fenêtre OCR est étroite).
    private var chips: some View {
        let page = focusPage.map { "p. \($0)" }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let page {
                    chip(String(localized: "Insérer \(page)"), "text.insert") {
                        if !draft.contains(page) { draft = draft.isEmpty ? page + " : " : page + " : " + draft }
                    }
                }
                chip(String(localized: "Résumer"), "text.alignleft") { draft = String(localized: "Résume \(page ?? String(localized: "ce passage")) : de quoi parle-t-elle, puis les points clés.") }
                chip(String(localized: "Formules"), "function") { draft = String(localized: "Explique pas à pas chaque formule de \(page ?? String(localized: "ce passage")), avec un exemple chiffré.") }
                chip(String(localized: "Vocabulaire"), "character.book.closed.ja") { draft = String(localized: "Liste les mots techniques japonais de \(page ?? String(localized: "ce passage")) avec lecture et sens.") }
                chip(String(localized: "Plus simple"), "tortoise") { draft = String(localized: "Réexplique ta dernière réponse plus simplement, avec un exemple.") }
                chip(String(localized: "Plus court"), "scissors") { draft = String(localized: "Résume ta dernière réponse en trois lignes.") }
            }
            .padding(.horizontal, 12)
        }
    }

    private func chip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.caption2.weight(.semibold))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Atelier.surfaceHigh, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(answering != nil)
    }

    /// État du modèle et durée de la dernière réponse.
    private var statusLine: some View {
        let name = selectedSpec.id == ModelSpec.qwen35chat4b.id ? "Qwen3.5" : "Qwen3-VL"
        let settings = AIChatSettingsStore.load(selectedModelID)
        var parts = [loading ? String(localized: "Chargement de \(name)…") : ready ? String(localized: "\(name) prêt") : String(localized: "\(name) indisponible")]
        if settings.instructions != nil { parts.append(String(localized: "consigne perso")) }
        if answering != nil { parts.append(String(localized: "réponse en cours…")) }
        else if let lastDuration { parts.append(String(localized: "dernière réponse en \(Int(lastDuration.rounded())) s")) }
        return Text(parts.joined(separator: " · "))
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 6)
    }

    static func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        show(String(localized: "Copié"))
    }

    private func speak(_ text: String) {
        if Self.speaker.isSpeaking { Self.speaker.stopSpeaking(at: .immediate); return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        Self.speaker.speak(utterance)
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { if toast == message { toast = nil } } }
    }

    /// Relance la dernière question (réponse précédente remplacée).
    private func regenerate() {
        guard answering == nil, messages.count >= 2, messages[messages.count - 2].role == .user else { return }
        let question = messages[messages.count - 2].text
        messages.removeLast(2)
        draft = question
        send()
    }

    private func renameConversation() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let i = conversations.firstIndex(where: { $0.id == selectedConversation }) else { return }
        conversations[i].title = String(title.prefix(60))
        saveConversations()
    }

    /// Supprime la conversation affichée (après confirmation) ; une autre prend sa place, sinon une vide.
    private func deleteConversation() {
        guard document != nil else {
            messages = []
            save()
            Task { await chat.reset() }
            return
        }
        guard let id = selectedConversation else { return }
        deleteConversations([id])
    }

    /// Supprime plusieurs conversations (la feuille a déjà demandé confirmation). Si l'affichée en fait partie,
    /// une restante prend sa place, sinon une conversation vide.
    private func deleteConversations(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let removesShown = selectedConversation.map(ids.contains) ?? false
        conversations.removeAll { ids.contains($0.id) }
        guard removesShown else {
            if conversations.isEmpty { conversations = [Conversation(title: "Nouveau chat", modelID: selectedModelID)] }
            saveConversations()
            return
        }
        if conversations.isEmpty { conversations = [Conversation(title: "Nouveau chat", modelID: selectedModelID)] }
        let next = conversations[0]
        selectedConversation = next.id
        messages = next.messages
        saveConversations()
        if next.modelID == selectedModelID { Task { await chat.reset() } }
        else {
            let oldChat = chat
            selectedModelID = next.modelID
            ready = false
            loading = true
            modelSwitch = Task {
                await oldChat.stop()
                guard !Task.isCancelled else { return }
                await startSelectedModel()
            }
        }
    }

    /// Liens des pages consultées (R4) : suivis à travers les modifications des pages ; un lien qu'on ne peut plus
    /// suivre avec certitude est retiré, avec une explication. Le texte de la réponse n'est jamais réécrit.
    private func citedLinks(_ m: QwenChat.Message, document: LibraryDocument) -> (pages: [Int], note: String?) {
        let current = (try? database?.layoutVersion(documentId: document.id)) ?? 0
        if let pages = m.pages, let version = m.layoutVersion {
            guard version != current else { return (pages, nil) }
            guard let mapping = try? database?.pageMapping(documentId: document.id, fromVersion: version) else {
                return ([], String(localized: "Le document a été remplacé depuis cette réponse : liens des pages retirés."))
            }
            let followed = pages.compactMap(mapping.target(of:))
            return (followed, followed.count < pages.count ? String(localized: "Certaines pages citées ont été supprimées depuis.") : nil)
        }
        // Message enregistré avant le suivi des pages : ses numéros ne valent que si rien n'a changé depuis.
        guard current == 0 else { return ([], String(localized: "Pages modifiées depuis cette réponse : liens retirés.")) }
        return (citedPages(in: m.text, document: document), nil)
    }

    private func citedPages(in answer: String, document: LibraryDocument) -> [Int] {
        // Les réponses déjà enregistrées gardent le libellé de la langue de l'époque.
        let markers = ["Pages consultées : ", String(localized: "Pages consultées : ")]
        guard let range = markers.lazy.compactMap({ answer.range(of: $0, options: .backwards) }).first else { return [] }
        return answer[range.upperBound...].split(separator: ",").compactMap { part in
            let label = part.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "p. ", with: "")
            return (0..<document.pageCount).first { document.pageLabel($0) == label }
        }
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, ready, answering == nil else { return }
        draft = ""
        error = nil
        messages.append(.init(role: .user, text: prompt))
        messages.append(.init(role: .assistant, text: ""))
        save()
        let index = messages.count - 1
        answering = Task {
            let start = Date()
            do {
                if let document {
                    await chat.reset()
                    // Une nouvelle question cherche dans le livre par ses propres termes. Seule une vraie
                    // relance peut utiliser le dernier échange pour lever une référence comme « ça ».
                    let previous = Array(messages.dropLast(2).suffix(2))
                    let followUp = Self.isFollowUp(prompt)
                    let requestedPages = DocumentKnowledge.explicitPages(prompt, document: document)
                    var passages = await Task.detached(priority: .userInitiated) {
                        DocumentKnowledge.passages(for: document, question: prompt, japaneseTerms: "")
                    }.value
                    if requestedPages.isEmpty && (passages.first?.score ?? 0) < 2 {
                        var terms = ""
                        let lastExchange = followUp ? previous.map { $0.text }.joined(separator: "\n").prefix(500) : ""
                        let lookup = "Question actuelle : \(prompt)\n\(lastExchange.isEmpty ? "" : "Dernier échange pour résoudre les pronoms seulement : \(lastExchange)\n")Donne uniquement 3 à 8 mots-clés japonais pour retrouver la réponse dans le manuel. Aucun commentaire."
                        for try await chunk in chat.stream(lookup) {
                            terms += chunk
                        }
                        await chat.reset()
                        let searchTerms = String(terms.prefix(120))
                        passages = await Task.detached(priority: .userInitiated) {
                            DocumentKnowledge.passages(for: document, question: prompt, japaneseTerms: searchTerms)
                        }.value
                    }
                    // Recette 1.5.6 (5.3) : rien trouvé par mots-clés → la page affichée (sinon la dernière lue) sert
                    // d'extrait ; l'IA sait ainsi sur quel document et quelle page on l'interroge.
                    if passages.isEmpty && requestedPages.isEmpty {
                        let shown = focusPage.flatMap { label in (0..<document.pageCount).first { document.pageLabel($0) == label } }
                            ?? document.lastPageIndex
                        let open = await Task.detached(priority: .userInitiated) { DocumentKnowledge.pagePassage(document, page: shown) }.value
                        passages = open.map { [$0] } ?? []
                    }
                    let dialogue = followUp ? previous.map { ($0.role == .user ? "Utilisateur : " : "Assistant : ") + $0.text }.joined(separator: "\n").prefix(800) : ""
                    let question = dialogue.isEmpty ? prompt : "Dernier échange (contexte, pas une source) :\n\(dialogue)\nQuestion actuelle : \(prompt)"
                    if passages.isEmpty && !requestedPages.isEmpty {
                        messages[index].text = String(localized: "La page demandée n'a pas encore de lecture OvisOCR2 disponible. Relance sa lecture dans l'onglet Texte, puis réessaie.")
                    } else if passages.isEmpty {
                        // T2 (10/11) : aucune page du livre ne correspond ; l'IA répond avec ses connaissances
                        // générales en le signalant, au lieu de refuser.
                        for try await chunk in chat.stream(question, context: BookChatPrompt.generalContext(title: document.title)) { messages[index].text += chunk }
                        // Revue D-07 : réponse sans page, mais liée à la version actuelle (pas de mention « liens retirés »).
                        messages[index].pages = []
                        messages[index].layoutVersion = (try? database?.layoutVersion(documentId: document.id)) ?? 0
                    } else {
                        let report = DocumentAnalysisService.shared.report(for: document.id)
                        let sources: String = passages.map { passage in
                            let checked = report?.pages[passage.page]
                            let confidence = checked.map { $0.lines > $0.unchecked
                                ? "Concordance des lectures OCR : \(Int($0.reliability * 100)) %."
                                : "Lecture non recoupée." } ?? "Lecture OvisOCR2 non recoupée."
                            return "[p. \(document.pageLabel(passage.page))] \(confidence)\n\(passage.text)"
                        }.joined(separator: "\n\n")
                        let context = BookChatPrompt.context(sources: sources, title: document.title)
                        for try await chunk in chat.stream(question, context: context) { messages[index].text += chunk }
                        // T2 (10/11) : seules les pages réellement citées par la réponse sont listées et ouvrables.
                        let cited = BookChatPrompt.listedPages(
                            in: messages[index].text,
                            passages: passages.map { (page: $0.page, label: document.pageLabel($0.page)) })
                        if !cited.isEmpty {
                            messages[index].text += "\n\n" + String(localized: "Pages consultées : ") + cited.map { "p. \(document.pageLabel($0))" }.joined(separator: ", ")
                        }
                        messages[index].pages = cited
                        messages[index].layoutVersion = (try? database?.layoutVersion(documentId: document.id)) ?? 0
                    }
                } else {
                    for try await chunk in chat.stream(prompt) { messages[index].text += chunk }
                }
                Diagnostics.remember("chat", String(localized: "✓ réponse en \(String(format: "%.1f", Date().timeIntervalSince(start))) s"))
                lastDuration = Date().timeIntervalSince(start)
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
                Diagnostics.remember("chat", String(localized: "✗ réponse : \(error.localizedDescription)"))
            }
            if messages[index].text.isEmpty { messages[index].text = String(localized: "(pas de réponse)") }
            answering = nil
            save()
        }
    }

    private func save() {
        if document != nil {
            guard let index = conversations.firstIndex(where: { $0.id == selectedConversation }) else { return }
            conversations[index].messages = messages
            if conversations[index].title == "Nouveau chat", let first = messages.first(where: { $0.role == .user }) {
                conversations[index].title = String(first.text.prefix(42))
            }
            saveConversations()
            return
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(messages).write(to: file, options: .atomic)
    }

    private func saveConversations() {
        guard let bookFile else { return }
        try? FileManager.default.createDirectory(at: bookFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(conversations).write(to: bookFile, options: .atomic)
    }

    private static func isFollowUp(_ question: String) -> Bool {
        let lower = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["et ça", "et cela", "ce point", "cette partie", "comment ça", "qu'en est-il"].contains {
            lower.hasPrefix($0)
        }
    }
}

/// Feuille de partage d'iOS présentée sur le contrôleur visible le plus haut (fenêtre OCR, feuilles empilées) :
/// `ShareLink` et une feuille SwiftUI ne s'ouvraient pas depuis le panneau intégré.
enum ShareSheetPresenter {
    @MainActor
    static func present(_ items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad : la feuille s'ancre au centre de l'écran visible (pas de bouton UIKit à viser).
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}

/// Conversations d'un livre (recette 1.3.2 (62)) : toucher en ouvre une ; « Sélectionner » permet d'en cocher
/// plusieurs et de les supprimer après une confirmation ; balayer ou appui long pour renommer ou supprimer une seule.
struct ConversationListSheet: View {
    let items: [(id: UUID, title: String, count: Int)]
    let selected: UUID?
    var onOpen: (UUID) -> Void
    var onRename: (UUID) -> Void
    var onDelete: (Set<UUID>) -> Void
    var onNew: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .inactive
    @State private var picked: Set<UUID> = []
    @State private var pending: Set<UUID> = []
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            List(selection: $picked) {
                ForEach(items, id: \.id) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).lineLimit(1)
                            Text("\(item.count / 2) échange\(item.count / 2 > 1 ? "s" : "")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.id == selected { Image(systemName: "checkmark").foregroundStyle(Atelier.Tint.ai) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if editMode == .inactive { onOpen(item.id) } }
                    .swipeActions {
                        Button(role: .destructive) { pending = [item.id]; confirm = true } label: { Label("Supprimer", systemImage: "trash") }
                        Button { onRename(item.id) } label: { Label("Renommer", systemImage: "pencil") }
                    }
                    .contextMenu {
                        Button { onRename(item.id) } label: { Label("Renommer", systemImage: "pencil") }
                        Button(role: .destructive) { pending = [item.id]; confirm = true } label: { Label("Supprimer", systemImage: "trash") }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editMode == .active ? String(localized: "Terminé") : String(localized: "Sélectionner")) {
                        withAnimation { editMode = editMode == .active ? .inactive : .active }
                        picked = []
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if editMode == .active {
                        Button("Supprimer (\(picked.count))", role: .destructive) { pending = picked; confirm = true }
                            .disabled(picked.isEmpty)
                    } else {
                        Button { onNew() } label: { Label("Nouveau chat", systemImage: "square.and.pencil") }
                    }
                }
            }
            .centeredConfirmation(isPresented: $confirm,
                                  title: pending.count > 1 ? String(localized: "Supprimer \(pending.count) conversations ?") : String(localized: "Supprimer cette conversation ?"),
                                  message: String(localized: "Leurs messages seront effacés de l'iPad."), confirm: String(localized: "Supprimer")) {
                onDelete(pending)
                picked.subtract(pending)
                pending = []
                editMode = .inactive
            }
        }
    }
}

/// Confirmation centrée dans la vue qui la porte (pas dans l'écran entier) : fond assombri, carte au milieu,
/// « Annuler » (Échap) et l'action destructive (↩). Animée ; fondu seul avec « Réduire les animations ».
private struct CenteredConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let confirm: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    Atelier.scrim.opacity(0.35).ignoresSafeArea()
                        .onTapGesture { isPresented = false }
                    VStack(spacing: 12) {
                        Image(systemName: "trash").font(.title2).foregroundStyle(.red)
                        Text(title).font(.headline).multilineTextAlignment(.center)
                        Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        HStack(spacing: 10) {
                            Button("Annuler") { isPresented = false }
                                .buttonStyle(.bordered)
                                .keyboardShortcut(.cancelAction)
                            Button(confirm, role: .destructive) { isPresented = false; action() }
                                .buttonStyle(.borderedProminent).tint(.red)
                                .keyboardShortcut(.defaultAction)
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .frame(maxWidth: 320)
                    .background(Atelier.material(.regularMaterial), in: RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous))
                    .atelierShapeShadow(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous), opacity: 0.3, radius: 16, y: 6)
                    .padding(16)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                    .accessibilityAddTraits(.isModal)
                }
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.85), value: isPresented)
    }
}

extension View {
    func centeredConfirmation(isPresented: Binding<Bool>, title: String, message: String, confirm: String,
                              action: @escaping () -> Void) -> some View {
        modifier(CenteredConfirmation(isPresented: isPresented, title: title, message: message, confirm: confirm, action: action))
    }
}
