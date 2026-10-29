// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import DictionaryKit
import XCTest

/// #50 : catalogue des dictionnaires téléchargeables (sans aucun vrai dictionnaire : index d'exemple seulement).
final class DictionaryCatalogTests: XCTestCase {
    func testBaseTitleAndMatching() {
        XCTAssertEqual(DictionaryCatalog.baseTitle("JMdict (French) [2026-10-28]"), "JMdict (French)")
        XCTAssertEqual(DictionaryCatalog.baseTitle("Jitendex.org [2026-10-03]"), "Jitendex.org")
        XCTAssertEqual(DictionaryCatalog.baseTitle("Mon lexique"), "Mon lexique")
        XCTAssertEqual(DictionaryCatalog.entry(forInstalledTitle: "JMnedict [2026-10-28]")?.id, "jmnedict")
        XCTAssertNil(DictionaryCatalog.entry(forInstalledTitle: "Autre [2026]"))
        // Titres réels relevés le 29/10/2026.
        XCTAssertEqual(DictionaryCatalog.entry(forInstalledTitle: "KANJIDIC (French) [2026-301]")?.id, "kanjidic-fr")
        XCTAssertEqual(DictionaryCatalog.entry(forInstalledTitle: "KANJIDIC [2026-301]")?.id, "kanjidic-en")
    }

    func testCatalogIsConsistent() {
        let all = DictionaryCatalog.entries
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(Set(all.map(\.titlePrefix)).count, all.count)
        XCTAssertTrue(all.allSatisfy { $0.indexURL.scheme == "https" && !$0.license.isEmpty })
        XCTAssertTrue(all.contains { $0.language == .french && $0.role == .general })
    }

    func testIndexDecodingAndUpdates() throws {
        let json = #"{"title":"JMdict (French) [2026-10-28]","format":3,"revision":"JMdict.2026-10-28","isUpdatable":true,"indexUrl":"https://example.org/i.json","downloadUrl":"https://example.org/d.zip"}"#
        let index = try YomitanIndex.decode(Data(json.utf8))
        XCTAssertEqual(index.downloadUrl?.absoluteString, "https://example.org/d.zip")
        XCTAssertTrue(index.isNewer(thanInstalledTitle: "JMdict (French) [2026-10-20]", revision: "JMdict.2026-10-20"))
        XCTAssertFalse(index.isNewer(thanInstalledTitle: "JMdict (French) [2026-10-28]", revision: "JMdict.2026-10-28"))
        let noRevision = try YomitanIndex.decode(Data(#"{"title":"Jitendex.org [2026-10-03]"}"#.utf8))
        XCTAssertTrue(noRevision.isNewer(thanInstalledTitle: "Jitendex.org [2026-09-01]", revision: "x"))
        XCTAssertFalse(noRevision.isNewer(thanInstalledTitle: "Jitendex.org [2026-10-03]", revision: "x"))
    }
}
