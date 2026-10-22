// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import XCTest
@testable import OCRKit

final class NeuralOCRTests: XCTestCase {
    func testImageOps() throws {
        // 3 × 2 : pixels numérotés pour suivre les déplacements.
        var px: [UInt8] = []
        for i in 0..<6 { px += [UInt8(i), UInt8(i), UInt8(i)] }
        let img = RGBImage(width: 3, height: 2, pixels: px)
        let rot = img.rotatedCounterClockwise()
        XCTAssertEqual(rot.width, 2)
        XCTAssertEqual(rot.height, 3)
        // Ligne du haut de l'image tournée = colonne de droite de l'original (2, 5).
        XCTAssertEqual([rot.pixels[0], rot.pixels[3]], [2, 5])
        XCTAssertEqual(img.cropped(x: 1, y: 1, width: 2, height: 1).pixels, [4, 4, 4, 5, 5, 5])
        let pad = img.padded(width: 4, height: 3, fill: 9)
        XCTAssertEqual(pad.pixels[3 * 3], 9)          // colonne ajoutée à droite
        XCTAssertEqual(pad.pixels[4 * 3 + 1], 3)      // (0, 1) inchangé
        let t = img.chw(mean: [0.5, 0.5, 0.5], std: [0.5, 0.5, 0.5])
        XCTAssertEqual(t.count, 18)
        XCTAssertEqual(t[0], -1, accuracy: 1e-6)
        // Aller-retour Core Graphics + redimensionnement.
        let cg = try XCTUnwrap(img.cgImage)
        XCTAssertEqual(RGBImage(cg)?.pixels, px)
        XCTAssertEqual(img.resized(width: 6, height: 4).width, 6)
    }

    func testDBPostprocess() {
        // Carte 20 × 10 avec un rectangle de texte (x 4…11, y 3…5).
        var map = [Float](repeating: 0, count: 200)
        for y in 3...5 { for x in 4...11 { map[y * 20 + x] = 0.9 } }
        map[0] = 0.9 // point isolé trop petit
        let boxes = DBPostprocess.boxes(map: map, width: 20, height: 10, outputSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(boxes.count, 1)
        let r = boxes[0].rect
        XCTAssertLessThan(r.minX, 40)
        XCTAssertGreaterThan(r.maxX, 120)
        XCTAssertLessThan(r.minY, 30)
        XCTAssertGreaterThan(boxes[0].score, 0.5)
    }

    func testCTC() {
        let charset = ["猫", "犬"]
        // 5 pas, 4 classes (blanc, 猫, 犬, espace) : 猫 猫 blanc 猫 犬 → 猫猫犬
        let steps: [[Float]] = [[0, 9, 0, 0], [0, 9, 0, 0], [9, 0, 0, 0], [0, 9, 0, 0], [0, 0, 9, 0]]
        let r = SequenceDecoder.ctc(steps.flatMap { $0 }, steps: 5, classes: 4, charset: charset + [" "])
        XCTAssertEqual(r.text, "猫猫犬")
        XCTAssertEqual(r.positions, [0, 3, 4])
    }

    func testPARSeqAndCharsets() {
        let logits: [[Float]] = [[0, 9, 0], [0, 0, 9], [9, 0, 0], [0, 9, 0]]
        XCTAssertEqual(SequenceDecoder.parseq(logits.flatMap { $0 }, steps: 4, classes: 3, charset: ["あ", "い"]), "あい")
        let yaml = "model:\n  charset_test: \"x\"\n  charset_train: \" !\\\"#\\\\a漢\"\n"
        XCTAssertEqual(SequenceDecoder.ndlCharset(yaml: yaml), [" ", "!", "\"", "#", "\\", "a", "漢"])
        XCTAssertEqual(SequenceDecoder.paddleCharset(dict: "一\r\n乙\n"), ["一", "乙", " "])
    }

    func testLayout() {
        let box = NormBox(x: 0, y: 0, w: 1, h: 0.1)
        let chars = NeuralLayout.characterBoxes(count: 2, centers: [0.25, 0.75], in: box, vertical: false)
        XCTAssertEqual(chars.map(\.x), [0, 0.5])
        XCTAssertEqual(chars[1].w, 0.5, accuracy: 1e-9)

        func line(_ t: String, x: Double, y: Double, w: Double, h: Double, v: Bool) -> OCRLine {
            OCRLine(text: t, box: NormBox(x: x, y: y, w: w, h: h), charBoxes: [], measuredCharBoxes: false, vertical: v, confidence: 1)
        }
        // Deux blocs verticaux : en haut colonnes A (droite) puis B, en bas colonne C.
        let page = [line("B", x: 0.5, y: 0.05, w: 0.04, h: 0.4, v: true), line("C", x: 0.7, y: 0.55, w: 0.04, h: 0.4, v: true),
                    line("A", x: 0.8, y: 0.05, w: 0.04, h: 0.4, v: true)]
        XCTAssertEqual(NeuralLayout.readingOrder(page).map(\.text), ["A", "B", "C"])
        let h = [line("2", x: 0.1, y: 0.5, w: 0.8, h: 0.03, v: false), line("1", x: 0.1, y: 0.1, w: 0.8, h: 0.03, v: false)]
        XCTAssertEqual(NeuralLayout.readingOrder(h).map(\.text), ["1", "2"])
    }

    func testModelStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("models-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ModelStore(root: root)
        XCTAssertFalse(store.isInstalled(.ppocr5))
        try FileManager.default.createDirectory(at: store.directory(.ppocr5), withIntermediateDirectories: true)
        for f in ModelSpec.ppocr5.files { try Data("x".utf8).write(to: store.url(.ppocr5, f.name)) }
        XCTAssertTrue(store.isInstalled(.ppocr5))
        XCTAssertEqual(store.installedSize(.ppocr5), 3)
        try store.delete(.ppocr5)
        XCTAssertFalse(store.isInstalled(.ppocr5))
        let file = root.appendingPathComponent("abc")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try ModelStore.sha256(of: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(Set(ModelSpec.all.map(\.id)).count, ModelSpec.all.count)
    }
}

final class CharacterHitTests: XCTestCase {
    func line(_ text: String, _ box: NormBox, vertical: Bool = false) -> OCRLine {
        OCRLine(text: text, box: box, charBoxes: CharacterLayout.proportional(text, in: box, vertical: vertical),
                measuredCharBoxes: false, vertical: vertical, confidence: 1)
    }

    func testTolerantHit() {
        // Grande ligne + petite ligne (furigana) juste au-dessus.
        let page = OCRPage(engine: "t", lines: [
            line("漢字", NormBox(x: 0.1, y: 0.10, w: 0.2, h: 0.05)),
            line("かんじ", NormBox(x: 0.1, y: 0.092, w: 0.2, h: 0.006)),
        ], durationMs: 0)
        // Dans la grande ligne, deuxième caractère.
        XCTAssertEqual(page.character(at: CGPoint(x: 0.25, y: 0.12))?.index, 1)
        // Juste au-dessus de la petite ligne : sans marge, la grande ligne (marge de 60 % de son
        // épaisseur) ; avec la marge du doigt, la petite ligne, plus proche.
        XCTAssertEqual(page.character(at: CGPoint(x: 0.12, y: 0.085))?.line, 0)
        XCTAssertEqual(page.character(at: CGPoint(x: 0.12, y: 0.085), tolerance: 0.01)?.line, 1)
        // Point dans la petite ligne (qui chevauche le haut de la grande) : la plus fine gagne.
        XCTAssertEqual(page.character(at: CGPoint(x: 0.28, y: 0.095), tolerance: 0.01)?.line, 1)
        // Loin de tout : rien.
        XCTAssertNil(page.character(at: CGPoint(x: 0.8, y: 0.8), tolerance: 0.01))
    }
}

final class RGBImageAccelerateTests: XCTestCase {
    func testConversionsMatchPixelLoops() throws {
        let w = 7, h = 5
        let pixels = (0..<(w * h * 3)).map { UInt8(($0 * 37) % 256) }
        let image = RGBImage(width: w, height: h, pixels: pixels)
        // Aller-retour Core Graphics : mêmes octets.
        let back = try XCTUnwrap(RGBImage(XCTUnwrap(image.cgImage)))
        XCTAssertEqual(back.pixels, pixels)
        // Tenseur : même calcul qu'une boucle simple (RGB puis BGR).
        let mean: [Float] = [0.485, 0.456, 0.406], std: [Float] = [0.229, 0.224, 0.225]
        for bgr in [false, true] {
            let fast = image.chw(mean: mean, std: std, bgr: bgr)
            for c in 0..<3 {
                let src = bgr ? 2 - c : c
                for i in 0..<(w * h) {
                    let slow = (Float(pixels[i * 3 + src]) / 255 - mean[c]) / std[c]
                    XCTAssertEqual(fast[c * w * h + i], slow, accuracy: 1e-5)
                }
            }
        }
    }
}

final class OCRLayoutTests: XCTestCase {
    private func line(_ text: String, x: Double, y: Double, w: Double, h: Double = 0.02, vertical: Bool = false) -> OCRLine {
        let box = NormBox(x: x, y: y, w: w, h: h)
        return OCRLine(text: text, box: box, charBoxes: CharacterLayout.proportional(text, in: box, vertical: vertical),
                       measuredCharBoxes: false, vertical: vertical, confidence: 1)
    }

    func testHeadingParagraphsAndTable() {
        let page = OCRPage(engine: "test", lines: [
            line("第一章", x: 0.1, y: 0.05, w: 0.2, h: 0.04),
            line("　日本語の文章です。これは", x: 0.12, y: 0.12, w: 0.78),
            line("続きの行です。", x: 0.1, y: 0.145, w: 0.3),
            line("　新しい段落。", x: 0.12, y: 0.17, w: 0.4),
            line("名前", x: 0.1, y: 0.3, w: 0.08), line("値段", x: 0.5, y: 0.3, w: 0.08),
            line("りんご", x: 0.1, y: 0.33, w: 0.1), line("百円", x: 0.5, y: 0.33, w: 0.08),
        ], durationMs: 0)
        let blocks = OCRLayout.blocks(page)
        XCTAssertEqual(blocks.first, .heading(level: 1, text: "第一章"))
        XCTAssertTrue(blocks.contains(.paragraph("日本語の文章です。これは続きの行です。")))
        XCTAssertTrue(blocks.contains(.paragraph("新しい段落。")))
        XCTAssertTrue(blocks.contains(.table([["名前", "値段"], ["りんご", "百円"]])))
        XCTAssertTrue(OCRLayout.markdown(blocks).contains("| 名前 | 値段 |"))
    }

    func testTwoColumnsStaySeparate() {
        let page = OCRPage(engine: "test", lines: [
            line("左の列の一行目", x: 0.05, y: 0.1, w: 0.4), line("左の列の二行目", x: 0.05, y: 0.125, w: 0.4),
            line("右の列の一行目", x: 0.55, y: 0.1, w: 0.4), line("右の列の二行目", x: 0.55, y: 0.125, w: 0.4),
        ], durationMs: 0)
        XCTAssertEqual(OCRLayout.blocks(page), [.paragraph("左の列の一行目左の列の二行目"), .paragraph("右の列の一行目右の列の二行目")])
    }
}

final class OCRLayoutRegionTests: XCTestCase {
    private func line(_ text: String, x: Double, y: Double, w: Double, h: Double = 0.02) -> OCRLine {
        let box = NormBox(x: x, y: y, w: w, h: h)
        return OCRLine(text: text, box: box, charBoxes: CharacterLayout.proportional(text, in: box, vertical: false),
                       measuredCharBoxes: false, vertical: false, confidence: 1)
    }

    func testRegionsDecideKindsAndOrder() {
        let page = OCRPage(engine: "test", lines: [
            line("12", x: 0.9, y: 0.95, w: 0.03),                   // folio (pied de page)
            line("右の段落です。", x: 0.55, y: 0.2, w: 0.4),
            line("見出し", x: 0.1, y: 0.05, w: 0.3),
            line("左の段落です。", x: 0.05, y: 0.2, w: 0.4),
        ], durationMs: 0)
        let regions = [
            OCRLayout.Region(box: NormBox(x: 0.04, y: 0.04, w: 0.5, h: 0.05), kind: .title(level: 1), order: 1),
            OCRLayout.Region(box: NormBox(x: 0.04, y: 0.18, w: 0.45, h: 0.1), kind: .text, order: 2),
            OCRLayout.Region(box: NormBox(x: 0.54, y: 0.18, w: 0.45, h: 0.1), kind: .text, order: 3),
            OCRLayout.Region(box: NormBox(x: 0.85, y: 0.93, w: 0.1, h: 0.05), kind: .ignored, order: 4),
        ]
        XCTAssertEqual(OCRLayout.blocks(page, regions: regions),
                       [.heading(level: 1, text: "見出し"), .paragraph("左の段落です。"), .paragraph("右の段落です。")])
    }
}

final class PageFrameTests: XCTestCase {
    /// Le repère doit coller au rendu réel de l'OCR (`PageRenderer`), pour chaque rotation intrinsèque.
    func testMatchesRendererForEveryRotation() throws {
        let square = CGRect(x: 20, y: 140, width: 20, height: 20)   // près du haut-gauche de la page non tournée
        for rotation in [0, 90, 180, 270] {
            let data = NSMutableData()
            var media = CGRect(x: 0, y: 0, width: 100, height: 200)
            let ctx = try XCTUnwrap(CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &media, nil))
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: Data(bytes: &media, count: MemoryLayout<CGRect>.size),
                              "Rotate": rotation] as CFDictionary)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(square)
            ctx.endPDFPage(); ctx.closePDF()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("frame-\(rotation).pdf")
            try (data as Data).write(to: url)
            PDFPool.release(url)
            let image = try PageRenderer.render(url: url, pageIndex: 0, longSide: 400)
            let rgb = try XCTUnwrap(RGBImage(image))
            // Centre des pixels noirs dans le rendu (normalisé, haut-gauche).
            var sx = 0.0, sy = 0.0, n = 0.0
            for y in 0..<rgb.height { for x in 0..<rgb.width where rgb.pixels[(y * rgb.width + x) * 3] < 128 { sx += Double(x); sy += Double(y); n += 1 } }
            XCTAssertGreaterThan(n, 0)
            let rendered = CGPoint(x: (sx / n + 0.5) / Double(rgb.width), y: (sy / n + 0.5) / Double(rgb.height))
            let pageRotation = try XCTUnwrap(CGPDFDocument(url as CFURL)?.page(at: 1)?.rotationAngle)
            XCTAssertEqual(Int(pageRotation), rotation, "le PDF d'essai doit porter la rotation")
            let frame = PageFrame(box: media, rotation: Int(pageRotation))
            let expected = frame.normalized(CGPoint(x: square.midX, y: square.midY))
            XCTAssertEqual(rendered.x, expected.x, accuracy: 0.02, "rotation \(rotation)")
            XCTAssertEqual(rendered.y, expected.y, accuracy: 0.02, "rotation \(rotation)")
            let back = frame.pagePoint(expected)
            XCTAssertEqual(back.x, square.midX, accuracy: 1e-6); XCTAssertEqual(back.y, square.midY, accuracy: 1e-6)
        }
    }
}

final class PageCleanerTests: XCTestCase {
    func testShadowedPaperBecomesWhiteAndInkStaysDark() {
        // Papier jauni avec une ombre de gauche à droite (220 → 110), trait d'encre au milieu (≈ 45 % du papier).
        let w = 160, h = 80
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                let paper = 220 - Double(x) * 110 / Double(w)
                let ink = (38...41).contains(y)
                let v = ink ? paper * 0.45 : paper
                let i = (y * w + x) * 3
                rgb[i] = UInt8(v); rgb[i + 1] = UInt8(v * 0.95); rgb[i + 2] = UInt8(v * 0.82)
            }
        }
        for mode in PageCleaner.Mode.allCases {
            let out = PageCleaner.clean(rgb, width: w, height: h, mode: mode)
            for x in [10, 80, 150] {
                XCTAssertGreaterThan(out[(10 * w + x) * 3], 235, "papier \(mode) x=\(x)")
                XCTAssertLessThan(out[(39 * w + x) * 3], 60, "encre \(mode) x=\(x)")
            }
        }
    }
}
