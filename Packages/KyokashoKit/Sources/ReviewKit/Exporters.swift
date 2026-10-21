// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB
import ZIPFoundation

/// Export des cartes vers Anki : CSV, paquet `.apkg`, lien AnkiMobile.
///
/// Le format `.apkg` (zip avec `collection.anki2` + `media`) suit la description publique
/// du format faite par genanki (MIT) ; le code est écrit pour Kyōkasho, rien n'est copié.
/// Les cartes partent comme neuves dans Anki : l'état FSRS n'est pas exporté.
public enum AnkiExport {

    // MARK: CSV

    /// CSV lisible par l'import d'Anki (en-têtes `#…`, une ligne par carte, tags en dernier).
    public static func csv(cards: [StudyCard], template: NoteTemplate, deckName: String) -> String {
        let columns = template.fieldNames + ["Tags"]
        var lines = [
            "#separator:comma",
            "#html:true",
            "#notetype:\(template.name)",
            "#deck:\(deckName)",
            "#columns:" + columns.map(csvField).joined(separator: ","),
            "#tags column:\(columns.count)",
        ]
        for card in cards {
            let values = template.fieldNames.map { card.fields[$0] ?? "" } + [card.tags.joined(separator: " ")]
            lines.append(values.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Guillemets façon RFC 4180 : on quote si `,` `"` ou retour à la ligne, et `"` est doublé.
    static func csvField(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: .apkg

    /// Écrit un paquet `.apkg` à `url`. Seuls les médias cités par les cartes sont inclus.
    public static func apkg(cards: [StudyCard], template: NoteTemplate, deckName: String,
                            mediaRoot: URL, to url: URL, now: Date = Date()) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("apkg-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let collection = work.appendingPathComponent("collection.anki2")
        try writeCollection(cards: cards, template: template, deckName: deckName, to: collection, now: now)

        // Médias : fichiers renommés 0, 1, 2… + table `media` en JSON.
        var mediaMap: [String: String] = [:]
        var mediaFiles: [(String, URL)] = []
        let names = cards.reduce(into: Set<String>()) { $0.formUnion(ReviewStore.mediaReferences(in: $1.fields)) }
        for name in names.sorted() {
            let file = mediaRoot.appendingPathComponent(name)
            guard fm.fileExists(atPath: file.path) else { continue }
            let index = String(mediaFiles.count)
            mediaMap[index] = name
            mediaFiles.append((index, file))
        }

        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .create)
        func add(_ path: String, _ data: Data) throws {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                                 compressionMethod: .deflate) { (pos: Int64, size: Int) in
                data.subdata(in: Int(pos)..<Int(pos) + size)
            }
        }
        try add("collection.anki2", try Data(contentsOf: collection))
        try add("media", try JSONSerialization.data(withJSONObject: mediaMap, options: [.sortedKeys]))
        for (index, file) in mediaFiles { try add(index, try Data(contentsOf: file)) }
    }

    /// Identifiant stable (entier positif < 2^53) tiré d'un nom : même modèle = même `mid` à chaque export.
    static func stableId(_ s: String) -> Int64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        return Int64(h & ((1 << 53) - 1)) | (1 << 40)
    }

    static func writeCollection(cards: [StudyCard], template: NoteTemplate, deckName: String,
                                to path: URL, now: Date) throws {
        let db = try DatabaseQueue(path: path.path)
        let ms = Int64(now.timeIntervalSince1970 * 1000)
        let secs = Int64(now.timeIntervalSince1970)
        let mid = stableId("model:" + template.name)
        let did = stableId("deck:" + deckName)

        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE col (id integer primary key, crt integer not null, mod integer not null,
                  scm integer not null, ver integer not null, dty integer not null, usn integer not null,
                  ls integer not null, conf text not null, models text not null, decks text not null,
                  dconf text not null, tags text not null);
                CREATE TABLE notes (id integer primary key, guid text not null, mid integer not null,
                  mod integer not null, usn integer not null, tags text not null, flds text not null,
                  sfld integer not null, csum integer not null, flags integer not null, data text not null);
                CREATE TABLE cards (id integer primary key, nid integer not null, did integer not null,
                  ord integer not null, mod integer not null, usn integer not null, type integer not null,
                  queue integer not null, due integer not null, ivl integer not null, factor integer not null,
                  reps integer not null, lapses integer not null, left integer not null, odue integer not null,
                  odid integer not null, flags integer not null, data text not null);
                CREATE TABLE revlog (id integer primary key, cid integer not null, usn integer not null,
                  ease integer not null, ivl integer not null, lastIvl integer not null, factor integer not null,
                  time integer not null, type integer not null);
                CREATE TABLE graves (usn integer not null, oid integer not null, type integer not null);
                CREATE INDEX ix_notes_usn on notes (usn);
                CREATE INDEX ix_cards_usn on cards (usn);
                CREATE INDEX ix_revlog_usn on revlog (usn);
                CREATE INDEX ix_cards_nid on cards (nid);
                CREATE INDEX ix_cards_sched on cards (did, queue, due);
                CREATE INDEX ix_revlog_cid on revlog (cid);
                CREATE INDEX ix_notes_csum on notes (csum);
                """)

            let qfmt = (try? CardTemplate(template.front))?.ankiSource ?? template.front
            let afmt = (try? CardTemplate(template.back))?.ankiSource ?? template.back
            let model: [String: Any] = [
                "id": String(mid), "name": template.name, "type": 0, "mod": secs, "usn": -1,
                "sortf": 0, "did": did, "css": template.css,
                "flds": template.fieldNames.enumerated().map { i, name in
                    ["name": name, "ord": i, "sticky": false, "rtl": false,
                     "font": "Hiragino Sans", "size": 20, "media": [String]()] as [String: Any]
                },
                "tmpls": [[
                    "name": "Carte 1", "ord": 0, "qfmt": qfmt, "afmt": afmt, "bqfmt": "", "bafmt": "",
                    "did": NSNull(), "bfont": "", "bsize": 0,
                ] as [String: Any]],
                "req": [[0, "any", [0]]],
                "latexPre": "\\documentclass[12pt]{article}\n\\special{papersize=3in,5in}\n\\usepackage[utf8]{inputenc}\n\\usepackage{amssymb,amsmath}\n\\pagestyle{empty}\n\\setlength{\\parindent}{0in}\n\\begin{document}\n",
                "latexPost": "\\end{document}",
                "latexsvg": false, "tags": [String](), "vers": [String](),
            ]
            func deck(_ id: Int64, _ name: String) -> [String: Any] {
                ["id": id, "name": name, "desc": "", "mod": secs, "usn": -1, "collapsed": false,
                 "browserCollapsed": false, "newToday": [0, 0], "revToday": [0, 0], "lrnToday": [0, 0],
                 "timeToday": [0, 0], "dyn": 0, "conf": 1, "extendNew": 10, "extendRev": 50]
            }
            let dconf: [String: Any] = [
                "id": 1, "name": "Default", "mod": 0, "usn": 0, "maxTaken": 60, "autoplay": true,
                "timer": 0, "replayq": true, "dyn": false,
                "new": ["perDay": 20, "delays": [1, 10], "ints": [1, 4, 7], "initialFactor": 2500,
                        "separate": true, "order": 1, "bury": false],
                "rev": ["perDay": 200, "ease4": 1.3, "fuzz": 0.05, "ivlFct": 1, "maxIvl": 36500,
                        "minSpace": 1, "bury": false],
                "lapse": ["delays": [10], "mult": 0, "minInt": 1, "leechFails": 8, "leechAction": 0],
            ]
            let conf: [String: Any] = [
                "curDeck": did, "curModel": String(mid), "activeDecks": [did], "newSpread": 0,
                "collapseTime": 1200, "timeLim": 0, "estTimes": true, "dueCounts": true,
                "sortType": "noteFld", "sortBackwards": false, "nextPos": cards.count + 1,
            ]
            func json(_ o: Any) throws -> String {
                String(decoding: try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), as: UTF8.self)
            }
            try db.execute(sql: "INSERT INTO col VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, '{}')", arguments: [
                secs, ms, ms, try json(conf), try json([String(mid): model]),
                try json(["1": deck(1, "Default"), String(did): deck(did, deckName)]),
                try json(["1": dconf]),
            ])

            for (i, card) in cards.enumerated() {
                let nid = ms + Int64(i)
                let fields = template.fieldNames.map { card.fields[$0] ?? "" }
                let tags = card.tags.isEmpty ? "" : " " + card.tags.joined(separator: " ") + " "
                let sfld = CardTemplate.stripHTML(fields.first ?? "")
                try db.execute(sql: "INSERT INTO notes VALUES (?, ?, ?, ?, -1, ?, ?, ?, 0, 0, '')", arguments: [
                    nid, card.guid, mid, secs, tags, fields.joined(separator: "\u{1F}"), sfld,
                ])
                try db.execute(sql: "INSERT INTO cards VALUES (?, ?, ?, 0, ?, -1, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, '')",
                               arguments: [nid, nid, did, secs, i + 1])
            }
        }
        try db.close()
    }

    // MARK: AnkiMobile

    /// Lien `anki://x-callback-url/addnote` (texte seulement : AnkiMobile ne prend pas les médias par URL).
    public static func ankiMobileURL(fields: [String: String], fieldNames: [String], noteType: String,
                                     deck: String, tags: [String] = []) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        var parts = ["type=" + enc(noteType), "deck=" + enc(deck)]
        for name in fieldNames {
            guard let value = fields[name], !value.isEmpty else { continue }
            parts.append("fld" + enc(name) + "=" + enc(value))
        }
        if !tags.isEmpty { parts.append("tags=" + enc(tags.joined(separator: " "))) }
        return URL(string: "anki://x-callback-url/addnote?" + parts.joined(separator: "&"))
    }
}
