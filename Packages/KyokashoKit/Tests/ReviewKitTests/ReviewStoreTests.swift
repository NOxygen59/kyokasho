// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReviewKit

final class ReviewStoreTests: XCTestCase {
    var store: ReviewStore!
    var deckId: Int64 = 0
    var templateId: Int64 = 0
    let now = Date()

    override func setUpWithError() throws {
        store = try ReviewStore.inMemory()
        deckId = try XCTUnwrap(store.decks().first?.id)
        templateId = try XCTUnwrap(store.templates().first?.id)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: store.mediaRoot)
    }

    @discardableResult
    func add(_ word: String, fields: [String: String] = [:]) throws -> StudyCard {
        try store.add(StudyCard(deckId: deckId, templateId: templateId, key: StudyCard.key(expression: word, reading: ""),
                                fields: fields.merging(["Mot": word]) { a, _ in a }, now: now))
    }

    func testShiftSourcePages() throws {
        let a = try store.add(StudyCard(deckId: deckId, templateId: templateId, key: "天井|", fields: ["Mot": "天井"],
                                        sourceDocumentId: "d", sourcePage: 3, now: now))
        let b = try store.add(StudyCard(deckId: deckId, templateId: templateId, key: "床|", fields: ["Mot": "床"],
                                        sourceDocumentId: "autre", sourcePage: 3, now: now))
        try store.shiftSourcePages(documentId: "d", by: 5)
        XCTAssertEqual(try store.card(id: XCTUnwrap(a.id))?.sourcePage, 8)
        XCTAssertEqual(try store.card(id: XCTUnwrap(b.id))?.sourcePage, 3)
    }

    /// #49 : une carte dont la page est retirée reste liée à son document, sans page ; le reste de la carte est intact.
    func testSetSourcePagesCanKeepACardWithoutPage() throws {
        let removed = try store.add(StudyCard(deckId: deckId, templateId: templateId, key: "欄間|", fields: ["Mot": "欄間"],
                                              sourceDocumentId: "d", sourcePage: 2, now: now))
        let kept = try store.add(StudyCard(deckId: deckId, templateId: templateId, key: "床|", fields: ["Mot": "床"],
                                           sourceDocumentId: "d", sourcePage: 4, now: now))
        try store.setSourcePages(documentId: "d", pages: [XCTUnwrap(removed.id): nil, XCTUnwrap(kept.id): 3])
        let card = try XCTUnwrap(store.card(id: XCTUnwrap(removed.id)))
        XCTAssertNil(card.sourcePage)
        XCTAssertEqual(card.sourceDocumentId, "d")
        XCTAssertEqual(card.fields, removed.fields)
        XCTAssertEqual(try store.card(id: XCTUnwrap(kept.id))?.sourcePage, 3)
        XCTAssertEqual(try store.sourcePages(documentId: "d"), [try XCTUnwrap(kept.id): 3])
    }

    /// #49 : rattachement à la restauration, seulement pour une carte encore sans page du même document.
    func testReattachOnlyTouchesCardsStillWithoutPage() throws {
        let detached = try store.add(StudyCard(deckId: deckId, templateId: templateId, key: "欄間|", fields: ["Mot": "欄間"],
                                               sourceDocumentId: "d", sourcePage: nil, now: now))
        let moved = try store.add(StudyCard(deckId: deckId, templateId: templateId, key: "床|", fields: ["Mot": "床"],
                                            sourceDocumentId: "d", sourcePage: 9, now: now))
        let other = try store.add(StudyCard(deckId: deckId, templateId: templateId, key: "壁|", fields: ["Mot": "壁"],
                                            sourceDocumentId: "autre", sourcePage: nil, now: now))
        let pages = [try XCTUnwrap(detached.id): 2, try XCTUnwrap(moved.id): 3, try XCTUnwrap(other.id): 4]
        XCTAssertEqual(try store.reattachSourcePages(documentId: "d", pages: pages), 1)
        XCTAssertEqual(try store.reattachSourcePages(documentId: "d", pages: pages), 0, "rejouable")
        XCTAssertEqual(try store.card(id: XCTUnwrap(detached.id))?.sourcePage, 2)
        XCTAssertEqual(try store.card(id: XCTUnwrap(moved.id))?.sourcePage, 9)
        XCTAssertNil(try store.card(id: XCTUnwrap(other.id))?.sourcePage)
    }

    func testSeed() throws {
        XCTAssertEqual(try store.decks().map(\.name), ["Kyōkasho"])
        XCTAssertEqual(try store.templates().map(\.name), [NoteTemplate.japaneseWord.name])
        XCTAssertEqual(try store.templates().first?.fieldNames, NoteTemplate.japaneseFields)
    }

    func testDuplicateByKey() throws {
        try add("猫")
        let key = StudyCard.key(expression: "猫", reading: "")
        XCTAssertNotNil(try store.card(key: key))
        XCTAssertNil(try store.card(key: StudyCard.key(expression: "犬", reading: "")))
        XCTAssertEqual(try store.existingKeys([key, "犬|"]), [key])
        XCTAssertEqual(try store.existingKeys([]), [])
    }

    func testNextLearningFirstAndNewLimit() throws {
        var settings = ReviewSettings()
        settings.fuzz = false
        settings.newCardsPerDay = 2
        let scheduler = ReviewScheduler(settings: settings)
        for w in ["一", "二", "三"] { try add(w) }

        guard case .card(let first) = try store.next(settings: settings, now: now) else { return XCTFail() }
        XCTAssertEqual(first.fields["Mot"], "一")
        let (learning, log) = try scheduler.review(first, grade: .again, now: now)
        try store.record(learning, log: log)
        XCTAssertEqual(learning.state, .learning)

        // La carte en apprentissage revient avant les nouvelles.
        guard case .card(let again) = try store.next(settings: settings, now: now) else { return XCTFail() }
        XCTAssertEqual(again.id, first.id)

        guard case .card(let second) = try store.next(settings: settings, now: now, excluding: first.id) else { return XCTFail() }
        XCTAssertEqual(second.fields["Mot"], "二")
        let (s2, l2) = try scheduler.review(second, grade: .easy, now: now)
        try store.record(s2, log: l2)

        // Deux nouvelles vues aujourd'hui : la limite est atteinte, « 三 » attend demain.
        let c = try store.counts(settings: settings, now: now)
        XCTAssertEqual(c.new, 0)
        XCTAssertEqual(c.learning, 1)
        switch try store.next(settings: settings, now: now, excluding: first.id) {
        case .later(let date): XCTAssertEqual(date.timeIntervalSince1970, learning.due.timeIntervalSince1970, accuracy: 1)
        case .card(let card): XCTAssertNotEqual(card.fields["Mot"], "三")
        case .done: XCTFail("la carte en apprentissage devrait revenir")
        }
    }

    func testCounts() throws {
        let settings = ReviewSettings()
        for w in ["一", "二", "三"] { try add(w) }
        XCTAssertEqual(try store.counts(settings: settings, now: now), ReviewStore.Counts(new: 3))
        var suspended = try add("四")
        suspended.suspended = true
        try store.update(suspended)
        XCTAssertEqual(try store.counts(settings: settings, now: now).total, 3)
    }

    func testRecordAndUndo() throws {
        let before = try add("猫")
        let (after, log) = try ReviewScheduler().review(before, grade: .good, now: now)
        let saved = try store.record(after, log: log)
        XCTAssertEqual(try store.history(cardId: before.id!).count, 1)
        XCTAssertEqual(try store.card(id: before.id!)?.reps, 1)

        try store.undo(restoring: before, logId: try XCTUnwrap(saved.id))
        XCTAssertEqual(try store.history(cardId: before.id!).count, 0)
        XCTAssertEqual(try store.card(id: before.id!)?.state, .new)
        XCTAssertEqual(try store.card(id: before.id!)?.reps, 0)
    }

    func testMedia() throws {
        let data = Data("image".utf8)
        let a = try store.addMedia(data, extension: "JPG")
        let b = try store.addMedia(data, extension: "jpg")
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasSuffix(".jpg"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.mediaRoot.path).count, 1)
        XCTAssertNotNil(store.mediaURL(a))
        XCTAssertNil(store.mediaURL("../" + a))

        let fields = ["Image": "<img src=\"\(a)\"><img src=\"https://x.fr/y.png\">", "Audio": "[sound:mot.mp3]"]
        XCTAssertEqual(ReviewStore.mediaReferences(in: fields), [a, "mot.mp3"])

        let unused = try store.addMedia(Data("autre".utf8), extension: "mp3")
        try add("猫", fields: ["Image": "<img src=\"\(a)\">"])
        XCTAssertEqual(try store.removeUnusedMedia(), 1)
        XCTAssertNil(store.mediaURL(unused))
        XCTAssertNotNil(store.mediaURL(a))
    }
}
