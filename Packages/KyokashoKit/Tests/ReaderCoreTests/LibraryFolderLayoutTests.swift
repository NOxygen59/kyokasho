// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// PLAN-T5-001, étape E2 : disposition de l'accueil avec dossiers (DEC-T5-07, 08, 09) et sélection à ranger.
final class LibraryFolderLayoutTests: XCTestCase {
    private func doc(_ id: String, manga: Bool = false) -> LibraryDocument {
        var document = LibraryDocument(id: id, title: id, originalFileName: "\(id).pdf", pageCount: 1, fileSize: 1)
        if manga { document.settingsOverride.mangaSpace = true }
        return document
    }

    private let study1 = LibraryFolder(id: "f1", name: "Grammaire", space: "study")
    private let study2 = LibraryFolder(id: "f2", name: "Vide", space: "study")
    private let manga1 = LibraryFolder(id: "m1", name: "Shōnen", space: "manga")

    private var folders: LibraryFolders {
        LibraryFolders(folders: [study1, manga1, study2], membership: ["a": "f1", "b": "f1", "z": "m1", "x": "inconnu"])
    }

    func testFoldersComeFirstAndLooseDocumentsKeepTheirOrder() {
        let docs = ["c", "a", "x", "b"].map { doc($0) }
        let result = LibraryFolderLayout.layout(documents: docs, folders: folders, space: .study, filtering: false)
        XCTAssertEqual(result.tiles.map(\.folder.id), ["f1", "f2"], "ordre de la base, espace affiché seulement")
        XCTAssertEqual(result.tiles[0].documents.map(\.id), ["a", "b"], "ordre reçu gardé")
        XCTAssertEqual(result.loose.map(\.id), ["c", "x"], "dossier inconnu : le document reste visible")
    }

    func testEmptyFolderStaysVisibleWithoutFilter() {
        let result = LibraryFolderLayout.layout(documents: [doc("c")], folders: folders, space: .study, filtering: false)
        XCTAssertEqual(result.tiles.map(\.folder.id), ["f1", "f2"])
        XCTAssertTrue(result.tiles.allSatisfy(\.documents.isEmpty))
    }

    func testFilterHidesFoldersWithoutMatchingDocuments() {
        let result = LibraryFolderLayout.layout(documents: [doc("b"), doc("c")], folders: folders, space: .study,
                                                filtering: true)
        XCTAssertEqual(result.tiles.map(\.folder.id), ["f1"])
        XCTAssertEqual(result.tiles[0].documents.map(\.id), ["b"])
        XCTAssertEqual(result.loose.map(\.id), ["c"])
    }

    func testMembershipToTheOtherSpaceIsIgnored() {
        // Un document rangé dans un dossier Manga mais affiché côté Livres & Manuels reste dans les sections.
        let result = LibraryFolderLayout.layout(documents: [doc("z")], folders: folders, space: .study, filtering: false)
        XCTAssertEqual(result.loose.map(\.id), ["z"])
        let manga = LibraryFolderLayout.layout(documents: [doc("z", manga: true)], folders: folders, space: .manga,
                                               filtering: false)
        XCTAssertEqual(manga.tiles.map(\.folder.id), ["m1"])
        XCTAssertEqual(manga.tiles[0].documents.map(\.id), ["z"])
    }

    func testCommonSpaceRefusesAMixedSelection() {
        XCTAssertEqual(LibraryFolderLayout.commonSpace(of: [doc("a"), doc("b")]), .study)
        XCTAssertEqual(LibraryFolderLayout.commonSpace(of: [doc("z", manga: true)]), .manga)
        XCTAssertNil(LibraryFolderLayout.commonSpace(of: [doc("a"), doc("z", manga: true)]))
        XCTAssertNil(LibraryFolderLayout.commonSpace(of: []))
    }
}
