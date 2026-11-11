// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// PLAN-T4-001, étape E2 : groupes, tri et filtres de l'écran « Notes ».
final class NoteListingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 22))! }

    private func note(_ id: String, due: String? = nil, priority: NotePriority = .normal, archived: Bool = false,
                      folder: String? = nil, tags: [String] = [], document: String = "d", body: String = "note",
                      created: TimeInterval = 0) -> OrganizedNote {
        OrganizedNote(note: PageComment(id: id, documentId: document, pageIndex: 1, body: body,
                                        createdAt: Date(timeIntervalSince1970: created)),
                      organization: NoteOrganization(dueDay: due, priority: priority, archived: archived,
                                                     folderId: folder, tagIds: tags))
    }

    func testGroupsByDueDay() {
        XCTAssertEqual(NoteListing.group(dueDay: "2026-11-10", today: today, calendar: calendar), .overdue)
        XCTAssertEqual(NoteListing.group(dueDay: "2026-11-11", today: today, calendar: calendar), .today)
        XCTAssertEqual(NoteListing.group(dueDay: "2026-11-12", today: today, calendar: calendar), .tomorrow)
        XCTAssertEqual(NoteListing.group(dueDay: "2026-11-13", today: today, calendar: calendar), .thisWeek)
        XCTAssertEqual(NoteListing.group(dueDay: "2026-11-18", today: today, calendar: calendar), .thisWeek)
        XCTAssertEqual(NoteListing.group(dueDay: "2026-11-19", today: today, calendar: calendar), .later)
        XCTAssertEqual(NoteListing.group(dueDay: nil, today: today, calendar: calendar), .noDue)
        XCTAssertEqual(NoteListing.group(dueDay: "demain", today: today, calendar: calendar), .noDue)
    }

    func testSectionsOrderAndSortWithinAGroup() {
        let notes = [
            note("a", due: "2026-11-15", created: 1),
            note("b", due: "2026-11-13", created: 2),
            note("c", due: "2026-11-16", priority: .high, created: 3),
            note("d", created: 4),
            note("e", due: "2026-11-01", created: 5),
            note("f", due: "2026-11-11", archived: true, created: 6),
        ]
        let sections = NoteListing.sections(notes, filter: .init(), today: today, calendar: calendar)
        XCTAssertEqual(sections.map(\.group), [.overdue, .thisWeek, .noDue])
        XCTAssertEqual(sections[1].notes.map(\.id), ["c", "b", "a"], "haute d'abord, puis échéance la plus proche")
        let archived = NoteListing.sections(notes, filter: .init(archived: true), today: today, calendar: calendar)
        XCTAssertEqual(archived.map(\.group), [.archived], "F17 : pas de « En retard » pour une note archivée")
        XCTAssertEqual(archived.flatMap(\.notes).map(\.id), ["f"])
    }

    func testFiltersCombine() {
        let notes = [
            note("a", folder: "F", tags: ["t1", "t2"], document: "d1", body: "Matériaux de façade"),
            note("b", folder: "F", tags: ["t2"], document: "d2", body: "Plan"),
            note("c", priority: .high, tags: ["t1"], document: "d1", body: "Coupe"),
        ]
        func ids(_ filter: NoteListing.Filter) -> [String] {
            NoteListing.sections(notes, filter: filter, today: today, calendar: calendar).flatMap(\.notes).map(\.id).sorted()
        }
        XCTAssertEqual(ids(.init(folderId: "F")), ["a", "b"])
        XCTAssertEqual(ids(.init(tagId: "t1")), ["a", "c"])
        XCTAssertEqual(ids(.init(folderId: "F", tagId: "t1")), ["a"])
        XCTAssertEqual(ids(.init(priority: .high)), ["c"])
        XCTAssertEqual(ids(.init(documentId: "d2")), ["b"])
        XCTAssertEqual(ids(.init(text: "FACADE")), ["a"], "sans casse ni accents")
        XCTAssertFalse(NoteListing.Filter().isActive)
        XCTAssertTrue(NoteListing.Filter(text: "x").isActive)
    }

    /// Revue DeepSeek F6 : la pastille (SQL), `NoteDay.isToReview` et les groupes de l'écran disent la même chose.
    func testBadgeAndScreenAgree() throws {
        let days = ["2026-10-01", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-12-25", "faux"]
        let db = try AppDatabase.inMemory()
        try db.save(LibraryDocument(id: "d", title: "d", originalFileName: "d.pdf", pageCount: 1, fileSize: 1))
        for (i, day) in days.enumerated() {
            try db.save(PageComment(id: "n\(i)", documentId: "d", pageIndex: 0, body: day))
            try db.writer.write { try $0.execute(sql: "UPDATE pageComment SET dueDay = ? WHERE id = ?", arguments: [day, "n\(i)"]) }
        }
        let listed = try db.organizedNotes(includeArchived: false)
        let byScreen = NoteListing.sections(listed, filter: .init(), today: today, calendar: calendar)
            .filter { $0.group.isToReview }.flatMap(\.notes).count
        let byRule = listed.filter { NoteDay.isToReview($0.organization, today: today, calendar: calendar) }.count
        XCTAssertEqual(byScreen, 4)
        XCTAssertEqual(byRule, 4)
        XCTAssertEqual(try db.notesToReviewCount(today: today, calendar: calendar), 4)
    }

    func testSearchAlsoFindsTheBookTitle() {
        let items = [note("a", document: "d1", body: "x"), note("b", document: "d2", body: "y")]
        let found = NoteListing.sections(items, filter: .init(text: "façade"), today: today, calendar: calendar,
                                         documentTitles: ["d1": "Matériaux de Façade"])
        XCTAssertEqual(found.flatMap(\.notes).map(\.id), ["a"])
    }
}
