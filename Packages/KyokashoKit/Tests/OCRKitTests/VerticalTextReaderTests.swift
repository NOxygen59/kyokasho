// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import CoreText
import ImageIO
import XCTest
@testable import OCRKit

/// Texte vertical : Vision ne le lit pas, `VerticalTextReader` le remet à l'horizontale.
final class VerticalTextReaderTests: XCTestCase {
    /// Page blanche où le texte est écrit caractère par caractère, en colonnes de droite à gauche ou en lignes.
    private func page(columns: [String] = [], rows: [String] = [], size: CGFloat = 26) throws -> CGImage {
        let width = 960, height = 1364
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 0, alpha: 1)
        let font = CTFontCreateWithName("HiraginoSans-W6" as CFString, size, nil)
        func draw(_ character: Character, x: CGFloat, y: CGFloat) {
            let attributes = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true] as CFDictionary
            let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, String(character) as CFString, attributes)!)
            context.textPosition = CGPoint(x: x, y: CGFloat(height) - y)
            CTLineDraw(line, context)
        }
        for (index, text) in columns.enumerated() {
            for (position, character) in text.enumerated() {
                draw(character, x: 800 - CGFloat(index) * size * 1.6, y: 200 + CGFloat(position) * size * 1.15)
            }
        }
        for (index, text) in rows.enumerated() {
            for (position, character) in text.enumerated() {
                draw(character, x: 100 + CGFloat(position) * size * 1.05, y: 900 + CGFloat(index) * size * 1.8)
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    func testReadsColumnsRightToLeft() throws {
        let lines = try VerticalTextReader.read(try page(columns: ["重要な勝負になると", "負けなしですね"]), languages: ["ja-JP"], skipping: [])
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy(\.vertical))
        XCTAssertGreaterThan(lines[0].box.x, lines[1].box.x)
        XCTAssertEqual(lines[0].text, "重要な勝負になると")
        XCTAssertEqual(lines[1].text, "負けなしですね")
        XCTAssertEqual(lines[0].charBoxes.count, lines[0].text.count)
    }

    func testCharacterBoxesFollowTheColumnDownward() throws {
        let line = try XCTUnwrap(try VerticalTextReader.read(try page(columns: ["重要な勝負になると"]), languages: ["ja-JP"], skipping: []).first)
        let positions = line.charBoxes.map(\.y)
        XCTAssertEqual(positions, positions.sorted())
        for box in line.charBoxes { XCTAssertGreaterThanOrEqual(box.x + 0.001, line.box.x) }
    }

    /// Une zone déjà lue n'est pas relue ; rien à faire hors du japonais.
    func testSkipsKnownZonesAndOtherLanguages() throws {
        let image = try page(columns: ["重要な勝負になると"])
        let whole = NormBox(x: 0, y: 0, w: 1, h: 1)
        XCTAssertEqual(try VerticalTextReader.read(image, languages: ["ja-JP"], skipping: [whole]), [])
        XCTAssertEqual(try VerticalTextReader.read(image, languages: ["en-US"], skipping: []), [])
    }

    /// Une page horizontale ne doit pas gagner de lignes inventées.
    func testHorizontalPageAddsNothingOnceVisionHasReadIt() throws {
        let rows = ["日本語の教科書を読んでいます", "毎日少しずつ勉強しましょう", "漢字の読み方を覚えます"]
        let image = try page(rows: rows)
        let known = NormBox(x: 0.08, y: 0.62, w: 0.9, h: 0.14)
        XCTAssertEqual(try VerticalTextReader.read(image, languages: ["ja-JP"], skipping: [known]), [])
    }

    /// Recette 1.4.8 : le toucher tombait sur le mauvais mot. Un point de suspension garde ses cases, et ce qui suit reste en face.
    func testCleaningKeepsEachCharacterOnItsCell() throws {
        let read: [VerticalTextReader.ReadCharacter] = [("：", 0), ("・", 1), ("そ", 2), ("の", 3), ("様", 4), ("子", 5)]
            .map { .init(character: $0.0, cells: $0.1...$0.1) }
        let cleaned = try XCTUnwrap(VerticalTextReader.cleaned(read))
        XCTAssertEqual(String(cleaned.map(\.character)), "…その様子")
        XCTAssertEqual(cleaned[0].cells, 0...1)
        XCTAssertEqual(cleaned[3].cells, 4...4)
    }

    /// Sur le vrai chapitre, Vision a rendu des positions dans le désordre : l'étendue inversée faisait planter l'app.
    func testCleaningSurvivesCharactersOutOfOrder() throws {
        let read: [VerticalTextReader.ReadCharacter] = [("そ", 0), ("：", 4), ("・", 2), ("の", 3), ("様", 5)]
            .map { .init(character: $0.0, cells: $0.1...$0.1) }
        let cleaned = try XCTUnwrap(VerticalTextReader.cleaned(read))
        XCTAssertEqual(cleaned[1].cells, 2...4)
    }

    func testCellIndexFollowsStripPosition() {
        // Marges de 16 de part et d'autre, 3 cases de 100.
        let width = 332
        XCTAssertEqual(VerticalTextReader.cellIndex(midX: 66.0 / 332, stripWidth: width, cellCount: 3), 0)
        XCTAssertEqual(VerticalTextReader.cellIndex(midX: 166.0 / 332, stripWidth: width, cellCount: 3), 1)
        XCTAssertEqual(VerticalTextReader.cellIndex(midX: 0.99, stripWidth: width, cellCount: 3), 2)
        XCTAssertEqual(VerticalTextReader.cellIndex(midX: 0, stripWidth: width, cellCount: 3), 0)
    }

    /// Une lecture ajoutée par l'app ne doit pas recouvrir des furigana déjà imprimés.
    func testPrintedRubyIsDetectedBesideColumn() throws {
        var pixels = [UInt8](repeating: 255, count: 400 * 400)
        func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
            for row in y..<(y + h) { for col in x..<(x + w) { pixels[row * 400 + col] = 0 } }
        }
        for k in 0..<6 { fill(200, 40 + k * 26, 20, 20) }
        for x in [260, 320] { for k in 0..<6 { fill(x, 40 + k * 26, 20, 20) } }
        for k in 0..<3 { fill(224, 40 + k * 10, 8, 8) }
        let found = try VerticalTextReader.detect(in: .init(width: 400, height: 400, pixels: pixels))
        XCTAssertEqual(found.columns.map(\.minX), [320, 260, 200])
        XCTAssertTrue(found.small.contains { $0.minX >= 219 && $0.minX <= 240 })
    }

    func testCleaningKeepsTextAndDropsNoise() {
        XCTAssertEqual(VerticalTextReader.cleaned("まあまあ：・"), "まあまあ…")
        XCTAssertEqual(VerticalTextReader.cleaned("分析しておかないと："), "分析しておかないと…")
        XCTAssertNil(VerticalTextReader.cleaned("PT"))
        XCTAssertNil(VerticalTextReader.cleaned("- 2"))
    }

    func testFuriganaColumnsAreLeftOut() throws {
        // Trois colonnes de texte larges de 20, une colonne de furigana large de 8.
        var pixels = [UInt8](repeating: 255, count: 400 * 400)
        func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
            for row in y..<(y + h) { for col in x..<(x + w) { pixels[row * 400 + col] = 0 } }
        }
        for x in [320, 260, 200] { for k in 0..<6 { fill(x, 40 + k * 26, 20, 20) } }
        for k in 0..<3 { fill(345, 40 + k * 12, 8, 8) }
        let columns = try VerticalTextReader.columns(in: .init(width: 400, height: 400, pixels: pixels))
        XCTAssertEqual(columns.map(\.minX), [320, 260, 200])
    }

    /// Revue Codex : l'ordre final du moteur est celui de la lecture, à droite d'abord, même avec du texte horizontal lu par Vision.
    func testEngineKeepsJapaneseOrder() throws {
        let image = try page(columns: ["重要な勝負になると", "負けなしですね", "それ以外の勝負だと"])
        let lines = try VisionOCREngine.run(image, languages: ["ja-JP", "en-US"])
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines.map(\.box.x), lines.map(\.box.x).sorted(by: >))
    }

    /// Contre-revue : des colonnes à côté de lignes horizontales gardent leur ordre, à égalité de nombre.
    func testEngineOrdersColumnsOnMixedPage() throws {
        let image = try page(columns: ["重要な勝負になると", "負けなしですね"], rows: ["日本語の教科書を読んでいます", "毎日少しずつ勉強しましょう"])
        let lines = try VisionOCREngine.run(image, languages: ["ja-JP", "en-US"])
        let columns = lines.filter(\.vertical).map(\.box.x)
        XCTAssertEqual(columns.count, 2)
        XCTAssertEqual(columns, columns.sorted(by: >))
        let rows = lines.filter { !$0.vertical }.map(\.box.y)
        XCTAssertEqual(rows, rows.sorted())
    }

    /// Contre-revue : beaucoup de petites lignes lues ailleurs n'empêchent plus de lire une colonne.
    func testManyKnownLinesElsewhereDoNotBlockColumns() throws {
        let known = (0..<40).map { NormBox(x: 0.01, y: 0.5 + Double($0) * 0.01, w: 0.02, h: 0.005) }
        let lines = try VerticalTextReader.read(try page(columns: ["重要な勝負になると"]), languages: ["ja-JP"], skipping: known)
        XCTAssertEqual(lines.map(\.text), ["重要な勝負になると"])
    }

    private func dots(_ pixels: inout [UInt8], size: Int, x: Range<Int>, y: Range<Int>) {
        for row in stride(from: y.lowerBound, to: y.upperBound, by: 5) {
            for column in stride(from: x.lowerBound, to: x.upperBound, by: 5) {
                for dy in 0...1 { for dx in 0...1 { pixels[(row + dy) * size + column + dx] = 0 } }
            }
        }
    }

    /// Une trame ne doit ni durer, ni inventer de texte, qu'elle remplisse la page ou reste sous l'ancien plafond (28 000 îlots).
    func testScreentoneStaysCheap() throws {
        for edge in [1395, 835] {
            let size = 1400
            var pixels = [UInt8](repeating: 255, count: size * size)
            dots(&pixels, size: size, x: 0..<edge, y: 0..<edge)
            let start = Date()
            XCTAssertEqual(try VerticalTextReader.columns(in: .init(width: size, height: size, pixels: pixels)), [])
            XCTAssertLessThan(Date().timeIntervalSince(start), 20, "mode debug")
        }
    }

    /// Seconde contre-revue : des îlots voisins, sans être une trame serrée, ne font pas disparaître la colonne d'à côté.
    func testNearbyIslandsKeepColumn() throws {
        let size = 1400
        var pixels = [UInt8](repeating: 255, count: size * size)
        for k in 0..<6 { for y in (100 + k * 34)..<(100 + k * 34 + 26) { for x in 1000..<1026 { pixels[y * size + x] = 0 } } }
        for index in 0..<81 {
            let x = 900 + (index % 9) * 8, y = 100 + (index / 9) * 8
            for dy in 0...1 { for dx in 0...1 { pixels[(y + dy) * size + x + dx] = 0 } }
        }
        XCTAssertTrue(try VerticalTextReader.columns(in: .init(width: size, height: size, pixels: pixels)).contains { $0.minX == 1000 })
    }

    /// Contre-revue : une trame dans un coin ne supprime pas une colonne de texte ailleurs.
    func testLocalScreentoneKeepsColumnElsewhere() throws {
        let size = 1400
        var pixels = [UInt8](repeating: 255, count: size * size)
        dots(&pixels, size: size, x: 0..<700, y: 0..<1395)
        for k in 0..<6 { for y in (100 + k * 34)..<(100 + k * 34 + 26) { for x in 1000..<1026 { pixels[y * size + x] = 0 } } }
        let columns = try VerticalTextReader.columns(in: .init(width: size, height: size, pixels: pixels))
        XCTAssertEqual(columns.map(\.minX), [1000])
    }

    /// Chapitre réel, à lancer à la main : KYOKASHO_MANGA_DIR=dossier swift test --filter testRealChapter. Rien de tiers dans le dépôt.
    func testRealChapterMeasure() throws {
        guard let path = ProcessInfo.processInfo.environment["KYOKASHO_MANGA_DIR"] else { throw XCTSkip("mesure manuelle") }
        let files = try FileManager.default.contentsOfDirectory(atPath: path).filter { $0.hasSuffix(".jpg") }.sorted()
        var before = 0, after = 0
        let start = Date()
        for file in files {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: path + "/" + file) as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let lines = try VisionOCREngine.run(image, languages: ["ja-JP", "en-US"])
            let vertical = lines.filter { $0.vertical && $0.confidence > 0 }.count
            before += lines.count - vertical
            after += lines.count
            print("PAGE \(file) lignes \(lines.count)")
            if ProcessInfo.processInfo.environment["KYOKASHO_MANGA_TEXT"] == file { lines.forEach { print("  ", $0.vertical ? "V" : "H", $0.hasPrintedRuby == true ? "R" : "-", String(format: "%.2f %.2f,%.2f", $0.confidence, $0.box.x, $0.box.y), $0.text, $0.charBoxes.count) } }
        }
        print("BILAN \(files.count) pages, \(after) lignes, \(Date().timeIntervalSince(start)) s")
    }
}
