// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

final class NoteReminderPlanTests: XCTestCase {
    private typealias Pending = NoteReminderPlan.PendingReminder
    private typealias Reminder = NoteReminderPlan.Reminder

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
    }

    private func note(_ id: String, page: Int = 0, body: String = "Texte", due: String? = "2026-11-21",
                      minute: Int? = nil, archived: Bool = false, reminders: [Int]? = nil) -> OrganizedNote {
        OrganizedNote(note: PageComment(id: id, documentId: "livre", pageIndex: page, body: body,
                                        createdAt: now, updatedAt: now),
                      organization: NoteOrganization(dueDay: due, priority: .normal, archived: archived,
                                                     folderId: nil, tagIds: [], dueMinute: minute, reminders: reminders))
    }

    private func plan(_ notes: [OrganizedNote], pending: [Pending] = [], labels: [Int: String] = [:]) -> NoteReminderPlan {
        NoteReminderPlan.make(notes, titles: ["livre": "Manuel"], pageLabel: { documentId, index in
            documentId == "livre" ? labels[index] : nil
        }, now: now, pending: pending, defaultMinute: 9 * 60, defaultReminders: [0], calendar: calendar,
        makeTitle: { "\($0) · p. \($1)" }, emptyBody: "Note sans texte")
    }

    private func additions(_ plan: NoteReminderPlan) -> [Reminder] {
        plan.updates.compactMap {
            guard case .add(let reminder) = $0 else { return nil }
            return reminder
        }
    }

    private func pending(_ reminder: Reminder) -> Pending {
        Pending(id: reminder.id, content: reminder.content, trigger: reminder.trigger)
    }

    func testLibellesInjectesEtRepliPhysique() {
        let result = plan([note("imprime", page: 8), note("romain", page: 1), note("absent", page: 2),
                           note("vide", page: 3)], labels: [8: "5", 1: "ii", 3: ""])
        let titles = Dictionary(uniqueKeysWithValues: additions(result).map { ($0.content.noteId, $0.content.title) })
        XCTAssertEqual(titles, ["imprime": "Manuel · p. 5", "romain": "Manuel · p. ii",
                                "absent": "Manuel · p. 3", "vide": "Manuel · p. 4"])
    }

    func testChangeDeTexteOuLibelleRemplaceSousLeMemeIdentifiant() throws {
        let old = try XCTUnwrap(additions(plan([note("note")])).first)
        let textOnly = plan([note("note", body: " \nNouveau texte \n")], pending: [pending(old)])
        let labelOnly = plan([note("note")], pending: [pending(old)], labels: [0: "vi"])
        for (result, title, body) in [(textOnly, old.content.title, "Nouveau texte"),
                                      (labelOnly, "Manuel · p. vi", old.content.body)] {
            XCTAssertEqual(result.updates.count, 1)
            guard case .replace(let replacement)? = result.updates.first else { return XCTFail("Remplacement attendu") }
            XCTAssertEqual(replacement.id, old.id)
            XCTAssertEqual(replacement.trigger, old.trigger)
            XCTAssertEqual(replacement.content.title, title)
            XCTAssertEqual(replacement.content.body, body)
            XCTAssertTrue(result.removals.isEmpty)
        }
    }

    func testRappelIdentiqueNeGenereAucunEffet() throws {
        let notes = [note("stable")]
        let old = try XCTUnwrap(additions(plan(notes)).first)
        let result = plan(notes, pending: [pending(old)])
        XCTAssertTrue(result.updates.isEmpty)
        XCTAssertTrue(result.removals.isEmpty)
    }

    func testComposantesOuRepetitionDifferentesImposentUnRemplacement() throws {
        let notes = [note("stable")]
        let wanted = try XCTUnwrap(additions(plan(notes)).first)
        var shifted = wanted.trigger.components
        shifted.minute = 1
        let oldTriggers: [NoteReminderPlan.Trigger?] = [.init(components: shifted, repeats: false),
                                                       .init(components: wanted.trigger.components, repeats: true), nil]
        for trigger in oldTriggers {
            let old = Pending(id: wanted.id, content: wanted.content, trigger: trigger)
            let result = plan(notes, pending: [old])
            XCTAssertEqual(result.updates, [.replace(wanted)])
            XCTAssertTrue(result.removals.isEmpty)
        }
    }

    func testAjoutEtRemplacementRestentDansLOrdreChronologique() throws {
        let late = note("tard", minute: 10 * 60)
        let old = try XCTUnwrap(additions(plan([late])).first)
        let early = try XCTUnwrap(additions(plan([note("tot")])).first)
        let incompatible = Pending(id: old.id, content: nil, trigger: old.trigger)
        let result = plan([late, note("tot")], pending: [incompatible])
        XCTAssertEqual(result.updates, [.add(early), .replace(old)])
        XCTAssertTrue(result.removals.isEmpty)
    }

    func testRetraitsCiblesSansToucherAuRappelStableNiAuxAutresNotifications() {
        let initial = [note("archivee"), note("passee"), note("supprimee"), note("sans-echeance"), note("stable")]
        let old = additions(plan(initial))
        XCTAssertEqual(old.count, initial.count)
        let notes = [note("archivee", archived: true), note("passee", due: "2026-11-20"),
                     note("sans-echeance", due: nil), note("stable")]
        let foreign = Pending(id: "revision-1", content: nil, trigger: nil)
        let result = plan(notes, pending: old.map(pending) + [foreign])
        XCTAssertEqual(result.removals, old.filter { $0.content.noteId != "stable" }.map(\.id).sorted())
        XCTAssertTrue(result.updates.isEmpty)
    }

    func testReglesDeDeclenchementEtIdentifiantsHistoriques() {
        let notes = [note("echeance", reminders: [0, 60, 15, 1_440]),
                     note("desactive", reminders: []), note("exactement-maintenant", due: "2026-11-20")]
        let reminders = additions(plan(notes))
        let expected = [DateComponents(year: 2026, month: 11, day: 21, hour: 8, minute: 0),
                        DateComponents(year: 2026, month: 11, day: 21, hour: 8, minute: 45),
                        DateComponents(year: 2026, month: 11, day: 21, hour: 9, minute: 0)]
        let dates = expected.map { calendar.date(from: $0)! }
        XCTAssertEqual(reminders.map(\.trigger.components), dates.map {
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
        })
        XCTAssertEqual(reminders.map(\.id), dates.map { "note-echeance-\(Int($0.timeIntervalSince1970))" })
        XCTAssertTrue(reminders.allSatisfy { !$0.trigger.repeats })
    }

    func testPlafondSelectionneLesPlusProchesEtRetireUnRappelEvince() throws {
        let notes = (0...60).reversed().map { note("n-\($0)", minute: $0) }
        let farthest = try XCTUnwrap(additions(plan([notes[0]])).first)
        let result = plan(notes, pending: [pending(farthest)])
        XCTAssertEqual(additions(result).map(\.content.noteId), (0..<60).map { "n-\($0)" })
        XCTAssertEqual(result.removals, [farthest.id])
    }

    func testCorpsVideLocaliseEtExtraitLimiteSansCouperUnCaractere() {
        let character = "か\u{3099}"
        let result = plan([note("vide", body: " \n"), note("long", body: String(repeating: character, count: 151))])
        let bodies = Dictionary(uniqueKeysWithValues: additions(result).map { ($0.content.noteId, $0.content.body) })
        XCTAssertEqual(bodies["vide"], "Note sans texte")
        XCTAssertEqual(bodies["long"], String(repeating: character, count: 150))
    }
}
