// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import DictionaryKit
import XCTest

/// #50 : catalogue des dictionnaires téléchargeables (sans aucun vrai dictionnaire : index d'exemple seulement).
final class DictionaryUpdateScheduleTests: XCTestCase {
    func testCheckIsDueOnceAWeek() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        XCTAssertTrue(DictionaryUpdateSchedule.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(DictionaryUpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-6 * 24 * 3600), now: now))
        XCTAssertTrue(DictionaryUpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-7 * 24 * 3600), now: now))
    }

    func testClockMovedBackDoesNotStopChecking() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        XCTAssertTrue(DictionaryUpdateSchedule.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }
}

final class DictionaryCatalogTests: XCTestCase {
    /// Recette locale facultative : vrais ZIP hors dépôt, base jetable, fermeture puis réouverture.
    /// Aucune bibliothèque personnelle n'est ouverte ; le chemin explicite évite de lire les données par défaut.
    func testRealBundledArchivesImportAndReopenWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["KYOKASHO_TEST_LEXICONS"] else {
            throw XCTSkip("Vrais lexiques externes non fournis")
        }
        let source = URL(fileURLWithPath: path, isDirectory: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-import-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let database = try DictionaryDatabase.open(directory: directory)
            for language in BundledLexicon.Language.allCases {
                let archive = source.appendingPathComponent(language.resource + ".zip")
                try DictionaryImporter(database: database).importDictionary(at: archive)
            }
        }
        let reopened = try DictionaryDatabase.open(directory: directory)
        let infos = try reopened.dictionaries()
        XCTAssertEqual(infos.count, 3)
        XCTAssertTrue(infos.allSatisfy { $0.termCount == 3836 && $0.enabled })
        for (language, expected) in [(BundledLexicon.Language.french, "plafond"), (.english, "ceiling"), (.chinese, "天花板")] {
            let info = try XCTUnwrap(infos.first { $0.title == language.title })
            let rows = try reopened.terms(matching: ["天井"], dictionaryIds: [try XCTUnwrap(info.id)])
            XCTAssertFalse(rows.isEmpty)
            XCTAssertTrue(rows.contains { $0.reading == "てんじょう" && $0.glossary.lowercased().contains(expected) })
            var options = LookupOptions()
            options.excludedDictionaryIds = BundledLexicon.excludedDictionaryIds(in: infos, language: language)
            let results = try Translator(database: reopened).findTerms("天井", options: options)
            XCTAssertFalse(results.isEmpty)
            XCTAssertTrue(results.allSatisfy { $0.definitions.allSatisfy { $0.dictionaryTitle == language.title } })
        }
    }

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

    /// D2 : la langue choisie passe en premier, les dictionnaires hors catalogue restent à leur place.
    func testLanguageFirstOrdering() {
        let titles = ["Mon lexique", "Jitendex.org [2026-10-03]", "KANJIDIC [2026-301]", "JMdict (French) [2026-10-28]", "KANJIDIC (French) [2026-301]"]
        let fr = DictionaryCatalog.ordered(titles: titles, first: .french).map { titles[$0] }
        XCTAssertEqual(fr, ["Mon lexique", "JMdict (French) [2026-10-28]", "KANJIDIC (French) [2026-301]", "Jitendex.org [2026-10-03]", "KANJIDIC [2026-301]"])
        let en = DictionaryCatalog.ordered(titles: fr, first: .english).map { fr[$0] }
        XCTAssertEqual(en.first, "Mon lexique")
        XCTAssertEqual(Array(en[1...2]), ["Jitendex.org [2026-10-03]", "KANJIDIC [2026-301]"])
    }

    /// Lexique fourni avec l'app : version lue dans le zip sans l'importer ; absent d'un paquet de test.
    func testBundledLexiconRevisionAndAbsence() throws {
        let zip = try FakeDictionary.make(title: BundledLexicon.title, revision: "2026-10-29")
        XCTAssertEqual(try BundledLexicon.revision(of: zip), "2026-10-29")
        XCTAssertFalse(BundledLexicon.needsUpdate(installedRevision: "2026-10-29", bundledRevision: "2026-10-29"))
        XCTAssertTrue(BundledLexicon.needsUpdate(installedRevision: "2026-10-29", bundledRevision: "2026-11-15"))
        XCTAssertNil(BundledLexicon.url(in: Bundle(for: Self.self)))
        XCTAssertNil(DictionaryCatalog.entry(forInstalledTitle: BundledLexicon.title), "pas une entrée téléchargeable")
        let notZip = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try Data("pas un zip".utf8).write(to: notZip)
        XCTAssertThrowsError(try BundledLexicon.revision(of: notZip))
    }

    /// Même titre d'une version à l'autre : l'import remplace l'ancienne version à sa place, sans doublon.
    func testBundledLexiconReimportReplacesInPlace() throws {
        let db = try DictionaryDatabase.inMemory()
        try DictionaryImporter(database: db).importDictionary(at: FakeDictionary.make(title: "Autre"))
        try DictionaryImporter(database: db).importDictionary(at: FakeDictionary.make(title: BundledLexicon.title, revision: "1"))
        try DictionaryImporter(database: db).importDictionary(at: FakeDictionary.make(title: BundledLexicon.title, revision: "2"))
        let list = try db.dictionaries()
        XCTAssertEqual(list.map(\.title), ["Autre", BundledLexicon.title])
        XCTAssertEqual(list.last?.revision, "2")
    }

    func testBundledLanguagesFollowAppliedLocalizationAndPlatform() {
        XCTAssertEqual(BundledLexicon.language(preferredLocalizations: ["en-GB", "fr"], supportsChinese: false), .english)
        XCTAssertEqual(BundledLexicon.language(preferredLocalizations: ["zh-Hans"], supportsChinese: true), .chinese)
        XCTAssertEqual(BundledLexicon.language(preferredLocalizations: ["zh-Hans"], supportsChinese: false), .french)
        XCTAssertEqual(BundledLexicon.language(preferredLocalizations: [], supportsChinese: true), .french)
        XCTAssertEqual(BundledLexicon.Language.french.title, "Lexique du design d'intérieur (Wikipédia, Wiktionnaire)")
        XCTAssertEqual(Set(BundledLexicon.Language.allCases.map(\.title)).count, 3)
        XCTAssertEqual(Set(BundledLexicon.Language.allCases.map(\.resource)).count, 3)
    }

    /// Importer les trois, mettre à jour l'anglais puis filtrer : aucune autre variante ni dictionnaire personnel
    /// ne doit être supprimé ou désactivé, et aucune définition de la mauvaise langue ne doit sortir.
    func testBundledVariantsCoexistAndLookupUsesOnlySelectedLanguage() throws {
        let db = try DictionaryDatabase.inMemory()
        for language in BundledLexicon.Language.allCases {
            try DictionaryImporter(database: db).importDictionary(at: FakeDictionary.make(title: language.title, revision: "1"))
        }
        try DictionaryImporter(database: db).importDictionary(at: FakeDictionary.make(title: "Personnel"))
        try DictionaryImporter(database: db).importDictionary(at: FakeDictionary.make(title: BundledLexicon.Language.english.title, revision: "2"))
        let infos = try db.dictionaries()
        XCTAssertEqual(infos.count, 4)
        XCTAssertTrue(infos.allSatisfy(\.enabled))
        XCTAssertEqual(infos.first { $0.title == BundledLexicon.Language.french.title }?.revision, "1")
        XCTAssertEqual(infos.first { $0.title == BundledLexicon.Language.chinese.title }?.revision, "1")
        XCTAssertEqual(infos.first { $0.title == BundledLexicon.Language.english.title }?.revision, "2")
        for language in BundledLexicon.Language.allCases {
            let excluded = BundledLexicon.excludedDictionaryIds(in: infos, language: language)
            XCTAssertEqual(excluded.count, 2)
            let selected = infos.filter { !excluded.contains($0.id!) }.map(\.title)
            XCTAssertEqual(Set(selected), [language.title, "Personnel"])
            var options = LookupOptions()
            options.excludedDictionaryIds = excluded
            let results = try Translator(database: db).findTerms("食べる", options: options)
            XCTAssertFalse(results.isEmpty)
            XCTAssertTrue(results.allSatisfy { result in
                result.definitions.allSatisfy { $0.dictionaryTitle == language.title || $0.dictionaryTitle == "Personnel" }
            })
        }
    }
}
