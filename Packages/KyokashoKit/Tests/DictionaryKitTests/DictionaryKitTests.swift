// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import XCTest
import ZIPFoundation
@testable import DictionaryKit

/// Petit dictionnaire factice au format Yomitan v3 (contenu écrit pour les tests).
enum FakeDictionary {
    static func make(title: String = "Test JMdict", revision: String = "1", terms: [[Any]]? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        let archive = try Archive(url: url, accessMode: .create)
        func add(_ path: String, _ object: Any) throws {
            let data = try JSONSerialization.data(withJSONObject: object)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { pos, size in
                data.subdata(in: Int(pos)..<Int(pos) + size)
            }
        }
        func addText(_ path: String, _ text: String) throws {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { pos, size in
                data.subdata(in: Int(pos)..<Int(pos) + size)
            }
        }
        try add("index.json", ["title": title, "revision": revision, "format": 3, "sequenced": true, "author": "Kyokasho tests"])
        try add("tag_bank_1.json", [["v1", "partOfSpeech", 0, "Ichidan verb", 0], ["v5", "partOfSpeech", 0, "Godan verb", 0],
                                    ["n", "partOfSpeech", 0, "noun", 0], ["P", "popular", -10, "common word", 10]])
        try add("term_bank_1.json", terms ?? [
            ["食べる", "たべる", "v1", "v1", 100, ["manger"], 1, "P"],
            ["食べ物", "たべもの", "n", "", 90, ["nourriture", "aliment"], 2, "P"],
            ["照明", "しょうめい", "n", "", 80, [["type": "structured-content", "content": [
                "tag": "div", "style": ["fontWeight": "bold"], "data": ["content": "glossary"],
                "content": ["éclairage ", ["tag": "a", "href": "?query=照らす&wildcards=off", "content": "照らす"]]]]], 3, ""],
            ["書く", "かく", "v5", "v5", 70, ["écrire"], 4, ""],
            ["食", "しょく", "n", "", 10, ["repas"], 5, ""],
            ["照らす", "てらす", "v5", "v5", 50, ["éclairer"], 6, ""],
            ["部屋", "へや", "n", "", 60, ["pièce, chambre"], 7, "P"],
        ])
        try add("term_meta_bank_1.json", [
            ["食べる", "freq", ["reading": "たべる", "frequency": ["value": 1200, "displayValue": "1200㋕"]]],
            ["照明", "freq", 5000],
            ["照明", "pitch", ["reading": "しょうめい", "pitches": [["position": 0]]]],
            ["食べる", "pitch", ["reading": "たべる", "pitches": [["position": 2]]]],
        ])
        try add("kanji_bank_1.json", [["照", "ショウ", "て.る て.らす", "jouyou", ["illuminer", "briller"], ["strokes": "13", "grade": "4"]]])
        try add("kanji_meta_bank_1.json", [["照", "freq", 812]])
        try addText("styles.css", "div[data-sc-content=\"glossary\"] { color: red; }\n@media (x) { a { b: c } }")
        return url
    }
}

final class DictionaryKitTests: XCTestCase {
    var db: DictionaryDatabase!
    var translator: Translator!

    override func setUpWithError() throws {
        db = try DictionaryDatabase.inMemory()
        try DictionaryImporter(database: db).importDictionary(at: try FakeDictionary.make())
        translator = Translator(database: db)
    }

    func testImportCounts() throws {
        let dicts = try db.dictionaries()
        XCTAssertEqual(dicts.count, 1)
        let d = dicts[0]
        XCTAssertEqual(d.title, "Test JMdict")
        XCTAssertEqual(d.termCount, 7)
        XCTAssertEqual(d.termMetaCount, 4)
        XCTAssertEqual(d.kanjiCount, 1)
        XCTAssertEqual(d.kanjiMetaCount, 1)
        XCTAssertNotNil(d.styles)
    }

    func testLongestMatchAndDeinflection() throws {
        let results = try translator.findTerms("食べさせられなかった部屋")
        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.expression, "食べる")
        XCTAssertEqual(first.matchedText, "食べさせられなかった")
        XCTAssertFalse(first.inflectionRules.isEmpty)
        XCTAssertTrue(results.contains { $0.expression == "食" }, "les mots plus courts restent proposés")
        XCTAssertEqual(first.frequencies.first?.display, "1200㋕")
        XCTAssertEqual(first.pitches.first?.downstep, 2)
    }

    func testCompoundBeatsPrefix() throws {
        let first = try XCTUnwrap(translator.findTerms("食べ物を食べる").first)
        XCTAssertEqual(first.expression, "食べ物")
        XCTAssertEqual(first.definitions.first?.tags.first?.name, "n")
        XCTAssertEqual(first.definitions.first?.termTags.first?.category, "popular")
    }

    func testKatakanaAndHalfWidthVariants() throws {
        XCTAssertEqual(try translator.findTerms("ヘヤ").first?.expression, "部屋")
        XCTAssertEqual(try translator.findTerms("ﾍﾔ").first?.expression, "部屋")
    }

    func testPartOfSpeechFilter() throws {
        // 書いた → 書く (v5) : OK ; « 照明た » ne doit rien déconjuguer sur un nom.
        XCTAssertEqual(try translator.findTerms("書いた").first?.expression, "書く")
        XCTAssertEqual(try translator.findTerms("書いた").first?.matchedText, "書いた")
        XCTAssertEqual(try translator.findTerms("照明した").first?.matchedText, "照明")
    }

    func testDisabledDictionaryIsIgnored() throws {
        let id = try XCTUnwrap(db.dictionaries().first?.id)
        try db.setEnabled(false, dictionaryId: id)
        translator.invalidate()
        XCTAssertTrue(try translator.findTerms("食べる").isEmpty)
    }

    func testKanji() throws {
        let k = try XCTUnwrap(translator.findKanji("照"))
        XCTAssertEqual(k.entries.first?.onyomi, ["ショウ"])
        XCTAssertEqual(k.entries.first?.kunyomi, ["て.る", "て.らす"])
        XCTAssertEqual(k.entries.first?.stats["strokes"], "13")
        XCTAssertEqual(k.frequencies.first?.value, 812)
        XCTAssertNil(try translator.findKanji("龍"))
    }

    func testSegmentation() throws {
        let segments = try translator.segment("部屋の照明を書いた。")
        let words = segments.compactMap { $0.term?.expression }
        XCTAssertEqual(words, ["部屋", "照明", "書く"])
        XCTAssertEqual(segments.map(\.text).joined(), "部屋の照明を書いた。")
    }

    /// Le mémo du découpage ne change aucun résultat, à réglages égaux comme différents.
    func testSegmentationMemoKeepsResultsAndHonoursOptions() throws {
        let text = "部屋の照明を書いた。"
        let first = try translator.segment(text)
        XCTAssertEqual(try translator.segment(text), first)
        var excluded = LookupOptions()
        excluded.excludedDictionaryIds = Set(try db.dictionaries().compactMap(\.id))
        XCTAssertTrue(try translator.segment(text, options: excluded).allSatisfy { $0.term == nil },
                      "réglages différents : le mot mémorisé ne doit pas ressortir")
        XCTAssertEqual(try translator.segment(text), first)
    }

    /// Un dictionnaire retiré ou désactivé ne doit plus répondre depuis le mémo.
    func testSegmentationMemoIsClearedByInvalidate() throws {
        let text = "部屋の照明を書いた。"
        XCTAssertFalse(try translator.segment(text).compactMap(\.term).isEmpty)
        for dictionary in try db.dictionaries() {
            try db.setEnabled(false, dictionaryId: try XCTUnwrap(dictionary.id))
        }
        translator.invalidate()
        XCTAssertTrue(try translator.segment(text).allSatisfy { $0.term == nil })
    }

    /// Revue Codex de 40952cf : une recherche lancée avant l'invalidation finit après elle. Son résultat ne doit pas
    /// ressortir pour les appels suivants, alors que le dictionnaire est désactivé.
    func testSegmentationStartedBeforeInvalidateIsNotReused() throws {
        let text = "照明"
        let ids = try db.dictionaries().compactMap(\.id)
        translator.beforeSegmentMemoWrite = { [translator, db] in
            translator!.beforeSegmentMemoWrite = nil
            for id in ids { try? db!.setEnabled(false, dictionaryId: id) }
            translator!.invalidate()
        }
        XCTAssertFalse(try translator.segment(text).compactMap(\.term).isEmpty, "calcul commencé avant la désactivation")
        XCTAssertTrue(try translator.segment(text).allSatisfy { $0.term == nil }, "résultat périmé repris du mémo")
    }

    /// Le découpage allégé choisit le même mot que la recherche complète.
    func testSegmentationPicksTheSameWordAsFullSearch() throws {
        for text in ["部屋の照明を書いた。", "照明", "書いた", "天井の部屋"] {
            var options = LookupOptions()
            options.maxResults = 1
            let chars = Array(text)
            var offset = 0
            for segment in try translator.segment(text) {
                defer { offset += segment.text.count }
                guard let term = segment.term else { continue }
                let best = try XCTUnwrap(translator.findTerms(String(chars[offset...]), options: options).first)
                XCTAssertEqual([term.expression, term.reading, term.matchedText], [best.expression, best.reading, best.matchedText])
                XCTAssertEqual(term.inflectionRules, best.inflectionRules)
                XCTAssertTrue(term.definitions.isEmpty)
            }
        }
    }

    /// Revue Codex de 502383c : une entrée trouvée seulement par une forme courte pèse quand même sur le classement de son
    /// groupe. Le découpage choisit donc le même mot que la recherche complète.
    func testSegmentationKeepsShortFormEntriesInTheirGroup() throws {
        let database = try DictionaryDatabase.inMemory()
        try database.writer.write { connection in
            for (title, priority, expression, reading, rules, score) in [
                ("A-low", 5, "する", "し", "vs", 100), ("A-high", 0, "する", "し", "n", 500), ("B-mid", 2, "為る", "する", "vs", 200),
            ] {
                try DictionaryInfo(title: title, revision: "1", format: 3, priority: priority, termCount: 1).insert(connection)
                try connection.execute(sql: """
                    INSERT INTO term(dictionaryId,expression,reading,definitionTags,rules,score,glossary,sequence,termTags)
                    VALUES (?,?,?,'',?,?,'[]',1,'')
                    """, arguments: [connection.lastInsertedRowID, expression, reading, rules, score])
            }
        }
        let translator = Translator(database: database)
        let direct = try XCTUnwrap(translator.findTerms("した").first)
        XCTAssertEqual([direct.expression, direct.reading], ["する", "し"])
        let term = try XCTUnwrap(translator.segment("した").first?.term)
        XCTAssertEqual([term.expression, term.reading, term.matchedText], [direct.expression, direct.reading, direct.matchedText])
    }

    func testTermsWithoutGlossaryKeepEverythingElse() throws {
        let ids = Set(try db.dictionaries().compactMap(\.id))
        let full = try db.terms(matching: ["照明"], dictionaryIds: ids).sorted { $0.id < $1.id }
        let light = try db.terms(matching: ["照明"], dictionaryIds: ids, withGlossary: false).sorted { $0.id < $1.id }
        XCTAssertFalse(full.isEmpty)
        XCTAssertEqual(full.map(\.id), light.map(\.id))
        XCTAssertEqual(full.map(\.rules), light.map(\.rules))
        XCTAssertEqual(full.map(\.score), light.map(\.score))
        XCTAssertTrue(light.allSatisfy { $0.glossary.isEmpty })
    }

    /// Le découpage ne charge pas les fréquences ; une recherche directe du même texte les garde.
    func testFindTermsStillAttachesMetaAfterSegmentation() throws {
        let before = try translator.findTerms("照明")
        _ = try translator.segment("照明")
        XCTAssertEqual(try translator.findTerms("照明").map(\.frequencies), before.map(\.frequencies))
    }

    /// Recette 1.4.5 : sur un thème clair, les furigana restaient blancs (`--fg2` non dérivé de l'encre du thème).
    func testLightThemeDerivesFuriganaInkFromThemeInk() {
        var renderer = GlossaryRenderer(inflectionName: { $0 })
        renderer.palette = ["fg": "#1b2226", "bg": "#ffffff"]
        XCTAssertTrue(renderer.paletteCSS.contains("--fg2:rgba(27,34,38,0.66)"))
        XCTAssertTrue(renderer.paletteCSS.contains("color-scheme:light"))
        XCTAssertTrue(renderer.paletteCSS.contains(".tag{background:rgba(0,0,0,.08)}"))
        renderer.palette = ["fg": "#eff4f2", "bg": "#1c252a"]
        XCTAssertTrue(renderer.paletteCSS.contains("--fg2:rgba(239,244,242,0.66)"))
        XCTAssertTrue(renderer.paletteCSS.contains("color-scheme:dark"))
        XCTAssertFalse(renderer.paletteCSS.contains(".tag{"))
    }

    /// Revue Codex de 2b55bd9 : encres atténuées à 4,5:1 au moins, sur Sépia et Terre où l'opacité fixe échouait.
    func testSecondaryInkReachesReadableContrast() {
        func luminance(_ v: [Double]) -> Double {
            let c = v.map { $0 / 255 <= 0.03928 ? $0 / 255 / 12.92 : pow(($0 / 255 + 0.055) / 1.055, 2.4) }
            return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        }
        for (ink, surface) in [((59, 42, 26), (248, 240, 225)), ((59, 42, 26), (230, 216, 190)), ((46, 42, 36), (243, 238, 229)), ((46, 42, 36), (221, 211, 195))] {
            for start in [0.66, 0.46] {
                let a = GlossaryRenderer.opacity(of: (ink.0, ink.1, ink.2), from: start, on: [(surface.0, surface.1, surface.2)])
                let mixed = [ink.0, ink.1, ink.2].enumerated().map { i, v in
                    Double(v) * a + Double([surface.0, surface.1, surface.2][i]) * (1 - a)
                }
                let one = luminance(mixed), two = luminance([Double(surface.0), Double(surface.1), Double(surface.2)])
                XCTAssertGreaterThanOrEqual((max(one, two) + 0.05) / (min(one, two) + 0.05), 4.5)
            }
        }
    }

    func testRendering() throws {
        let results = try translator.findTerms("照明")
        let renderer = GlossaryRenderer(inflectionName: { [translator] in translator!.inflectionName($0) })
        let html = renderer.page(terms: results, dictionaries: try db.dictionaries())
        XCTAssertTrue(html.contains("<ruby>"))
        XCTAssertTrue(html.contains("しょうめい"))
        XCTAssertTrue(html.contains("data-query=\"照らす\""), "lien interne Yomitan → recherche")
        XCTAssertTrue(html.contains("font-weight:bold"))
        XCTAssertTrue(html.contains("[data-dictionary=\"Test JMdict\"] div[data-sc-content=\"glossary\"]"), "CSS du dictionnaire limité à ses définitions")
        XCTAssertFalse(html.contains("@media"), "règles @ ignorées")
        XCTAssertTrue(html.contains("<svg"), "graphique d'accent")
        // Échappement : pas d'injection depuis un dictionnaire.
        XCTAssertEqual(renderer.escape("<script>"), "&lt;script&gt;")
        let k = renderer.page(kanji: try XCTUnwrap(translator.findKanji("照")))
        XCTAssertTrue(k.contains("ショウ"))
    }

    func testInflectedRendering() throws {
        let results = try translator.findTerms("食べた")
        let html = GlossaryRenderer(inflectionName: { [translator] in translator!.inflectionName($0) })
            .page(terms: results, dictionaries: [])
        XCTAssertTrue(html.contains("class=\"inflection\""))
    }

    func testUpdateReplacesAndKeepsPriority() throws {
        let other = try FakeDictionary.make(title: "Autre", terms: [["猫", "ねこ", "n", "", 1, ["chat"], 1, ""]])
        try DictionaryImporter(database: db).importDictionary(at: other)
        let ids = try db.dictionaries().compactMap(\.id)
        try db.setOrder(ids.reversed())
        let before = try XCTUnwrap(db.dictionary(title: "Test JMdict"))
        try DictionaryImporter(database: db).importDictionary(at: try FakeDictionary.make(revision: "2"))
        let after = try XCTUnwrap(db.dictionary(title: "Test JMdict"))
        XCTAssertEqual(after.revision, "2")
        XCTAssertEqual(after.priority, before.priority)
        XCTAssertEqual(try db.dictionaries().count, 2)
        XCTAssertThrowsError(try DictionaryImporter(database: db).importDictionary(at: try FakeDictionary.make(), replaceExisting: false))
    }

    func testProfilesAndAudio() throws {
        var profiles = DictionaryProfiles()
        var p = profiles.active
        p.lookup.scanLength = 30
        profiles.active = p
        let data = try JSONEncoder().encode(profiles)
        let back = try JSONDecoder().decode(DictionaryProfiles.self, from: data)
        XCTAssertEqual(back.active.lookup.scanLength, 30)
        let decoded = try JSONDecoder().decode(LookupOptions.self, from: Data(#"{"scanLength":500}"#.utf8))
        XCTAssertEqual(decoded.scanLength, 40, "borné")
        let urls = AudioSource.defaults[1].resolve(term: "食べる", reading: "たべる")
        XCTAssertTrue(urls[0].hasPrefix("https://assets.languagepod101.com/"))
        XCTAssertFalse(urls[0].contains("食"), "encodé")
        XCTAssertEqual(AudioSource.defaults[0].resolve(term: "猫", reading: "ねこ").first, "猫_ねこ.mp3")
    }

    func testDelete() throws {
        let id = try XCTUnwrap(db.dictionaries().first?.id)
        try db.deleteDictionary(id: id)
        XCTAssertTrue(try db.dictionaries().isEmpty)
        let left = try db.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM term") }
        XCTAssertEqual(left, 0)
    }

    func testRejectsNonDictionary() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        let archive = try Archive(url: url, accessMode: .create)
        let data = Data("x".utf8)
        try archive.addEntry(with: "readme.txt", type: .file, uncompressedSize: Int64(1)) { (_: Int64, _: Int) in data }
        XCTAssertThrowsError(try DictionaryImporter(database: db).importDictionary(at: url)) {
            XCTAssertEqual($0 as? DictionaryImporter.ImportError, .notADictionary)
        }
    }

    func testLookupPerformance() throws {
        // Base plus grosse : 20 000 entrées factices, recherche d'une phrase conjuguée.
        var rows: [[Any]] = []
        for i in 0..<20000 { rows.append(["語\(i)", "ご\(i)", "n", "", i, ["mot \(i)"], i, ""]) }
        rows.append(["食べる", "たべる", "v1", "v1", 100, ["manger"], 1, ""])
        let big = try DictionaryDatabase.inMemory()
        try DictionaryImporter(database: big).importDictionary(at: try FakeDictionary.make(title: "Gros", terms: rows))
        let t = Translator(database: big)
        measure { _ = try? t.findTerms("食べさせられなかったでしょう") }
    }
}
