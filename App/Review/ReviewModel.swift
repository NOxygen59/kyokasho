// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import DictionaryKit
import Foundation
import ReaderCore
import ReviewKit
import UIKit

/// Cartes de révision côté app : base `Review/`, réglages, ajout depuis le dictionnaire.
@MainActor
final class ReviewModel: ObservableObject {
    let store: ReviewStore
    private let appDatabase: AppDatabase

    @Published private(set) var counts = ReviewStore.Counts()
    @Published private(set) var decks: [Deck] = []
    @Published private(set) var templates: [NoteTemplate] = []
    /// Clés (`mot|lecture`) des cartes existantes, pour afficher ✓ dans les listes.
    @Published private(set) var keys: Set<String> = []
    @Published var settings: ReviewSettings {
        didSet {
            guard settings != oldValue else { return }
            try? appDatabase.setStoredValue(settings, forKey: "review.settings")
            refresh()
        }
    }

    enum AddResult: Equatable { case added, duplicate, failed }

    init(appDatabase: AppDatabase) {
        self.appDatabase = appDatabase
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Kyokasho/Review", isDirectory: true)
        // Dernier recours : base en mémoire plutôt que de planter.
        if let opened = try? ReviewStore.open(directory: directory) {
            store = opened
        } else {
            store = try! ReviewStore.inMemory()
        }
        settings = (try? appDatabase.storedValue(ReviewSettings.self, forKey: "review.settings")) ?? ReviewSettings()
        refresh()
    }

    func refresh() {
        decks = (try? store.decks()) ?? []
        templates = (try? store.templates()) ?? []
        counts = (try? store.counts(settings: settings)) ?? ReviewStore.Counts()
    }

    /// Met à jour `keys` pour une liste de mots affichés dans le dictionnaire.
    func loadKeys(_ candidates: [String]) {
        let found = (try? store.existingKeys(candidates)) ?? []
        keys.formUnion(found)
    }

    /// Carte supprimée : le mot redevient ajoutable (＋).
    func forgetKey(_ key: String) { keys.remove(key) }

    var defaultDeckId: Int64? { settings.defaultDeckId.flatMap { id in decks.first { $0.id == id }?.id } ?? decks.first?.id }
    var defaultTemplate: NoteTemplate? {
        settings.defaultTemplateId.flatMap { id in templates.first { $0.id == id } } ?? templates.first
    }

    /// Cartes en cours d'ajout (audio en téléchargement) : un double clic ne crée pas de doublon.
    private var pending: Set<String> = []

    /// Ajout depuis le dictionnaire : le doublon se voit tout de suite, l'audio est cherché ensuite.
    /// Renvoie un message à afficher, ou `nil`.
    func add(_ term: TermResult, sentence: String?, source: String?, image: Data?, documentId: String?, page: Int?,
             dictionary: DictionaryModel) -> String? {
        let key = StudyCard.key(expression: term.expression, reading: term.reading)
        if keys.contains(key) || pending.contains(key) || (try? store.card(key: key)) != nil {
            keys.insert(key)
            return "Déjà dans tes cartes"
        }
        pending.insert(key)
        let wantsAudio = settings.includeAudio
        Task {
            let audio = wantsAudio ? await dictionary.audioData(term: term.expression, reading: term.reading) : nil
            addCard(term: term, sentence: sentence, source: source, imageData: image, audio: audio,
                    documentId: documentId, page: page)
            pending.remove(key)
        }
        return nil
    }

    /// Le lot reste dans Kyōkasho, exportable en Anki depuis le document.
    /// Une seule transaction hors du fil principal, puis un seul rafraîchissement.
    func addPageCards(_ fields: [[String: String]], documentId: String, page: Int) async throws -> Int {
        guard let deckId = defaultDeckId, let templateId = defaultTemplate?.id else {
            throw NSError(domain: "Kyokasho.Cartes", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Choisis un paquet et un modèle dans les réglages des cartes."])
        }
        let cards = fields.map { fields in
            StudyCard(deckId: deckId, templateId: templateId,
                      key: StudyCard.key(expression: fields["Mot"] ?? "", reading: fields["Lecture"] ?? ""),
                      fields: fields, tags: ["kyokasho", "lexique"], sourceDocumentId: documentId, sourcePage: page)
        }
        let store = store
        let added = try await Task.detached(priority: .userInitiated) { try store.addMissing(cards) }.value
        keys.formUnion(cards.map(\.key))
        refresh()
        return added
    }

    /// Ajoute une carte. `imageData` (JPEG) et `audio` vont dans les médias selon les réglages.
    @discardableResult
    func addCard(term: TermResult, sentence: String?, source: String?, imageData: Data?, audio: (Data, String)?,
                 documentId: String?, page: Int?) -> AddResult {
        let key = StudyCard.key(expression: term.expression, reading: term.reading)
        if keys.contains(key) || (try? store.card(key: key)) != nil {
            keys.insert(key)
            return .duplicate
        }
        guard let deckId = defaultDeckId, let template = defaultTemplate, let templateId = template.id else { return .failed }
        var fields = CardFields.make(term: term, sentence: sentence, source: source)
        if settings.includeImage, let imageData, let name = try? store.addMedia(imageData, extension: "jpg") {
            fields["Image"] = "<img src=\"\(name)\">"
        }
        if settings.includeAudio, let (data, ext) = audio, let name = try? store.addMedia(data, extension: ext) {
            fields["Audio"] = "[sound:\(name)]"
        }
        let card = StudyCard(deckId: deckId, templateId: templateId, key: key, fields: fields,
                             tags: ["kyokasho"], sourceDocumentId: documentId, sourcePage: page)
        guard (try? store.add(card)) != nil else { return .failed }
        keys.insert(key)
        if settings.sendToAnkiMobile,
           let url = AnkiExport.ankiMobileURL(fields: fields, fieldNames: template.fieldNames,
                                              noteType: settings.ankiMobileNoteType, deck: settings.ankiMobileDeck,
                                              tags: card.tags) {
            UIApplication.shared.open(url)
        }
        refresh()
        return .added
    }
}
