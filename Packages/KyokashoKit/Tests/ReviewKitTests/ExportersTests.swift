// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GRDB
import XCTest
import ZIPFoundation
@testable import ReviewKit

final class ExportersTests: XCTestCase {
    let template = NoteTemplate(name: "Japonais", fieldNames: ["Mot", "Sens", "Image"],
                                front: "{{Mot}}", back: "{{#if Sens}}{{Sens}}{{/if}}", css: ".card{}")

    func card(_ word: String, _ fields: [String: String], tags: [String] = []) -> StudyCard {
        StudyCard(deckId: 1, templateId: 1, key: word + "|", fields: fields.merging(["Mot": word]) { a, _ in a }, tags: tags)
    }

    func testCSV() {
        let csv = AnkiExport.csv(cards: [card("猫", ["Sens": "chat, \"félin\"\nanimal"], tags: ["n5", "animal"])],
                                 template: template, deckName: "Kyōkasho")
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(Array(lines.prefix(6)), ["#separator:comma", "#html:true", "#notetype:Japonais",
                                                 "#deck:Kyōkasho", "#columns:Mot,Sens,Image,Tags", "#tags column:4"])
        XCTAssertTrue(csv.contains("猫,\"chat, \"\"félin\"\"\nanimal\",,n5 animal\n"))
        XCTAssertEqual(AnkiExport.csvField("simple"), "simple")
    }

    func testAPKG() throws {
        let fm = FileManager.default
        let media = fm.temporaryDirectory.appendingPathComponent("media-" + UUID().uuidString)
        try fm.createDirectory(at: media, withIntermediateDirectories: true)
        try Data("jpg".utf8).write(to: media.appendingPathComponent("chat.jpg"))
        try Data("inutile".utf8).write(to: media.appendingPathComponent("autre.jpg"))
        let out = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".apkg")
        defer { try? fm.removeItem(at: media); try? fm.removeItem(at: out) }

        let cards = [card("猫", ["Sens": "<b>chat</b>", "Image": "<img src=\"chat.jpg\">"], tags: ["n5"]),
                     card("犬", ["Sens": "chien"])]
        try AnkiExport.apkg(cards: cards, template: template, deckName: "Kyōkasho", mediaRoot: media, to: out)

        let archive = try Archive(url: out, accessMode: .read)
        func read(_ name: String) throws -> Data {
            var data = Data()
            _ = try archive.extract(try XCTUnwrap(archive[name])) { data.append($0) }
            return data
        }
        let mediaMap = try JSONSerialization.jsonObject(with: try read("media")) as? [String: String]
        XCTAssertEqual(mediaMap, ["0": "chat.jpg"])
        XCTAssertEqual(try read("0"), Data("jpg".utf8))
        XCTAssertNil(archive["1"])

        let dbURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".anki2")
        defer { try? fm.removeItem(at: dbURL) }
        try read("collection.anki2").write(to: dbURL)
        let db = try DatabaseQueue(path: dbURL.path)
        try db.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cards"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT ver FROM col"), 11)
            let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT flds, sfld, tags, guid FROM notes ORDER BY id LIMIT 1"))
            XCTAssertEqual(row["flds"] as String, "猫\u{1F}<b>chat</b>\u{1F}<img src=\"chat.jpg\">")
            XCTAssertEqual(row["tags"] as String, " n5 ")
            XCTAssertEqual(row["guid"] as String, cards[0].guid)
            let modelsJSON = try XCTUnwrap(String.fetchOne(db, sql: "SELECT models FROM col"))
            let models = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(modelsJSON.utf8)) as? [String: [String: Any]])
            let model = try XCTUnwrap(models.values.first)
            XCTAssertEqual(model["name"] as? String, "Japonais")
            XCTAssertEqual((model["flds"] as? [[String: Any]])?.compactMap { $0["name"] as? String }, ["Mot", "Sens", "Image"])
            let tmpl = try XCTUnwrap((model["tmpls"] as? [[String: Any]])?.first)
            XCTAssertEqual(tmpl["afmt"] as? String, "{{#Sens}}{{Sens}}{{/Sens}}")
            let decksJSON = try XCTUnwrap(String.fetchOne(db, sql: "SELECT decks FROM col"))
            XCTAssertTrue(decksJSON.contains("Kyōkasho"))
        }
        XCTAssertEqual(AnkiExport.stableId("model:Japonais"), AnkiExport.stableId("model:Japonais"))
        XCTAssertLessThan(AnkiExport.stableId("x"), 1 << 53)
    }

    func testAnkiMobileURL() throws {
        let url = try XCTUnwrap(AnkiExport.ankiMobileURL(fields: ["Mot": "猫", "Sens": "chat & chien = 2?", "Image": ""],
                                                         fieldNames: ["Mot", "Sens", "Image"],
                                                         noteType: "Kyōkasho", deck: "Mon paquet", tags: ["a", "b"]))
        let s = url.absoluteString
        XCTAssertTrue(s.hasPrefix("anki://x-callback-url/addnote?type=Ky%C5%8Dkasho&deck=Mon%20paquet&"))
        XCTAssertTrue(s.contains("fldSens=chat%20%26%20chien%20%3D%202%3F"))
        XCTAssertFalse(s.contains("fldImage"))
        XCTAssertTrue(s.hasSuffix("tags=a%20b"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "fldMot" }?.value, "猫")
    }
}
