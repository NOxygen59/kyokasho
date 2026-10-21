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
        XCTAssertEqual(Set(ModelSpec.all.map(\.id)).count, 3)
    }
}
