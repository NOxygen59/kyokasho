// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// RET-008 / Issue #11 : le brouillon d'une note survit au changement de mode, à la fermeture et au redémarrage.
final class NoteDraftStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("drafts-" + UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testDraftSurvivesANewStoreInstanceLikeAnAppRestart() throws {
        try NoteDraftStore(folder: folder).setDraft("Brouillon 日本語\nligne 2 ", documentId: "doc", page: 3)
        let restarted = NoteDraftStore(folder: folder)
        XCTAssertEqual(restarted.draft(documentId: "doc", page: 3), "Brouillon 日本語\nligne 2 ", "texte conservé tel quel")
    }

    func testOneDraftPerPageAndPerDocument() throws {
        let store = NoteDraftStore(folder: folder)
        try store.setDraft("page 0", documentId: "doc", page: 0)
        try store.setDraft("page 5", documentId: "doc", page: 5)
        try store.setDraft("autre livre", documentId: "other", page: 0)
        XCTAssertEqual(store.drafts(documentId: "doc"), [0: "page 0", 5: "page 5"])
        XCTAssertEqual(store.draft(documentId: "doc", page: 1), "")
        XCTAssertEqual(store.draft(documentId: "other", page: 0), "autre livre")
    }

    func testBlankTextRemovesTheDraftAndTheLastOneRemovesTheFile() throws {
        let store = NoteDraftStore(folder: folder)
        try store.setDraft("à garder", documentId: "doc", page: 0)
        try store.setDraft("à effacer", documentId: "doc", page: 1)
        try store.setDraft("  \n ", documentId: "doc", page: 1)
        XCTAssertEqual(store.drafts(documentId: "doc"), [0: "à garder"])
        try store.setDraft("", documentId: "doc", page: 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(documentId: "doc").path))
        XCTAssertNoThrow(try store.setDraft("", documentId: "absent", page: 0), "rien à effacer : aucune erreur")
    }

    func testRemoveAllOnlyTouchesTheDeletedDocument() throws {
        let store = NoteDraftStore(folder: folder)
        try store.setDraft("supprimé", documentId: "doc", page: 0)
        try store.setDraft("intact", documentId: "other", page: 0)
        try store.removeAll(documentId: "doc")
        XCTAssertEqual(store.drafts(documentId: "doc"), [:])
        XCTAssertEqual(store.draft(documentId: "other", page: 0), "intact")
    }

    func testShiftMovesEveryDraftByTheInsertedPageCount() {
        XCTAssertEqual(NoteDraftStore.shifted([0: "a", 3: "b"], by: 2), [2: "a", 5: "b"])
        XCTAssertEqual(NoteDraftStore.shifted([0: "a"], by: 0), [0: "a"])
    }

    func testCorruptFileReadsAsNoDraftAndIsReplacedOnNextSave() throws {
        let store = NoteDraftStore(folder: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("pas du json".utf8).write(to: store.url(documentId: "doc"))
        XCTAssertEqual(store.drafts(documentId: "doc"), [:])
        try store.setDraft("nouveau", documentId: "doc", page: 0)
        XCTAssertEqual(NoteDraftStore(folder: folder).drafts(documentId: "doc"), [0: "nouveau"])
    }

    /// RET-051 : un avertissement par brouillon non ajouté, dans l'ordre des pages.
    func testPendingPagesListsEveryNonBlankDraftInPageOrder() {
        XCTAssertEqual(NoteDraftStore.pendingPages([12: "b", 3: "a", 7: "  \n"]), [3, 12])
        XCTAssertEqual(NoteDraftStore.pendingPages([:]), [])
    }

    /// RET-051 : « Ajouter » efface le brouillon, l'avertissement de sa page disparaît.
    func testPendingPageDisappearsOnceTheNoteIsAdded() throws {
        let store = NoteDraftStore(folder: folder)
        try store.setDraft("à ajouter", documentId: "doc", page: 4)
        try store.setDraft("autre", documentId: "doc", page: 9)
        XCTAssertEqual(NoteDraftStore.pendingPages(store.drafts(documentId: "doc")), [4, 9])
        try store.setDraft("", documentId: "doc", page: 4)
        XCTAssertEqual(NoteDraftStore.pendingPages(store.drafts(documentId: "doc")), [9])
    }

    func testDiskFormatIsVersionedAndRoundTrips() throws {
        let data = try NoteDraftStore.encode([2: "x", 10: "y"])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"pages":{"10":"y","2":"x"},"version":1}"#)
        XCTAssertEqual(try NoteDraftStore.decode(data), [2: "x", 10: "y"])
        XCTAssertThrowsError(try NoteDraftStore.decode(Data(#"{"version":1,"pages":{"p":"x"}}"#.utf8)))
    }

    /// #49 : les brouillons suivent leur page ; celui d'une page retirée sort du résultat (archivé par l'appelant).
    func testRemappedFollowsPagesAndDropsRemovedOnes() throws {
        let drafts = [0: "a", 2: "b", 3: "c"]
        XCTAssertEqual(NoteDraftStore.remapped(drafts, with: try PageMapping.removal(oldCount: 4, removing: [2])), [0: "a", 2: "c"])
        XCTAssertEqual(NoteDraftStore.remapped(drafts, with: try PageMapping.insertion(oldCount: 4, inserted: 2, at: 0)),
                       NoteDraftStore.shifted(drafts, by: 2))
    }
}
