// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
@testable import ReaderCore

/// PLAN-T4-001, étape E1 : rangement des notes (échéance, priorité, archive, classeur, étiquettes).
final class NoteOrganizationTests: XCTestCase {
    private func document(_ id: String) -> LibraryDocument {
        LibraryDocument(id: id, title: id, originalFileName: "\(id).pdf", pageCount: 5, fileSize: 1)
    }

    private func database() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.save(document("d"))
        try db.save(PageComment(id: "n1", documentId: "d", pageIndex: 1, body: "note 1"))
        try db.save(PageComment(id: "n2", documentId: "d", pageIndex: 2, body: "note 2"))
        return db
    }

    func testMigrationFromAPopulatedV6DatabaseGivesDefaults() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notes-v6-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("kyokasho.sqlite")
        do {
            let queue = try DatabaseQueue(path: file.path)
            try AppDatabase.migrator.migrate(queue, upTo: "v6-folders")
            try queue.write { db in
                try db.execute(sql: "INSERT INTO document (id, title, originalFileName, pageCount, fileSize, importedAt, lastPageIndex, firstPageIndex) VALUES ('d', 'Ancien', 'a.pdf', 3, 10, '2026-10-01 10:00:00.000', 0, 0)")
                try db.execute(sql: "INSERT INTO pageComment (id, documentId, pageIndex, body, createdAt, updatedAt) VALUES ('n', 'd', 1, 'note 図', '2026-10-01 10:00:00.000', '2026-10-01 10:00:00.000')")
            }
            try queue.close()
        }
        let db = try AppDatabase.open(at: file)
        XCTAssertEqual(try db.organization(noteId: "n"), .default)
        XCTAssertEqual(try db.comments(documentId: "d").first?.body, "note 図")
    }

    func testSavingTheTextNeverErasesTheOrganization() throws {
        let db = try database()
        let tag = try db.noteTag(named: "Explication")
        try db.apply(.addTag(tag.id), to: ["n1"])
        try db.apply(.due("2026-11-20"), to: ["n1"])
        try db.apply(.archived(true), to: ["n1"])
        var note = try XCTUnwrap(db.comments(documentId: "d").first { $0.id == "n1" })
        note.body = "texte corrigé"
        note.updatedAt = Date()
        try db.save(note)
        let organization = try XCTUnwrap(db.organization(noteId: "n1"))
        XCTAssertEqual(organization.tagIds, [tag.id])
        XCTAssertEqual(organization.dueDay, "2026-11-20")
        XCTAssertTrue(organization.archived)
    }

    func testChangesApplyToSeveralNotesAndTagsStayCanonical() throws {
        let db = try database()
        let a = try db.noteTag(named: "A"), b = try db.noteTag(named: "B")
        XCTAssertEqual(try db.noteTag(named: "  a ").id, a.id, "même nom, sans tenir compte des majuscules")
        try db.apply(.addTag(b.id), to: ["n1", "n2"])
        try db.apply(.addTag(a.id), to: ["n1", "n2"])
        try db.apply(.addTag(a.id), to: ["n1"])
        XCTAssertEqual(try db.organization(noteId: "n1")?.tagIds, [a.id, b.id].sorted())
        try db.apply(.removeTag(b.id), to: ["n2"])
        XCTAssertEqual(try db.organization(noteId: "n2")?.tagIds, [a.id])
        XCTAssertThrowsError(try db.apply(.due("2026-02-30"), to: ["n1"])) { XCTAssertEqual($0 as? NoteOrganizationError, .invalidDay) }
        XCTAssertThrowsError(try db.apply(.addTag("inconnue"), to: ["n1"])) { XCTAssertEqual($0 as? NoteOrganizationError, .tagNotFound) }
        XCTAssertThrowsError(try db.apply(.folder("inconnu"), to: ["n1"])) { XCTAssertEqual($0 as? NoteOrganizationError, .folderNotFound) }
    }

    func testDeletingAFolderOrATagKeepsTheNotes() throws {
        let db = try database()
        let folder = try db.createNoteFolder(name: "Matériaux"), tag = try db.noteTag(named: "Test")
        try db.apply(.folder(folder.id), to: ["n1"])
        try db.apply(.addTag(tag.id), to: ["n1", "n2"])
        try db.deleteNoteFolder(id: folder.id)
        try db.deleteNoteTag(id: tag.id)
        XCTAssertEqual(try db.organization(noteId: "n1"), .default)
        XCTAssertEqual(try db.comments(documentId: "d").count, 2, "aucune note effacée")
        XCTAssertEqual(try db.writer.read { try String.fetchOne($0, sql: "SELECT tagIds FROM pageComment WHERE id = 'n2'") }, "[]")
    }

    func testPackageCarriesTheOrganizationAndUnknownIdsAreIgnored() throws {
        let source = try database()
        let folder = try source.createNoteFolder(name: "Matériaux"), tag = try source.noteTag(named: "Test")
        try source.apply(.folder(folder.id), to: ["n1"])
        try source.apply(.addTag(tag.id), to: ["n1"])
        try source.apply(.priority(.high), to: ["n1"])
        let rows = try source.packageRows(documentId: "d")
        // Même appareil, « remplacer » : tout reste.
        try source.installPackage(documentId: "d", rows: rows, replacing: true)
        XCTAssertEqual(try source.organization(noteId: "n1")?.tagIds, [tag.id])
        XCTAssertEqual(try source.organization(noteId: "n1")?.folderId, folder.id)
        // Autre appareil : priorité gardée, classeur et étiquette inconnus ignorés, sans erreur.
        let other = try AppDatabase.inMemory()
        try other.installPackage(documentId: "d", rows: rows, replacing: false)
        let organization = try XCTUnwrap(other.organization(noteId: "n1"))
        XCTAssertEqual(organization.priority, .high)
        XCTAssertNil(organization.folderId)
        XCTAssertEqual(organization.tagIds, [])
    }

    func testDriveFusionKeepsTheOrganization() throws {
        let db = try database()
        try db.save(document("new"))
        try db.apply(.due("2026-12-01"), to: ["n1"])
        try db.rekeyDocument(from: "d", to: XCTUnwrap(db.document(id: "new")))
        XCTAssertEqual(try db.organization(noteId: "n1")?.dueDay, "2026-12-01")
        XCTAssertEqual(try db.comments(documentId: "new").count, 2)
    }

    func testReviewBadgeCountsPastTodayAndTomorrowOnly() throws {
        let db = try database()
        try db.save(PageComment(id: "n3", documentId: "d", pageIndex: 3, body: "3"))
        try db.save(PageComment(id: "n4", documentId: "d", pageIndex: 4, body: "4"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 23)))
        try db.apply(.due("2026-11-01"), to: ["n1"])   // passée
        try db.apply(.due("2026-11-12"), to: ["n2"])   // demain
        try db.apply(.due("2026-11-13"), to: ["n3"])   // après-demain : non
        try db.apply(.due("2026-11-11"), to: ["n4"])   // aujourd'hui, mais archivée : non
        try db.apply(.archived(true), to: ["n4"])
        XCTAssertEqual(try db.notesToReviewCount(today: today, calendar: calendar), 2)
        XCTAssertEqual(try db.notesToReviewCount(today: today, calendar: calendar, excludingDocuments: ["d"]), 0)
        let organization = try XCTUnwrap(db.organization(noteId: "n2"))
        XCTAssertTrue(NoteDay.isToReview(organization, today: today, calendar: calendar))
        XCTAssertEqual(try db.organizedNotes(includeArchived: false).map(\.id).sorted(), ["n1", "n2", "n3"])
        XCTAssertEqual(try db.organizedNotes(includeArchived: true).count, 4)
    }

    func testDayStrings() {
        XCTAssertTrue(NoteDay.isValid("2028-02-29"))
        XCTAssertFalse(NoteDay.isValid("2027-02-29"))
        XCTAssertFalse(NoteDay.isValid("2026-1-5"))
        XCTAssertFalse(NoteDay.isValid("demain"))
    }

    /// Revue GLM R2 n°1 : un iPad au calendrier japonais écrit quand même « 2026-11-11 ».
    func testDayStringIsGregorianWhateverTheDeviceCalendar() throws {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = try XCTUnwrap(japanese.date(from: DateComponents(era: 236, year: 8, month: 11, day: 11, hour: 12)))
        XCTAssertEqual(NoteDay.string(date), "2026-11-11")
        XCTAssertEqual(NoteDay.calendar.identifier, .gregorian)
    }

    /// Revue GLM R2 n°2 : la liste ne charge pas les dessins.
    func testOrganizedNotesDoNotLoadDrawings() throws {
        let db = try database()
        try db.save(PageComment(id: "n3", documentId: "d", pageIndex: 3, body: "dessin", drawing: Data([1, 2, 3])))
        let listed = try XCTUnwrap(db.organizedNotes(includeArchived: true).first { $0.id == "n3" })
        XCTAssertNil(listed.note.drawing)
        XCTAssertEqual(listed.note.body, "dessin")
        XCTAssertEqual(try db.comments(documentId: "d").first { $0.id == "n3" }?.drawing, Data([1, 2, 3]))
    }

    /// Revue DeepSeek n°3 et n°7 : échéance non canonique ignorée ; renommer vers un nom pris est refusé.
    func testInvalidDueDayIsIgnoredAndRenamingIntoADuplicateIsRefused() throws {
        let db = try database()
        try db.writer.write { try $0.execute(sql: "UPDATE pageComment SET dueDay = '2026-1-5' WHERE id = 'n1'") }
        XCTAssertNil(try db.organization(noteId: "n1")?.dueDay)
        XCTAssertEqual(try db.notesToReviewCount(today: Date()), 0)
        let a = try db.noteTag(named: "Test S46")
        let b = try db.noteTag(named: "Autre")
        XCTAssertThrowsError(try db.renameNoteTag(id: b.id, to: "test s46")) { XCTAssertEqual($0 as? NoteOrganizationError, .duplicateName) }
        XCTAssertNoThrow(try db.renameNoteTag(id: a.id, to: "TEST S46"), "renommer en changeant la casse reste permis")
        XCTAssertEqual(try db.organizedNotes(includeArchived: true, excludingDocuments: ["d"]).count, 0)
    }

    /// E3 : l'étiquette tapée dans « Ranger la note » réutilise celle qui existe (majuscules ignorées) ; une sélection
    /// multiple refusée (classeur disparu) ne change aucune note.
    func testTagTypedTwiceIsReusedAndARefusedBatchChangesNothing() throws {
        let db = try database()
        let first = try db.noteTag(named: "Test S46")
        try db.apply(.addTag(first.id), to: ["n1"])
        let again = try db.noteTag(named: "  test s46 ")
        XCTAssertEqual(again.id, first.id)
        try db.apply(.addTag(again.id), to: ["n1", "n2"])
        XCTAssertEqual(try db.noteTags().count, 1)
        XCTAssertEqual(try db.organization(noteId: "n2")?.tagIds, [first.id])

        let folder = try db.createNoteFolder(name: "Matériaux")
        try db.apply(.folder(folder.id), to: ["n1"])
        XCTAssertThrowsError(try db.apply(.folder("disparu"), to: ["n1", "n2"]))
        XCTAssertEqual(try db.organization(noteId: "n1")?.folderId, folder.id)
        XCTAssertNil(try db.organization(noteId: "n2")?.folderId)
    }

    /// Revue DeepSeek D-07 F4 : note disparue → le lot échoue (rien écrit) et aucune étiquette n'est créée.
    func testDeletedNoteFailsTheBatchAndCreatesNoOrphanTag() throws {
        let db = try database()
        XCTAssertThrowsError(try db.apply(.priority(.high), to: ["n1", "disparue"])) {
            XCTAssertEqual($0 as? NoteOrganizationError, .noteNotFound)
        }
        XCTAssertEqual(try db.organization(noteId: "n1")?.priority, .normal, "tout ou rien")
        XCTAssertThrowsError(try db.addTag(named: "Test S46", toNote: "disparue"))
        XCTAssertTrue(try db.noteTags().isEmpty)
        try db.addTag(named: "Test S46", toNote: "n1")
        try db.addTag(named: "test s46", toNote: "n2")
        XCTAssertEqual(try db.noteTags().count, 1)
        XCTAssertEqual(try db.organization(noteId: "n2")?.tagIds, try db.organization(noteId: "n1")?.tagIds)
    }

    /// Relecture finale f2b3d49 (N2) : « Nouveau classeur… » sur une note disparue ne laisse aucun classeur vide.
    func testNewFolderForADeletedNoteCreatesNothing() throws {
        let db = try database()
        XCTAssertThrowsError(try db.createNoteFolder(name: "Matériaux", assigningTo: "disparue"))
        XCTAssertTrue(try db.noteFolders().isEmpty)
        let folder = try db.createNoteFolder(name: "Matériaux", assigningTo: "n1")
        XCTAssertEqual(try db.organization(noteId: "n1")?.folderId, folder.id)
    }
}
