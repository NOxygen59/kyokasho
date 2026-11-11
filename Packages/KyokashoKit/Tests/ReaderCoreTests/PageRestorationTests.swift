// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
@testable import ReaderCore

/// Restauration d'une suppression (#49, S3), base synthétique en mémoire.
final class PageRestorationTests: XCTestCase {
    var db: AppDatabase!

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
        var doc = LibraryDocument(id: "d", title: "Test", originalFileName: "t.pdf", pageCount: 6, fileSize: 1)
        doc.firstPageIndex = 1
        try db.save(doc)
        for page in 0..<6 { try db.save(PageComment(documentId: "d", pageIndex: page, body: "p\(page)")) }
        try db.writer.write { db in
            try OCRResultRecord(documentId: "d", pageIndex: 2, engine: "retouche", json: Data([2, 0]), durationMs: 1).insert(db)
        }
    }

    private func notes() throws -> [String] { try db.comments(documentId: "d").map { "\($0.pageIndex):\($0.body)" } }
    private func version() throws -> Int { try XCTUnwrap(db.layoutVersion(documentId: "d")) }

    @discardableResult
    private func remove(_ pages: Set<Int>, id: String, cards: [Int64: Int] = [:]) throws -> PageMapping {
        let count = try XCTUnwrap(db.document(id: "d")).pageCount
        let mapping = try PageMapping.removal(oldCount: count, removing: pages)
        try db.remapPages(documentId: "d", mapping: mapping, editId: id, kind: .removal, expectedVersion: version(),
                          fileSize: 1, detachedCards: cards)
        return mapping
    }

    @discardableResult
    private func restore(_ archive: String, id: String) throws -> AppDatabase.RestorationPlan {
        let plan = try db.restorationPlan(documentId: "d", archiveId: archive)
        try db.remapPages(documentId: "d", mapping: plan.mapping, editId: id, kind: .restoration,
                          expectedVersion: version(), fileSize: 1, restoring: plan)
        return plan
    }

    func testRemoveThenRestoreGivesBackEverythingInPlace() throws {
        try remove([2, 3], id: "s1", cards: [7: 2])
        let before = try XCTUnwrap(db.pageEdit(id: "s1")).pageOrder
        XCTAssertEqual(try notes(), ["0:p0", "1:p1", "2:p4", "3:p5"])
        let plan = try restore("s1", id: "r1")
        XCTAssertEqual(plan.positions.values.sorted(), [2, 3])
        XCTAssertEqual(plan.cards, [7: 2])
        XCTAssertEqual(try notes(), ["0:p0", "1:p1", "2:p2", "3:p3", "4:p4", "5:p5"])
        XCTAssertEqual(try db.ocrResult(documentId: "d", pageIndex: 2, engine: "retouche")?.json, Data([2, 0]))
        XCTAssertEqual(try db.pageIdentities(documentId: "d").map(\.pageId), before, "mêmes identifiants")
        XCTAssertEqual(try db.pageIdentities(documentId: "d").map(\.printedNumber), [nil, 1, 2, 3, 4, 5], "mêmes numéros imprimés")
        XCTAssertEqual(try db.pageEdit(id: "s1")?.restoredBy, "r1")
        XCTAssertThrowsError(try db.restorationPlan(documentId: "d", archiveId: "s1"), "déjà restaurée")
    }

    func testLaterChangesAreKeptWhenRestoring() throws {
        try remove([2], id: "s1")
        try db.save(PageComment(documentId: "d", pageIndex: 2, body: "écrite après"))   // sur l'ancienne p3
        try db.remapPages(documentId: "d", mapping: PageMapping.insertion(oldCount: 5, inserted: 1, at: 0), editId: "a1",
                          kind: .insertion, expectedVersion: version(), fileSize: 1)
        try restore("s1", id: "r1")
        // La page 2 revient après p1 (décalée par l'ajout), la note écrite après reste sur sa page.
        let comments = try db.comments(documentId: "d")
        XCTAssertEqual(comments.first { $0.body == "p2" }?.pageIndex, 3)
        XCTAssertEqual(comments.first { $0.body == "écrite après" }?.pageIndex, 4)
        XCTAssertEqual(comments.first { $0.body == "p3" }?.pageIndex, 4)
        XCTAssertEqual(try XCTUnwrap(db.document(id: "d")).pageCount, 7)
    }

    func testTwoRemovalsCanBeRestoredInEitherOrder() throws {
        for order in [["s1", "s2"], ["s2", "s1"]] {
            try setUpWithError()
            try remove([1], id: "s1")
            let before = try XCTUnwrap(db.pageEdit(id: "s1")).pageOrder
            try remove([2, 3], id: "s2")   // anciennes p3, p4
            for (index, archive) in order.enumerated() { try restore(archive, id: "r\(index)") }
            XCTAssertEqual(try db.pageIdentities(documentId: "d").map(\.pageId), before, "\(order)")
            XCTAssertEqual(try notes(), (0..<6).map { "\($0):p\($0)" }, "\(order)")
        }
    }

    func testAdjacentRemovalsRestoreInEitherOrderWithLaterInsertion() throws {
        for added in [false, true] {
            for order in [["s1", "s2"], ["s2", "s1"]] {
                try setUpWithError()
                try remove([1], id: "s1")
                let original = try XCTUnwrap(db.pageEdit(id: "s1")).pageOrder
                try remove([1], id: "s2") // p2 était voisine de p1, déjà absente.
                if added {
                    try db.remapPages(documentId: "d", mapping: PageMapping.insertion(oldCount: 4, inserted: 1, at: 1),
                                      editId: "a", kind: .insertion, expectedVersion: version(), fileSize: 1)
                    try db.save(PageComment(documentId: "d", pageIndex: 1, body: "nouvelle"))
                }
                try db.save(PageComment(documentId: "d", pageIndex: added ? 2 : 1, body: "après"))
                for (i, archive) in order.enumerated() { try restore(archive, id: "r\(i)") }
                let identities = try db.pageIdentities(documentId: "d").map(\.pageId)
                XCTAssertEqual(identities.filter { original.contains($0) }, original, "\(order), ajout=\(added)")
                let notes = try db.comments(documentId: "d")
                XCTAssertEqual(notes.first { $0.body == "après" }?.pageIndex, added ? 4 : 3)
                if added { XCTAssertEqual(notes.first { $0.body == "nouvelle" }?.pageIndex, 3) }
            }
        }
    }

    func testReplayRejectsAlteredRestorationMetadata() throws {
        try remove([1], id: "s1", cards: [7: 1])
        let original = try restore("s1", id: "r1")
        XCTAssertFalse(try db.remapPages(documentId: "d", mapping: original.mapping, editId: "r1", kind: .restoration,
                                        expectedVersion: 1, fileSize: 1, restoring: original))
        for field in 0..<4 {
            var altered = original
            switch field {
            case 0: altered.cards = [999: 999]
            case 1: altered.archiveId = "autre"
            case 2: altered.positions = [:]
            default: altered.originalIndices = [:]
            }
            XCTAssertThrowsError(try db.remapPages(documentId: "d", mapping: original.mapping, editId: "r1", kind: .restoration,
                                                   expectedVersion: 1, fileSize: 1, restoring: altered), "champ \(field)")
        }
    }

    func testReplayOfAlteredRemovalJournalFailsCleanly() throws {
        try remove([2, 3], id: "s1")
        // Journal altéré sur le disque : l'ordre enregistré (pageOrderJSON) est remplacé par six fois le
        // même identifiant « x ». Les identifiants des deux pages retirées sont donc absents de l'ordre —
        // le scénario testé n'est pas une clé répétée. L'aide archivedPositions lève alors une erreur
        // propre, jamais un plantage par désemballage forcé — C2.4.
        try db.writer.write { db in
            try db.execute(sql: "UPDATE pageEdit SET pageOrderJSON = ? WHERE id = ?",
                           arguments: [try JSONEncoder().encode(Array(repeating: "x", count: 6)), "s1"])
        }
        let mapping = try PageMapping.removal(oldCount: 6, removing: [2, 3])
        XCTAssertThrowsError(try db.remapPages(documentId: "d", mapping: mapping, editId: "s1", kind: .removal,
                                               expectedVersion: 0, fileSize: 1)) {
            XCTAssertTrue($0.localizedDescription.contains("altéré"), $0.localizedDescription)
        }
        XCTAssertEqual(try notes().count, 4, "rien n'est refait")
    }

    func testReplayOfRestorationWithAlteredArchiveFailsCleanly() throws {
        try remove([2, 3], id: "s1")
        let original = try restore("s1", id: "r1")
        try db.writer.write { db in
            try db.execute(sql: "UPDATE pageEdit SET pageOrderJSON = ? WHERE id = ?",
                           arguments: [try JSONEncoder().encode(Array(repeating: "x", count: 6)), "s1"])
        }
        XCTAssertThrowsError(try db.remapPages(documentId: "d", mapping: original.mapping, editId: "r1",
                                               kind: .restoration, expectedVersion: 1, fileSize: 1,
                                               restoring: original)) {
            XCTAssertTrue($0.localizedDescription.contains("altéré"), $0.localizedDescription)
        }
    }

    /// Ordre d'archive altéré (P2 n°2 de la revue R2, contre-revue DeepSeek) : `pageOrderJSON` est raccourci
    /// sur le disque alors que `mappingJSON` garde ses indices (4 et 5). L'altération passe tous les gardes
    /// de chaîne et d'historique (l'état courant du document est intact), atteint vraiment
    /// `removedPageIds()` — la ligne corrigée — et lève « Plan de restauration altéré » au lieu de planter
    /// par indexation hors bornes ; la restauration s'arrête sans rien appliquer.
    func testPlanOfAlteredArchiveOrderFailsCleanlyWithoutEffect() throws {
        try remove([4, 5], id: "s1")
        let rows = try db.archivedRows(editId: "s1").count
        try db.writer.write { db in
            // Journal altéré sur le disque : l'ordre enregistré ne compte plus que quatre identifiants,
            // pour un document qui en avait six avant la suppression de ses pages 5 et 6.
            try db.execute(sql: "UPDATE pageEdit SET pageOrderJSON = ? WHERE id = ?",
                           arguments: [try JSONEncoder().encode(["a", "b", "c", "d"]), "s1"])
        }
        XCTAssertThrowsError(try db.restorationPlan(documentId: "d", archiveId: "s1")) { error in
            XCTAssertTrue(error is AppDatabase.PageEditError, "\(error)")
            XCTAssertTrue(error.localizedDescription.contains("Plan de restauration altéré"), error.localizedDescription)
        }
        XCTAssertEqual(try notes(), ["0:p0", "1:p1", "2:p2", "3:p3"], "rien n'est refait")
        XCTAssertEqual(try db.pageEdit(id: "s1")?.restoredBy, nil, "l'archive n'est pas marquée restaurée")
        XCTAssertEqual(try db.archivedRows(editId: "s1").count, rows, "l'archive reste en place")
    }

    /// Identifiants retirés répétés dans l'ordre d'archive (l'une des pages y a disparu) : le garde
    /// « Historique des pages incomplet » lève avant tout calcul du plan, sans rien appliquer.
    func testPlanWithRepeatedIdsInArchiveOrderFailsCleanlyWithoutEffect() throws {
        try remove([4, 5], id: "s1")
        let order = try XCTUnwrap(db.pageEdit(id: "s1")).pageOrder
        let rows = try db.archivedRows(editId: "s1").count
        try db.writer.write { db in
            // Journal altéré sur le disque : la dernière page retirée répète l'identifiant de celle
            // d'avant, l'une des deux a donc disparu de l'ordre enregistré.
            try db.execute(sql: "UPDATE pageEdit SET pageOrderJSON = ? WHERE id = ?",
                           arguments: [try JSONEncoder().encode([order[0], order[1], order[2], order[3], order[4], order[4]]), "s1"])
        }
        XCTAssertThrowsError(try db.restorationPlan(documentId: "d", archiveId: "s1")) { error in
            XCTAssertTrue(error is AppDatabase.PageEditError, "\(error)")
            XCTAssertTrue(error.localizedDescription.contains("restauration arrêtée"), error.localizedDescription)
        }
        XCTAssertEqual(try notes(), ["0:p0", "1:p1", "2:p2", "3:p3"], "rien n'est refait")
        XCTAssertEqual(try db.pageEdit(id: "s1")?.restoredBy, nil, "l'archive n'est pas marquée restaurée")
        XCTAssertEqual(try db.archivedRows(editId: "s1").count, rows, "l'archive reste en place")
    }

    func testRestorationRefusedAfterDriveReplacementOrPurge() throws {
        try remove([1], id: "s1")
        var doc = try XCTUnwrap(db.document(id: "d"))
        doc.id = "d2"
        try db.rekeyDocument(from: "d", to: doc)
        XCTAssertThrowsError(try db.restorationPlan(documentId: "d2", archiveId: "s1")) {
            XCTAssertTrue($0.localizedDescription.contains("remplacé"))
        }
        try setUpWithError()
        try remove([1], id: "s1")
        try db.purgeArchive(editId: "s1")
        try db.purgeArchive(editId: "s1")   // rejouable
        XCTAssertTrue(try db.archivedRows(editId: "s1").isEmpty)
        XCTAssertNotNil(try db.pageEdit(id: "s1")?.purgedAt)
        XCTAssertThrowsError(try db.restorationPlan(documentId: "d", archiveId: "s1"))
    }

    func testStalePlanIsRefusedWithoutEffect() throws {
        try remove([1], id: "s1")
        let plan = try db.restorationPlan(documentId: "d", archiveId: "s1")
        try remove([0], id: "s2")
        XCTAssertThrowsError(try db.remapPages(documentId: "d", mapping: plan.mapping, editId: "r1", kind: .restoration,
                                               expectedVersion: version(), fileSize: 1, restoring: plan))
        XCTAssertEqual(try notes(), ["0:p2", "1:p3", "2:p4", "3:p5"])
    }

    func testDetachedCardsMustBelongToRemovedPages() throws {
        let mapping = try PageMapping.removal(oldCount: 6, removing: [1])
        XCTAssertThrowsError(try db.remapPages(documentId: "d", mapping: mapping, editId: "s1", kind: .removal,
                                               expectedVersion: 0, fileSize: 1, detachedCards: [7: 2]))
        XCTAssertEqual(try notes().count, 6)
    }

    func testChainMappingFollowsOldPagesOrBreaks() throws {
        XCTAssertEqual(try db.pageMapping(documentId: "d", fromVersion: 0)?.targets, (0..<6).map { $0 })
        try remove([0], id: "s1")
        try db.remapPages(documentId: "d", mapping: PageMapping.insertion(oldCount: 5, inserted: 2, at: 5), editId: "a1",
                          kind: .insertion, expectedVersion: 1, fileSize: 1)
        XCTAssertEqual(try db.pageMapping(documentId: "d", fromVersion: 0)?.targets, [nil, 0, 1, 2, 3, 4])
        var doc = try XCTUnwrap(db.document(id: "d"))
        doc.id = "d2"
        try db.rekeyDocument(from: "d", to: doc)
        XCTAssertNil(try db.pageMapping(documentId: "d2", fromVersion: 0), "remplacement : chaîne rompue")
    }

    func testPrintedNumbersAndManualPageOne() throws {
        XCTAssertNil(try db.printedNumbers()["d"])
        try remove([3], id: "s1")
        XCTAssertEqual(try db.printedNumbers()["d"], [nil, 1, 2, 4, 5])
        try db.renumberPrintedPages(documentId: "d", firstPageIndex: 2)
        XCTAssertEqual(try db.printedNumbers()["d"], [nil, nil, 1, 2, 3])
    }

    /// PLAN-T4-001 E1 : une note étiquetée, datée et rangée retirée avec sa page puis restaurée garde tout son rangement
    /// (les colonnes sont dans la ligne archivée par `SELECT *`).
    func testRemovedThenRestoredNoteKeepsItsOrganization() throws {
        let note = try XCTUnwrap(db.comments(documentId: "d").first { $0.pageIndex == 2 })
        let tag = try db.noteTag(named: "Test S46")
        let folder = try db.createNoteFolder(name: "Matériaux")
        try db.apply(.addTag(tag.id), to: [note.id])
        try db.apply(.folder(folder.id), to: [note.id])
        try db.apply(.due("2026-11-18"), to: [note.id])
        try db.apply(.priority(.high), to: [note.id])
        let before = try XCTUnwrap(db.organization(noteId: note.id))
        try remove([2], id: "s1")
        XCTAssertNil(try db.organization(noteId: note.id))
        try restore("s1", id: "r1")
        XCTAssertEqual(try db.organization(noteId: note.id), before)
    }

    /// Revue DeepSeek R2 n°8 : une archive de page faite **avant** la v7 (JSON sans les colonnes de rangement) se
    /// restaure avec le rangement par défaut. Et n°1 : une étiquette supprimée pendant que la page est retirée revient
    /// ignorée (identifiant inconnu), sans erreur.
    func testRestoringAnArchiveFromBeforeV7AndADeletedTag() throws {
        let note = try XCTUnwrap(db.comments(documentId: "d").first { $0.pageIndex == 2 })
        let tag = try db.noteTag(named: "Supprimée ensuite")
        try db.apply(.addTag(tag.id), to: [note.id])
        try remove([2], id: "s1")
        try db.deleteNoteTag(id: tag.id)
        try restore("s1", id: "r1")
        XCTAssertEqual(try db.organization(noteId: note.id)?.tagIds, [])

        let other = try XCTUnwrap(db.comments(documentId: "d").first { $0.pageIndex == 3 })
        try db.apply(.priority(.high), to: [other.id])
        try remove([3], id: "s2")
        try db.writer.write { db in
            try db.execute(sql: """
                UPDATE pageEditRow SET rowJSON = CAST(json_remove(CAST(rowJSON AS TEXT), '$.dueDay', '$.priority', '$.archived',
                '$.noteFolderId', '$.tagIds') AS BLOB) WHERE editId = 's2' AND tableName = 'pageComment'
                """)
        }
        try restore("s2", id: "r2")
        XCTAssertEqual(try db.organization(noteId: other.id), .default)
    }
}
