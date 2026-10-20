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
