// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
@testable import MorphologyKit
import XCTest

/// Avec le vrai dictionnaire seulement : `KYOKASHO_UNIDIC=<dossier dicdir> swift test --filter MeCabTests`.
final class MeCabTests: XCTestCase {
    private func mecab() throws -> MeCab {
        guard let path = ProcessInfo.processInfo.environment["KYOKASHO_UNIDIC"] else { throw XCTSkip("KYOKASHO_UNIDIC absent") }
        return try MeCab(dictionary: URL(fileURLWithPath: path))
    }

    func testCSV() {
        XCTAssertEqual(MeCab.csv("a,\"b,c\",d"), ["a", "b,c", "d"])
    }

    func testReadingsInContext() throws {
        let m = try mecab()
        let tokens = m.tokens("天井を張る場合、一般的に小屋裏、天井裏にスペースをとる。")
        let map = Dictionary(tokens.map { ($0.surface, $0.reading) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(map["天井"], "てんじょう")
        XCTAssertEqual(map["場合"], "ばあい")
        XCTAssertEqual(map["張る"] ?? map["張"], map["張る"] != nil ? "はる" : "は")
        // Les zones recouvrent le texte dans l'ordre.
        let text = "今日は上手に読んだ。" as NSString
        let t2 = m.tokens(text as String)
        XCTAssertEqual(t2.map(\.surface).joined(), text as String)
        for t in t2 { XCTAssertEqual(text.substring(with: t.range), t.surface) }
        XCTAssertEqual(t2.first?.reading, "きょう")
        print(t2.map { "\($0.surface)/\($0.reading)/\($0.lemma)" })
    }
}

/// Décompression de la vraie archive : `KYOKASHO_UNIDIC_ARCHIVE=<…tar.gz> swift test --filter UniDicTests`.
final class UniDicTests: XCTestCase {
    func testExtract() throws {
        guard let path = ProcessInfo.processInfo.environment["KYOKASHO_UNIDIC_ARCHIVE"] else { throw XCTSkip("archive absente") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("unidic-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try UniDic.extract(archive: URL(fileURLWithPath: path), to: dir)
        XCTAssertTrue(UniDic.isInstalled(at: dir))
        let size = (try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("sys.dic").path)[.size] as? NSNumber)?.intValue
        XCTAssertEqual(size, 187_680_870)
        let m = try MeCab(dictionary: dir)
        XCTAssertEqual(m.tokens("天井").first?.reading, "てんじょう")
    }
}
