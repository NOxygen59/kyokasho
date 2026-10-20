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
    let database: DictionaryDatabase?
    let translator: Translator?
    private let appDatabase: AppDatabase
    /// Dossier des fichiers audio locaux (visible dans l'app Fichiers : Kyōkasho › Audio).
    let audioFolder: URL

    @Published private(set) var dictionaries: [DictionaryInfo] = []
    @Published private(set) var importState: ImportState?
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
        let db = try? DictionaryDatabase.open(directory: support.appendingPathComponent("Dictionaries", isDirectory: true))
        database = db
        translator = db.map { Translator(database: $0) }
        profiles = (try? appDatabase.storedValue(DictionaryProfiles.self, forKey: "dictionary.profiles")) ?? DictionaryProfiles()
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

    func kanji(_ character: String) async -> KanjiResult? {
        guard let translator else { return nil }
        return await Task.detached(priority: .userInitiated) { try? translator.findKanji(character) }.value
    }

    func segment(_ text: String) async -> [Translator.Segment] {
        guard let translator else { return [] }
        let options = profile.lookup
        return await Task.detached(priority: .utility) { (try? translator.segment(text, options: options)) ?? [] }.value
    }

    func renderer(canAddCards: Bool = false) -> GlossaryRenderer {
        var options = profile.display
        options.canAddCards = canAddCards
        let translator = translator
        return GlossaryRenderer(options: options, inflectionName: { id in translator?.inflectionName(id) ?? id })
    }

    // MARK: Audio

    enum AudioResult { case played, notFound }

    /// Essaie les sources dans l'ordre du profil ; en ligne seulement à ta demande (bouton ▶︎).
    @discardableResult
    func playAudio(term: String, reading: String) async -> AudioResult {
        for source in profile.audioSources where source.enabled {
            for candidate in source.resolve(term: term, reading: reading) {
                let data: Data?
                switch source.kind {
                case .localFolder:
                    data = try? Data(contentsOf: audioFolder.appendingPathComponent(candidate))
                case .url:
                    guard let url = URL(string: candidate) else { continue }
                    data = await Self.download(url)
                }
                if let data, play(data) { return .played }
            }
        }
        return .notFound
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
