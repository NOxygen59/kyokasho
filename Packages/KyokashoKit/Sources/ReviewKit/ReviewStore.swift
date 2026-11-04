// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB

/// Base des cartes (fichier à part : `review.sqlite` + dossier `Media`).
public final class ReviewStore: @unchecked Sendable {
    public let writer: any DatabaseWriter

    /// Pages insérées avant celles d'un document (« Ajouter des pages… ») : page d'origine des cartes décalée.
    public func shiftSourcePages(documentId: String, by offset: Int) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE card SET sourcePage = sourcePage + ? WHERE sourceDocumentId = ? AND sourcePage IS NOT NULL",
                           arguments: [offset, documentId])
        }
    }
    /// Instantané sans limite de pagination ; seuls les liens vers les pages sont capturés.
    public func sourcePages(documentId: String) throws -> [Int64: Int] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, sourcePage FROM card WHERE sourceDocumentId = ? AND sourcePage IS NOT NULL", arguments: [documentId])
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["id"] as Int64, $0["sourcePage"] as Int) })
        }
    }

    /// Installe des valeurs finales : une reprise ne touche ni la planification FSRS ni l'historique.
    /// `nil` = carte gardée **sans page** (page retirée du document, #49) ; elle reste liée à son document, ce qui la
    /// distingue d'une carte sans document. Omettre une carte laisserait son ancienne page : toutes les cartes du
    /// document concernées par l'opération doivent donc figurer dans `pages`.
    public func setSourcePages(documentId: String, pages: [Int64: Int?]) throws {
        try writer.write { db in
            for (id, page) in pages {
                try db.execute(sql: "UPDATE card SET sourcePage = ? WHERE id = ? AND sourceDocumentId = ?", arguments: [page, id, documentId])
                guard db.changesCount == 1 else {
                    throw NSError(domain: "Kyokasho.PageShift", code: 3, userInfo: [NSLocalizedDescriptionKey: String(localized: "Carte absente ou associée à un autre document.", bundle: .main)])
                }
            }
        }
    }

    /// Restauration de pages (#49) : rattache une carte détachée à sa page revenue, **seulement** si elle est toujours
    /// sans page et liée au même document (une carte rattachée ailleurs entre-temps n'est pas touchée). Rejouable.
    /// Ne touche ni FSRS ni l'historique. Renvoie le nombre de cartes rattachées.
    @discardableResult
    public func reattachSourcePages(documentId: String, pages: [Int64: Int]) throws -> Int {
        try writer.write { db in
            var count = 0
            for (id, page) in pages {
                try db.execute(sql: "UPDATE card SET sourcePage = ? WHERE id = ? AND sourceDocumentId = ? AND sourcePage IS NULL",
                               arguments: [page, id, documentId])
                count += db.changesCount
            }
            return count
        }
    }

    /// Images et sons des cartes (noms de fichiers plats, comme le dossier média d'Anki).
    public let mediaRoot: URL

    init(_ writer: any DatabaseWriter, mediaRoot: URL) throws {
        self.writer = writer
        self.mediaRoot = mediaRoot
        try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
        try Self.migrator.migrate(writer)
        try seedIfNeeded()
    }

    public static func open(directory: URL) throws -> ReviewStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: directory.appendingPathComponent("review.sqlite").path)
        return try ReviewStore(pool, mediaRoot: directory.appendingPathComponent("Media", isDirectory: true))
    }

    public static func inMemory() throws -> ReviewStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-media-" + UUID().uuidString)
        return try ReviewStore(DatabaseQueue(), mediaRoot: root)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "deck") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "noteTemplate") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("fieldNames", .text).notNull()
                t.column("front", .text).notNull()
                t.column("back", .text).notNull()
                t.column("css", .text).notNull()
                t.column("modifiedAt", .datetime).notNull()
            }
            try db.create(table: "card") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deckId", .integer).notNull().references("deck", onDelete: .cascade)
                t.column("templateId", .integer).notNull().references("noteTemplate", onDelete: .restrict)
                t.column("guid", .text).notNull().unique()
                t.column("key", .text).notNull()
                t.column("fields", .text).notNull()
                t.column("tags", .text).notNull()
                t.column("sourceDocumentId", .text)
                t.column("sourcePage", .integer)
                t.column("createdAt", .datetime).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("suspended", .boolean).notNull().defaults(to: false)
                t.column("due", .datetime).notNull()
                t.column("stability", .double).notNull()
                t.column("difficulty", .double).notNull()
                t.column("elapsedDays", .double).notNull()
                t.column("scheduledDays", .double).notNull()
                t.column("learningSteps", .integer).notNull()
                t.column("reps", .integer).notNull()
                t.column("lapses", .integer).notNull()
                t.column("state", .integer).notNull()
                t.column("lastReview", .datetime)
            }
            try db.create(index: "card_key", on: "card", columns: ["key"])
            try db.create(index: "card_queue", on: "card", columns: ["deckId", "state", "due"])
            try db.create(table: "reviewLog") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("cardId", .integer).notNull().references("card", onDelete: .cascade)
                t.column("grade", .integer).notNull()
                t.column("state", .integer).notNull()
                t.column("reviewedAt", .datetime).notNull()
                t.column("elapsedDays", .double).notNull()
                t.column("scheduledDays", .double).notNull()
                t.column("stability", .double).notNull()
                t.column("difficulty", .double).notNull()
                t.column("duration", .double).notNull()
            }
            try db.create(index: "reviewLog_card", on: "reviewLog", columns: ["cardId"])
            try db.create(index: "reviewLog_date", on: "reviewLog", columns: ["reviewedAt"])
        }
        return m
    }

    private func seedIfNeeded() throws {
        try writer.write { db in
            if try Deck.fetchCount(db) == 0 {
                var deck = Deck(name: "Kyōkasho")
                try deck.insert(db)
            }
            if try NoteTemplate.fetchCount(db) == 0 {
                var template = NoteTemplate.japaneseWord
                try template.insert(db)
            }
        }
    }

    // MARK: Paquets et modèles

    public func decks() throws -> [Deck] {
        try writer.read { try Deck.order(Column("name")).fetchAll($0) }
    }

    @discardableResult
    public func addDeck(named name: String) throws -> Deck {
        try writer.write { db in
            var deck = Deck(name: name)
            try deck.insert(db)
            return deck
        }
    }

    public func templates() throws -> [NoteTemplate] {
        try writer.read { try NoteTemplate.order(Column("id")).fetchAll($0) }
    }

    public func template(id: Int64) throws -> NoteTemplate? {
        try writer.read { try NoteTemplate.fetchOne($0, key: id) }
    }

    @discardableResult
    public func save(_ template: NoteTemplate) throws -> NoteTemplate {
        try writer.write { db in
            var t = template
            t.modifiedAt = Date()
            try t.save(db)
            return t
        }
    }

    // MARK: Cartes

    @discardableResult
    public func add(_ card: StudyCard) throws -> StudyCard {
        try writer.write { db in
            var c = card
            try c.insert(db)
            return c
        }
    }

    /// Ajout groupé atomique : une erreur ne laisse pas une page à moitié ajoutée.
    /// Vérification dans la transaction, y compris les répétitions dans le lot.
    public func addMissing(_ cards: [StudyCard]) throws -> Int {
        try writer.write { db in
            var added = 0
            for var card in cards {
                guard try StudyCard.filter(Column("key") == card.key).fetchOne(db) == nil else { continue }
                try card.insert(db)
                added += 1
            }
            return added
        }
    }

    public func update(_ card: StudyCard) throws {
        try writer.write { db in
            var c = card
            c.modifiedAt = Date()
            try c.update(db)
        }
    }

    public func deleteCards(_ ids: [Int64]) throws {
        try writer.write { db in _ = try StudyCard.deleteAll(db, keys: ids) }
    }

    public func card(id: Int64) throws -> StudyCard? {
        try writer.read { try StudyCard.fetchOne($0, key: id) }
    }

    /// Carte déjà créée pour ce mot (anti-doublon).
    public func card(key: String) throws -> StudyCard? {
        try writer.read { try StudyCard.filter(Column("key") == key).fetchOne($0) }
    }

    public func existingKeys(_ keys: [String]) throws -> Set<String> {
        guard !keys.isEmpty else { return [] }
        return try writer.read { db in
            Set(try String.fetchAll(db, StudyCard.select(Column("key")).filter(keys.contains(Column("key")))))
        }
    }

    /// Liste (navigateur de cartes). `query` cherche dans les champs.
    public func cards(deckId: Int64? = nil, query: String = "", limit: Int = 500) throws -> [StudyCard] {
        try writer.read { db in
            var request = StudyCard.all()
            if let deckId { request = request.filter(Column("deckId") == deckId) }
            let q = query.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty { request = request.filter(Column("fields").like("%\(q)%") || Column("key").like("%\(q)%")) }
            return try request.order(Column("createdAt").desc).limit(limit).fetchAll(db)
        }
    }

    // MARK: File de révision

    public struct Counts: Equatable, Sendable {
        public var new: Int
        public var learning: Int
        public var review: Int
        public var total: Int { new + learning + review }

        public init(new: Int = 0, learning: Int = 0, review: Int = 0) {
            self.new = new
            self.learning = learning
            self.review = review
        }
    }

    /// Les apprentissages en cours sont montrés jusqu'à 20 min en avance (comme Anki).
    public static let learnAhead: TimeInterval = 20 * 60

    func base(_ deckId: Int64?) -> QueryInterfaceRequest<StudyCard> {
        var r = StudyCard.filter(Column("suspended") == false)
        if let deckId { r = r.filter(Column("deckId") == deckId) }
        return r
    }

    /// Nombre de nouvelles cartes vues pour la première fois depuis `dayStart`.
    func newIntroduced(_ db: Database, since dayStart: Date, deckId: Int64?) throws -> Int {
        var sql = "SELECT COUNT(DISTINCT l.cardId) FROM reviewLog l JOIN card c ON c.id = l.cardId WHERE l.state = 0 AND l.reviewedAt >= ?"
        var args: StatementArguments = [dayStart]
        if let deckId { sql += " AND c.deckId = ?"; args += [deckId] }
        return try Int.fetchOne(db, sql: sql, arguments: args) ?? 0
    }

    func reviewsDone(_ db: Database, since dayStart: Date, deckId: Int64?) throws -> Int {
        var sql = "SELECT COUNT(*) FROM reviewLog l JOIN card c ON c.id = l.cardId WHERE l.state = 2 AND l.reviewedAt >= ?"
        var args: StatementArguments = [dayStart]
        if let deckId { sql += " AND c.deckId = ?"; args += [deckId] }
        return try Int.fetchOne(db, sql: sql, arguments: args) ?? 0
    }

    public func counts(deckId: Int64? = nil, settings: ReviewSettings, now: Date = Date()) throws -> Counts {
        let dayStart = settings.dayStart(for: now)
        let tomorrow = dayStart.addingTimeInterval(86400)
        return try writer.read { db in
            let learning = try base(deckId).filter([MemoryState.learning.rawValue, MemoryState.relearning.rawValue].contains(Column("state")))
                .filter(Column("due") < tomorrow).fetchCount(db)
            let reviewDue = try base(deckId).filter(Column("state") == MemoryState.review.rawValue)
                .filter(Column("due") < tomorrow).fetchCount(db)
            let reviewLeft = max(0, settings.maximumReviewsPerDay - (try reviewsDone(db, since: dayStart, deckId: deckId)))
            let newLeft = max(0, settings.newCardsPerDay - (try newIntroduced(db, since: dayStart, deckId: deckId)))
            let newAvailable = try base(deckId).filter(Column("state") == MemoryState.new.rawValue).fetchCount(db)
            return Counts(new: min(newLeft, newAvailable), learning: learning, review: min(reviewDue, reviewLeft))
        }
    }

    public enum Next: Equatable, Sendable {
        case card(StudyCard)
        /// Plus rien maintenant ; une carte en apprentissage revient à cette heure.
        case later(Date)
        case done
    }

    /// Prochaine carte à montrer : apprentissage dû, puis révisions du jour, puis nouvelles.
    /// Une nouvelle carte est glissée toutes les 4 révisions pour ne pas les garder pour la fin.
    public func next(deckId: Int64? = nil, settings: ReviewSettings, now: Date = Date(), excluding: Int64? = nil) throws -> Next {
        let dayStart = settings.dayStart(for: now)
        let tomorrow = dayStart.addingTimeInterval(86400)
        return try writer.read { db in
            var b = base(deckId)
            if let excluding { b = b.filter(Column("id") != excluding) }
            let learningStates = [MemoryState.learning.rawValue, MemoryState.relearning.rawValue]
            if let c = try b.filter(learningStates.contains(Column("state")))
                .filter(Column("due") <= now.addingTimeInterval(Self.learnAhead)).order(Column("due")).fetchOne(db) {
                return .card(c)
            }
            let reviewsDone = try reviewsDone(db, since: dayStart, deckId: deckId)
            let newDone = try newIntroduced(db, since: dayStart, deckId: deckId)
            let newAllowed = newDone < settings.newCardsPerDay
            let review = reviewsDone < settings.maximumReviewsPerDay
                ? try b.filter(Column("state") == MemoryState.review.rawValue).filter(Column("due") < tomorrow)
                    .order(Column("due")).fetchOne(db)
                : nil
            let new = newAllowed
                ? try b.filter(Column("state") == MemoryState.new.rawValue).order(Column("id")).fetchOne(db)
                : nil
            let total = reviewsDone + newDone
            if let review, let new { return .card(total % 5 == 4 ? new : review) }
            if let c = review ?? new { return .card(c) }
            // Sans `excluding` : la carte qu'on vient de voir peut être celle qui revient plus tard.
            if let later = try base(deckId).filter(learningStates.contains(Column("state"))).filter(Column("due") < tomorrow)
                .order(Column("due")).fetchOne(db) {
                return .later(later.due)
            }
            return .done
        }
    }

    /// Enregistre une réponse (carte + historique dans la même transaction).
    @discardableResult
    public func record(_ card: StudyCard, log: ReviewEntry) throws -> ReviewEntry {
        try writer.write { db in
            var c = card
            try c.update(db)
            var l = log
            try l.insert(db)
            return l
        }
    }

    /// Annule une réponse : remet la carte dans son état d'avant et efface la ligne d'historique.
    public func undo(restoring card: StudyCard, logId: Int64) throws {
        try writer.write { db in
            var c = card
            try c.update(db)
            _ = try ReviewEntry.deleteOne(db, key: logId)
        }
    }

    public func history(cardId: Int64) throws -> [ReviewEntry] {
        try writer.read { try ReviewEntry.filter(Column("cardId") == cardId).order(Column("reviewedAt").desc).fetchAll($0) }
    }

    /// Statistiques simples : révisions par jour sur `days` jours, taux de réussite.
    public struct Stats: Equatable, Sendable {
        public var reviewsPerDay: [Date: Int]
        public var retention: Double?
        public var totalCards: Int
        public var matureCards: Int
    }

    public func stats(days: Int = 30, settings: ReviewSettings, now: Date = Date()) throws -> Stats {
        let start = settings.dayStart(for: now).addingTimeInterval(-Double(days - 1) * 86400)
        return try writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT reviewedAt, grade, state FROM reviewLog WHERE reviewedAt >= ?", arguments: [start])
            var perDay: [Date: Int] = [:]
            var passed = 0, reviewed = 0
            for row in rows {
                let date: Date = row["reviewedAt"]
                perDay[settings.dayStart(for: date), default: 0] += 1
                if (row["state"] as Int) == MemoryState.review.rawValue {
                    reviewed += 1
                    if (row["grade"] as Int) > 1 { passed += 1 }
                }
            }
            let total = try StudyCard.fetchCount(db)
            let mature = try StudyCard.filter(Column("scheduledDays") >= 21).fetchCount(db)
            return Stats(reviewsPerDay: perDay, retention: reviewed > 0 ? Double(passed) / Double(reviewed) : nil,
                         totalCards: total, matureCards: mature)
        }
    }

    // MARK: Médias

    /// Range un fichier média ; le nom vient du contenu (deux fois la même image = un fichier).
    public func addMedia(_ data: Data, extension ext: String, prefix: String = "kyokasho") throws -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in data { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        let name = "\(prefix)-\(String(h, radix: 36)).\(ext.lowercased())"
        let url = mediaRoot.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        return name
    }

    public func mediaURL(_ name: String) -> URL? {
        let url = mediaRoot.appendingPathComponent(name)
        guard !name.contains("/"), !name.hasPrefix("."), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Médias cités par des champs (`<img src="…">`, `[sound:…]`).
    public static func mediaReferences(in fields: [String: String]) -> Set<String> {
        var names = Set<String>()
        for value in fields.values {
            names.formUnion(matches(in: value, prefix: "src=\"", suffix: "\""))
            names.formUnion(matches(in: value, prefix: "[sound:", suffix: "]"))
        }
        return names.filter { !$0.contains("/") && !$0.contains(":") }
    }

    static func matches(in s: String, prefix: String, suffix: String) -> [String] {
        var out: [String] = []
        var rest = s[...]
        while let p = rest.range(of: prefix) {
            rest = rest[p.upperBound...]
            guard let e = rest.range(of: suffix) else { break }
            out.append(String(rest[..<e.lowerBound]))
            rest = rest[e.upperBound...]
        }
        return out
    }

    /// Supprime les médias que plus aucune carte n'utilise. Renvoie le nombre de fichiers retirés.
    @discardableResult
    public func removeUnusedMedia() throws -> Int {
        let used = try writer.read { db in
            try StudyCard.fetchAll(db).reduce(into: Set<String>()) { $0.formUnion(Self.mediaReferences(in: $1.fields)) }
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: mediaRoot.path)) ?? []
        var removed = 0
        for name in files where !used.contains(name) {
            try? FileManager.default.removeItem(at: mediaRoot.appendingPathComponent(name))
            removed += 1
        }
        return removed
    }
}

public extension NoteTemplate {
    /// Champs du modèle japonais fourni.
    static let japaneseFields = ["Mot", "Lecture", "Furigana", "Sens", "Phrase", "Traduction",
                                 "Image", "Audio", "Accent", "Fréquence", "Source", "Notes"]

    /// Modèle par défaut : recto = mot (+ phrase), verso = lecture, sens, accent, image, audio.
    static var japaneseWord: NoteTemplate {
        NoteTemplate(
            name: "Japonais — mot",
            fieldNames: japaneseFields,
            front: """
                <div class="word">{{Mot}}</div>
                {{#if Phrase}}<div class="sentence">{{Phrase}}</div>{{/if}}
                """,
            back: """
                <div class="word">{{furigana:Furigana}}</div>
                {{#if Phrase}}<div class="sentence">{{Phrase}}</div>{{/if}}
                {{#if Traduction}}<div class="translation">{{Traduction}}</div>{{/if}}
                <hr id="answer">
                <div class="meta">{{#if Accent}}<span class="pitch">{{Accent}}</span>{{/if}}\
                {{#if Fréquence}}<span class="freq">{{Fréquence}}</span>{{/if}}</div>
                <div class="meaning">{{Sens}}</div>
                {{#if Image}}<div class="image">{{Image}}</div>{{/if}}
                {{Audio}}
                {{#if Notes}}<div class="notes">{{Notes}}</div>{{/if}}
                {{#if Source}}<div class="source">{{Source}}</div>{{/if}}
                """,
            css: """
                .card { font-family: "Hiragino Sans", -apple-system, sans-serif; font-size: 20px; text-align: center;
                  color: #e8e6e1; background: #16181c; line-height: 1.5; padding: 12px; }
                .word { font-family: "Hiragino Mincho ProN", serif; font-size: 52px; margin: 18px 0 8px; }
                .word rt { font-size: 0.38em; color: #9aa3ad; }
                .sentence { font-size: 22px; color: #c9c6bf; margin: 6px 0; }
                .sentence b { color: #ff6f59; font-weight: 600; }
                .translation { font-size: 16px; color: #8d949c; }
                hr#answer { border: none; border-top: 1px solid #2c3036; margin: 16px 0; }
                .meta span { display: inline-block; margin: 0 6px; padding: 2px 8px; border-radius: 6px;
                  background: #22262c; font-size: 14px; color: #b9c0c8; }
                .meaning { text-align: left; max-width: 640px; margin: 12px auto; font-size: 18px; }
                .meaning ol { padding-left: 1.4em; } .meaning li { margin: 3px 0; }
                .image img { max-width: 100%; max-height: 220px; border-radius: 8px; margin-top: 10px; }
                .notes { font-size: 16px; color: #c9c6bf; margin-top: 10px; }
                .source { font-size: 12px; color: #6d747c; margin-top: 14px; }
                """
        )
    }
}
