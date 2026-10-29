// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import AVFoundation
import Combine
import DictionaryKit
import Foundation
import ReaderCore

/// Dictionnaires de l'app : base, import en tâche de fond, recherche, profils, audio.
@MainActor
final class DictionaryModel: ObservableObject {
    struct SavedEntry: Codable, Hashable, Identifiable {
        enum Kind: String, Codable { case word, kanji }
        var kind: Kind
        var expression: String
        var reading: String
        var id: String { kind.rawValue + "|" + expression + "|" + reading }
    }

    struct Notebook: Codable, Equatable {
        var saved: [SavedEntry] = []
        var recent: [SavedEntry] = []
    }

    let database: DictionaryDatabase?
    let translator: Translator?
    private let appDatabase: AppDatabase
    /// Dossier des fichiers audio locaux (visible dans l'app Fichiers : Kyōkasho › Audio).
    let audioFolder: URL

    @Published private(set) var dictionaries: [DictionaryInfo] = []
    @Published private(set) var importState: ImportState?
    @Published private(set) var notebook: Notebook {
        didSet {
            guard notebook != oldValue else { return }
            try? appDatabase.setStoredValue(notebook, forKey: "dictionary.notebook")
        }
    }
    @Published var profiles: DictionaryProfiles {
        didSet {
            guard profiles != oldValue else { return }
            try? appDatabase.setStoredValue(profiles, forKey: "dictionary.profiles")
        }
    }
    @Published var lastError: String?

    struct ImportState: Equatable {
        var fileName: String
        var step: String
        var fraction: Double
    }

    private var importTask: Task<Void, Never>?
    private var player: AVAudioPlayer?

    var profile: DictionaryProfile {
        get { profiles.active }
        set { profiles.active = newValue }
    }

    var hasTermDictionaries: Bool { dictionaries.contains { $0.enabled && $0.termCount > 0 } }

    init(appDatabase: AppDatabase) {
        self.appDatabase = appDatabase
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kyokasho", isDirectory: true)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        audioFolder = documents.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
        // Restauration inachevée (#51) : ne rien créer à la place de la bibliothèque mise de côté.
        let db = LibraryBackupService.restoreBlocked ? nil
            : try? DictionaryDatabase.open(directory: support.appendingPathComponent("Dictionaries", isDirectory: true))
        database = db
        translator = db.map { Translator(database: $0) }
        profiles = (try? appDatabase.storedValue(DictionaryProfiles.self, forKey: "dictionary.profiles")) ?? DictionaryProfiles()
        notebook = (try? appDatabase.storedValue(Notebook.self, forKey: "dictionary.notebook")) ?? Notebook()
        reload()
    }

    func reload() {
        dictionaries = (try? database?.dictionaries()) ?? []
        translator?.invalidate()
    }

    // MARK: Import

    func importDictionaries(_ urls: [URL]) {
        guard let database, importTask == nil else { return }
        importTask = Task.detached(priority: .userInitiated) { [weak self] in
            for url in urls {
                if Task.isCancelled { break }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let name = url.lastPathComponent
                await MainActor.run { self?.importState = ImportState(fileName: name, step: "Ouverture", fraction: 0) }
                var lastReport = Date.distantPast
                do {
                    try DictionaryImporter(database: database).importDictionary(at: url) { p in
                        // Pas plus de 10 mises à jour d'écran par seconde.
                        guard Date().timeIntervalSince(lastReport) > 0.1 || p.fraction >= 1 else { return }
                        lastReport = Date()
                        Task { @MainActor in self?.importState = ImportState(fileName: name, step: p.step, fraction: p.fraction) }
                    }
                } catch {
                    await MainActor.run { self?.lastError = "\(name) : \(error.localizedDescription)" }
                }
            }
            await MainActor.run {
                self?.importState = nil
                self?.importTask = nil
                self?.reload()
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    func delete(_ dictionary: DictionaryInfo) {
        guard let database, let id = dictionary.id else { return }
        importState = ImportState(fileName: dictionary.title, step: "Suppression", fraction: 0)
        Task.detached(priority: .userInitiated) { [weak self] in
            try? database.deleteDictionary(id: id)
            await MainActor.run {
                self?.importState = nil
                self?.reload()
            }
        }
    }

    func setEnabled(_ dictionary: DictionaryInfo, _ enabled: Bool) {
        guard let id = dictionary.id else { return }
        try? database?.setEnabled(enabled, dictionaryId: id)
        reload()
    }

    static let firstLanguageKey = "dictionary.firstLanguage"

    /// Langue des définitions qui passe en premier (#50, D2) : réordonne les dictionnaires du catalogue.
    func applyFirstLanguage() {
        let raw = UserDefaults.standard.string(forKey: Self.firstLanguageKey) ?? CatalogEntry.Language.french.rawValue
        let first = CatalogEntry.Language(rawValue: raw) ?? .french
        let list = dictionaries
        let order = DictionaryCatalog.ordered(titles: list.map(\.title), first: first)
        guard order != Array(list.indices) else { return }
        try? database?.setOrder(order.compactMap { list[$0].id })
        reload()
    }

    func move(from source: IndexSet, to destination: Int) {
        var list = dictionaries
        list.move(fromOffsets: source, toOffset: destination)
        try? database?.setOrder(list.compactMap(\.id))
        reload()
    }

    // MARK: Recherche (hors du fil principal)

    func lookup(_ text: String) async -> [TermResult] {
        guard let translator else { return [] }
        let options = profile.lookup
        return await Task.detached(priority: .userInitiated) {
            (try? translator.findTerms(text, options: options)) ?? []
        }.value
    }

    func words(startingWith prefix: String) async -> [DictionaryWord] {
        guard let database else { return [] }
        let ids = Set(dictionaries.filter { $0.enabled && $0.termCount > 0
            && !profile.lookup.excludedDictionaryIds.contains($0.id ?? -1) }.compactMap(\.id))
        return await Task.detached(priority: .userInitiated) {
            (try? database.words(startingWith: prefix, dictionaryIds: ids)) ?? []
        }.value
    }

    func isSaved(_ entry: SavedEntry) -> Bool { notebook.saved.contains(entry) }

    func toggleSaved(_ entry: SavedEntry) {
        if let index = notebook.saved.firstIndex(of: entry) {
            notebook.saved.remove(at: index)
        } else {
            notebook.saved.insert(entry, at: 0)
        }
    }

    func remember(_ entry: SavedEntry) {
        notebook.recent.removeAll { $0 == entry }
        notebook.recent.insert(entry, at: 0)
        if notebook.recent.count > 80 { notebook.recent.removeLast(notebook.recent.count - 80) }
    }

    func kanji(_ character: String) async -> KanjiResult? {
        guard let translator else { return nil }
        return await Task.detached(priority: .userInitiated) { try? translator.findKanji(character) }.value
    }

    func segment(_ text: String) async -> [Translator.Segment] {
        guard let translator else { return [] }
        let options = profile.lookup
        return await Task.detached(priority: .utility) { (try? translator.segment(text, options: options)) ?? [] }.value
    }

    func renderer(canAddCards: Bool = false, added: Set<String> = []) -> GlossaryRenderer {
        var options = profile.display
        options.canAddCards = canAddCards
        let translator = translator
        var renderer = GlossaryRenderer(options: options, inflectionName: { id in translator?.inflectionName(id) ?? id })
        renderer.addedTermIds = added
        renderer.palette = Theme.cssPalette
        return renderer
    }

    // MARK: Audio

    enum AudioResult { case played, notFound }

    /// Essaie les sources dans l'ordre du profil ; en ligne seulement à ta demande (bouton ▶︎).
    @discardableResult
    func playAudio(term: String, reading: String) async -> AudioResult {
        guard let (data, _) = await audioData(term: term, reading: reading), play(data) else { return .notFound }
        return .played
    }

    /// Premier enregistrement trouvé (sources dans l'ordre du profil) et son extension (mp3 par défaut).
    func audioData(term: String, reading: String) async -> (Data, String)? {
        for source in profile.audioSources where source.enabled {
            for candidate in source.resolve(term: term, reading: reading) {
                let data: Data?
                var ext = (candidate as NSString).pathExtension.lowercased()
                switch source.kind {
                case .localFolder:
                    // Lecture du disque hors du fil principal (le popup reste fluide).
                    let file = audioFolder.appendingPathComponent(candidate)
                    data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: file) }.value
                case .url:
                    guard let url = URL(string: candidate) else { continue }
                    ext = url.pathExtension.lowercased()
                    data = await Self.download(url)
                }
                if let data, await Task.detached(priority: .userInitiated, operation: { AVAudioPlayerCheck.isPlayable(data) }).value {
                    return (data, ["mp3", "m4a", "ogg", "opus", "wav", "aac"].contains(ext) ? ext : "mp3")
                }
            }
        }
        return nil
    }

    nonisolated static func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 1000 else { return nil }
        // JapanesePod101 renvoie un enregistrement « audio introuvable » de 52 288 octets.
        if url.host?.contains("languagepod101") == true, data.count == 52288 { return nil }
        return data
    }

    private func play(_ data: Data) -> Bool {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        guard let player = try? AVAudioPlayer(data: data) else { return false }
        self.player = player
        return player.play()
    }
}

/// Un fichier est gardé seulement si AVAudioPlayer sait le lire (évite les pages d'erreur HTML).
enum AVAudioPlayerCheck {
    static func isPlayable(_ data: Data) -> Bool { (try? AVAudioPlayer(data: data)) != nil }
}
